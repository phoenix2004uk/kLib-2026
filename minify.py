#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import dataclasses
import itertools
import math
import os
import re
import struct
import sys
import unicodedata
from pathlib import Path
from collections import defaultdict
from typing import Iterable, Iterator, Optional, Sequence

KOS_VERSION = "1.6.0.1"

# Token order mirrors kRISC.tpg / generated Scanner.cs.  For equal-length
# matches the scanner chooses the token with the smaller enum value.
TOKEN_SPECS = [
    ("PLUSMINUS", r"(?:\+|-)") ,
    ("MULT", r"\*"),
    ("DIV", r"/"),
    ("POWER", r"\^"),
    ("E", r"e((?=\d)|\b)"),
    ("NOT", r"not\b"),
    ("AND", r"and\b"),
    ("OR", r"or\b"),
    ("TRUEFALSE", r"true\b|\bfalse\b"),
    ("COMPARATOR", r"<>|>=|<=|=|>|<"),
    ("SET", r"set\b"),
    ("TO", r"to\b"),
    ("IS", r"is\b"),
    ("IF", r"if\b"),
    ("ELSE", r"else\b"),
    ("UNTIL", r"until\b"),
    ("STEP", r"step\b"),
    ("DO", r"do\b"),
    ("LOCK", r"lock\b"),
    ("UNLOCK", r"unlock\b"),
    ("PRINT", r"print\b"),
    ("AT", r"at\b"),
    ("ON", r"on\b"),
    ("TOGGLE", r"toggle\b"),
    ("WAIT", r"wait\b"),
    ("WHEN", r"when\b"),
    ("THEN", r"then\b"),
    ("OFF", r"off\b"),
    ("STAGE", r"stage\b"),
    ("CLEARSCREEN", r"clearscreen\b"),
    ("ADD", r"add\b"),
    ("REMOVE", r"remove\b"),
    ("LOG", r"log\b"),
    ("BREAK", r"break\b"),
    ("PRESERVE", r"preserve\b"),
    ("DECLARE", r"declare\b"),
    ("DEFINED", r"defined\b"),
    ("LOCAL", r"local\b"),
    ("GLOBAL", r"global\b"),
    ("PARAMETER", r"parameter\b"),
    ("FUNCTION", r"function\b"),
    ("RETURN", r"return\b"),
    ("SWITCH", r"switch\b"),
    ("COPY", r"copy\b"),
    ("FROM", r"from\b"),
    ("RENAME", r"rename\b"),
    ("VOLUME", r"volume\b"),
    ("FILE", r"file\b"),
    ("DELETE", r"delete\b"),
    ("EDIT", r"edit\b"),
    ("RUN", r"run\b"),
    ("RUNPATH", r"runpath\b"),
    ("RUNONCEPATH", r"runoncepath\b"),
    ("ONCE", r"once\b"),
    ("COMPILE", r"compile\b"),
    ("LIST", r"list\b"),
    ("REBOOT", r"reboot\b"),
    ("SHUTDOWN", r"shutdown\b"),
    ("FOR", r"for\b"),
    ("UNSET", r"unset\b"),
    ("CHOOSE", r"choose\b"),
    ("BRACKETOPEN", r"\("),
    ("BRACKETCLOSE", r"\)"),
    ("CURLYOPEN", r"\{"),
    ("CURLYCLOSE", r"\}"),
    ("SQUAREOPEN", r"\["),
    ("SQUARECLOSE", r"\]"),
    ("COMMA", r","),
    ("COLON", r":"),
    ("IN", r"in\b"),
    ("ARRAYINDEX", r"#"),
    ("ALL", r"all\b"),
    ("IDENTIFIER", r"[_\w&&\D]\w*"), # replaced below; Python re lacks \p{L}
    ("FILEIDENT", r"[_A-Za-z]\w*(?:\.[_A-Za-z]\w*)*"),
    ("INTEGER", r"\d[_\d]*"),
    ("DOUBLE", r"(?:\d+(?:_\d*)*)?\.\d+(?:_\d*)*"),
    ("STRING", r'@?"(?:""|[^"])*"'),
    ("EOI", r"\."),
    ("ATSIGN", r"@"),
    ("LAZYGLOBAL", r"lazyglobal\b"),
    ("CLOBBERBUILTINS", r"clobberbuiltins\b"),
    ("EOF", r"$"),
]

# Python's stdlib re does not have .NET \p{L}; kOS identifiers are Unicode.
# Use a dedicated predicate/regex for IDENTIFIER and FILEIDENT instead.
TOKEN_ORDER = {name: i for i, (name, _) in enumerate(TOKEN_SPECS)}
TOKEN_REGEX = {name: re.compile(pattern, re.IGNORECASE) for name, pattern in TOKEN_SPECS if name != "IDENTIFIER"}
COMMENT_RE = re.compile(r"//[^\n]*(?:\n|$)")

KEYWORDS = {
    name.lower() for name, _ in TOKEN_SPECS
    if name not in {
        "PLUSMINUS", "MULT", "DIV", "POWER", "E", "TRUEFALSE", "COMPARATOR",
        "BRACKETOPEN", "BRACKETCLOSE", "CURLYOPEN", "CURLYCLOSE", "SQUAREOPEN",
        "SQUARECLOSE", "COMMA", "COLON", "ARRAYINDEX", "IDENTIFIER", "FILEIDENT",
        "INTEGER", "DOUBLE", "STRING", "EOI", "ATSIGN", "EOF"
    }
}
# actual keyword spellings differ from token names for a few terminals
KEYWORD_TEXT = {
    "not", "and", "or", "set", "to", "is", "if", "else", "until", "step", "do",
    "lock", "unlock", "print", "at", "on", "toggle", "wait", "when", "then", "off",
    "stage", "clearscreen", "add", "remove", "log", "break", "preserve", "declare",
    "defined", "local", "global", "parameter", "function", "return", "switch", "copy",
    "from", "rename", "volume", "file", "delete", "edit", "run", "runpath",
    "runoncepath", "once", "compile", "list", "reboot", "shutdown", "for", "unset",
    "choose", "in", "all", "lazyglobal", "clobberbuiltins", "true", "false"
}

# One-character built-ins verified in kOS 1.6.0.1 source.  We intentionally use
# underscore-prefixed names after the safe one-character pool, avoiding the need
# to guess about two-character built-ins such as UP.
ONE_CHAR_BUILTINS = {"e", "q", "r", "v"}
# Compiler/KS/UserFunction.cs (kOS 1.6.0.1): these lock names have special
# FlyByWire behaviour.  They must never be renamed, even if explicitly LOCAL,
# because changing the spelling changes whether the compiler treats the lock as
# a system control lock.
SYSTEM_LOCKS = {"throttle", "steering", "wheelthrottle", "wheelsteering"}
ONE_CHAR_POOL = [c for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ_" if c.lower() not in ONE_CHAR_BUILTINS]

class MinifyError(Exception):
    pass

@dataclasses.dataclass(frozen=True)
class Token:
    kind: str
    text: str
    start: int
    end: int

    def fingerprint(self):
        if self.kind in {"IDENTIFIER", "FILEIDENT"}:
            return (self.kind, self.text.lower())
        return (self.kind, self.text)

@dataclasses.dataclass(frozen=True)
class ScanProbe:
    """One *actual* TinyPG scanner probe at a token position.

    Failed lookaheads matter: removing whitespace can turn a previously
    UNDETERMINED optional lookahead into a token and change the parser branch.
    """
    expected: tuple[str, ...]
    result_kind: str

@dataclasses.dataclass(frozen=True)
class ScanEvent:
    """One consumed token and every scanner probe made at its position."""
    kind: str
    text: str
    probes: tuple[ScanProbe, ...]

@dataclasses.dataclass
class Node:
    kind: str
    children: list[object] = dataclasses.field(default_factory=list)
    attrs: dict[str, object] = dataclasses.field(default_factory=dict)

    def terminals(self) -> Iterator[Token]:
        for child in self.children:
            if isinstance(child, Token):
                yield child
            elif isinstance(child, Node):
                yield from child.terminals()
            elif isinstance(child, list):
                for item in child:
                    if isinstance(item, Token):
                        yield item
                    elif isinstance(item, Node):
                        yield from item.terminals()

    def fingerprint(self):
        return (
            self.kind,
            tuple(
                child.fingerprint() if isinstance(child, (Node, Token))
                else tuple(x.fingerprint() for x in child if isinstance(x, (Node, Token))) if isinstance(child, list)
                else child
                for child in self.children
            ),
            tuple(sorted((k, _fp_value(v)) for k, v in self.attrs.items() if k not in {"scope", "symbol"}))
        )

def _fp_value(v):
    if isinstance(v, Token):
        return v.fingerprint()
    if isinstance(v, Node):
        return v.fingerprint()
    if isinstance(v, (list, tuple)):
        return tuple(_fp_value(x) for x in v)
    if isinstance(v, dict):
        return tuple(sorted((k, _fp_value(x)) for k, x in v.items()))
    return v

def _is_ident_start(ch: str) -> bool:
    # .NET \p{L}: Lu, Ll, Lt, Lm, Lo.
    return ch == "_" or unicodedata.category(ch) in {"Lu", "Ll", "Lt", "Lm", "Lo"}

def _is_ident_continue(ch: str) -> bool:
    # .NET \w used by kOS IDENTIFIER: letters + Mn + Nd + Pc.
    return unicodedata.category(ch) in {"Lu", "Ll", "Lt", "Lm", "Lo", "Mn", "Nd", "Pc"}

def _is_kos_whitespace_char(ch: str) -> bool:
    r"""Match kRISC.tpg WHITESPACE -> (\s|\p{C}) at one character."""
    return ch.isspace() or unicodedata.category(ch).startswith("C")

def _skip_kos_whitespace(source: str, pos: int) -> int:
    i = pos
    while i < len(source) and _is_kos_whitespace_char(source[i]):
        i += 1
    return i

def _match_identifier(src: str, pos: int) -> int:
    if pos >= len(src) or not _is_ident_start(src[pos]):
        return 0
    i = pos + 1
    while i < len(src) and _is_ident_continue(src[i]):
        i += 1
    return i - pos

def _match_fileident(src: str, pos: int) -> int:
    first = _match_identifier(src, pos)
    if not first:
        return 0
    i = pos + first
    while i < len(src) and src[i] == ".":
        nxt = _match_identifier(src, i + 1)
        if not nxt:
            break
        i += 1 + nxt
    return i - pos

class Scanner:
    """Faithful model of the generated TinyPG scanner used by kOS 1.6.0.1."""

    def __init__(self, source: str, capture_trace: bool = False):
        self.source = source
        # TOKEN_REGEX is compiled case-insensitively.  Matching the original
        # source avoids Python Unicode lowercasing expansions changing offsets.
        self.lower = source
        self.pos = 0
        self.lookahead_token: Optional[Token] = None
        self.capture_trace = capture_trace
        self.trace: list[ScanEvent] = []
        self._pending_probes: list[ScanProbe] = []
        self._expected_intern: dict[tuple[str, ...], tuple[str, ...]] = {}

    def _intern_expected(self, expected: tuple[str, ...]) -> tuple[str, ...]:
        cached = self._expected_intern.get(expected)
        if cached is not None:
            return cached
        self._expected_intern[expected] = expected
        return expected

    def _skip(self, pos: int) -> int:
        while True:
            end = _skip_kos_whitespace(self.source, pos)
            if end != pos:
                pos = end
                continue
            m = COMMENT_RE.match(self.source, pos)
            if m:
                pos = m.end()
                continue
            return pos

    def _match(self, kind: str, pos: int) -> int:
        if kind == "IDENTIFIER":
            n = _match_identifier(self.source, pos)
            return n if n else -1
        if kind == "FILEIDENT":
            n = _match_fileident(self.source, pos)
            return n if n else -1
        if kind == "EOF":
            return 0 if pos == len(self.source) else -1
        m = TOKEN_REGEX[kind].match(self.lower, pos)
        return (m.end() - pos) if m and m.start() == pos else -1

    def lookahead(self, *expected: str) -> Token:
        if self.lookahead_token is not None and self.lookahead_token.kind not in {"UNDETERMINED", "NONE"}:
            return self.lookahead_token

        pos = self._skip(self.pos)
        candidates = expected or tuple(name for name, _ in TOKEN_SPECS)
        best_kind = "UNDETERMINED"
        best_len = -1
        best_order = 10**9
        for kind in candidates:
            n = self._match(kind, pos)
            if n < 0:
                continue
            order = TOKEN_ORDER.get(kind, 10**8)
            if n > best_len or (n == best_len and order < best_order):
                best_len = n
                best_order = order
                best_kind = kind

        if best_len >= 0:
            tok = Token(best_kind, self.source[pos:pos + best_len], pos, pos + best_len)
        else:
            end = min(pos + 1, len(self.source))
            tok = Token("UNDETERMINED", self.source[pos:end] if pos < len(self.source) else "EOF", pos, end)

        if self.capture_trace:
            exp = self._intern_expected(tuple(candidates))
            self._pending_probes.append(ScanProbe(exp, tok.kind))

        self.lookahead_token = tok
        return tok

    def scan(self, *expected: str) -> Token:
        tok = self.lookahead(*expected)
        if self.capture_trace and tok.kind != "EOF":
            self.trace.append(ScanEvent(tok.kind, tok.text, tuple(self._pending_probes)))
            self._pending_probes.clear()
        self.lookahead_token = None
        self.pos = tok.end
        return tok

class Parser:
    INSTRUCTION_STARTS = (
        "EOI", "SET", "IF", "UNTIL", "FROM", "UNLOCK", "PRINT", "ON", "TOGGLE", "WAIT",
        "WHEN", "STAGE", "CLEARSCREEN", "ADD", "REMOVE", "LOG", "BREAK", "PRESERVE",
        "PARAMETER", "FUNCTION", "LOCK", "DECLARE", "LOCAL", "GLOBAL", "RETURN", "SWITCH",
        "COPY", "RENAME", "DELETE", "EDIT", "RUN", "RUNPATH", "RUNONCEPATH", "COMPILE", "LIST",
        "REBOOT", "SHUTDOWN", "FOR", "UNSET", "CURLYOPEN", "ATSIGN", "IDENTIFIER", "FILEIDENT"
    )

    def __init__(self, source: str, capture_trace: bool = False):
        self.source = source
        self.scanner = Scanner(source, capture_trace=capture_trace)

    def error(self, message: str, tok: Optional[Token] = None):
        tok = tok or self.scanner.lookahead()
        line = self.source.count("\n", 0, tok.start) + 1
        col = tok.start - self.source.rfind("\n", 0, tok.start)
        raise MinifyError(f"{message} at {line}:{col} near {tok.text!r}")

    def take(self, kind: str) -> Token:
        tok = self.scanner.scan(kind)
        if tok.kind != kind:
            self.error(f"expected {kind}, got {tok.kind}", tok)
        return tok

    def maybe(self, *kinds: str) -> Optional[Token]:
        tok = self.scanner.lookahead(*kinds)
        if tok.kind in kinds:
            return self.scanner.scan(tok.kind)
        return None

    def parse(self) -> Node:
        statements = []
        while True:
            tok = self.scanner.lookahead(*(self.INSTRUCTION_STARTS + ("EOF",)))
            if tok.kind == "EOF":
                self.take("EOF")
                break
            statements.append(self.parse_instruction())
        return Node("program", statements)

    def parse_instruction(self) -> Node:
        tok = self.scanner.lookahead(*self.INSTRUCTION_STARTS)
        kind = tok.kind
        if kind == "EOI":
            return Node("empty", [self.take("EOI")])
        if kind == "SET": return self.parse_set()
        if kind == "IF": return self.parse_if()
        if kind == "UNTIL": return self.parse_until()
        if kind == "FROM": return self.parse_from()
        if kind == "UNLOCK": return self.parse_simple_ident_stmt("unlock", "UNLOCK", allow_all=True)
        if kind == "PRINT": return self.parse_print()
        if kind == "ON": return self.parse_on()
        if kind == "TOGGLE": return self.parse_simple_var_stmt("toggle", "TOGGLE")
        if kind == "WAIT": return self.parse_wait()
        if kind == "WHEN": return self.parse_when()
        if kind == "STAGE": return self.parse_keyword_eoi("stage", "STAGE")
        if kind == "CLEARSCREEN": return self.parse_keyword_eoi("clearscreen", "CLEARSCREEN")
        if kind == "ADD": return self.parse_expr_stmt("add", "ADD")
        if kind == "REMOVE": return self.parse_expr_stmt("remove", "REMOVE")
        if kind == "LOG": return self.parse_log()
        if kind == "BREAK": return self.parse_keyword_eoi("break", "BREAK")
        if kind == "PRESERVE": return self.parse_keyword_eoi("preserve", "PRESERVE")
        if kind in {"PARAMETER", "FUNCTION", "LOCK", "DECLARE", "LOCAL", "GLOBAL"}:
            return self.parse_declare()
        if kind == "RETURN": return self.parse_return()
        if kind == "SWITCH": return self.parse_switch()
        if kind == "COPY": return self.parse_copy()
        if kind == "RENAME": return self.parse_rename()
        if kind == "DELETE": return self.parse_delete()
        if kind == "EDIT": return self.parse_expr_stmt("edit", "EDIT")
        if kind == "RUN": return self.parse_run()
        if kind == "RUNPATH": return self.parse_runpath(False)
        if kind == "RUNONCEPATH": return self.parse_runpath(True)
        if kind == "COMPILE": return self.parse_compile()
        if kind == "LIST": return self.parse_list_stmt()
        if kind == "REBOOT": return self.parse_keyword_eoi("reboot", "REBOOT")
        if kind == "SHUTDOWN": return self.parse_keyword_eoi("shutdown", "SHUTDOWN")
        if kind == "FOR": return self.parse_for()
        if kind == "UNSET": return self.parse_simple_ident_stmt("unset", "UNSET", allow_all=True)
        if kind == "CURLYOPEN": return self.parse_block(expression=False)
        if kind == "ATSIGN": return self.parse_directive()
        if kind in {"IDENTIFIER", "FILEIDENT"}: return self.parse_identifier_led_stmt()
        self.error("cannot parse instruction", tok)

    def parse_keyword_eoi(self, name: str, keyword: str) -> Node:
        return Node(name, [self.take(keyword), self.take("EOI")])

    def parse_expr_stmt(self, name: str, keyword: str) -> Node:
        return Node(name, [self.take(keyword), self.parse_expr(), self.take("EOI")])

    def parse_simple_ident_stmt(self, name: str, keyword: str, allow_all=False) -> Node:
        items = [self.take(keyword)]
        tok = self.scanner.lookahead("IDENTIFIER", "ALL") if allow_all else self.scanner.lookahead("IDENTIFIER")
        if tok.kind == "ALL" and allow_all: items.append(self.take("ALL"))
        else: items.append(self.take("IDENTIFIER"))
        items.append(self.take("EOI"))
        return Node(name, items)

    def parse_simple_var_stmt(self, name: str, keyword: str) -> Node:
        return Node(name, [self.take(keyword), self.parse_suffix(), self.take("EOI")])

    def parse_set(self) -> Node:
        items = [self.take("SET")]
        pairs = []
        while True:
            target = self.parse_suffix()
            to = self.take("TO")
            value = self.parse_expr()
            pairs.append((target, to, value))
            comma = self.maybe("COMMA")
            if not comma:
                break
            items.append(comma)
        items.append(self.take("EOI"))
        return Node("set", items, {"pairs": pairs})

    def parse_if(self) -> Node:
        kw = self.take("IF")
        cond = self.parse_expr()
        then = self.parse_instruction()
        extra = self.maybe("EOI")
        els = None
        else_tok = None
        if self.scanner.lookahead("ELSE", "EOI", "SET", "IF", "UNTIL", "FROM", "UNLOCK", "PRINT", "ON", "TOGGLE", "WAIT", "WHEN", "STAGE", "CLEARSCREEN", "ADD", "REMOVE", "LOG", "BREAK", "PRESERVE", "PARAMETER", "FUNCTION", "LOCK", "DECLARE", "LOCAL", "GLOBAL", "RETURN", "SWITCH", "COPY", "RENAME", "DELETE", "EDIT", "RUN", "RUNPATH", "RUNONCEPATH", "COMPILE", "LIST", "REBOOT", "SHUTDOWN", "FOR", "UNSET", "CURLYOPEN", "ATSIGN", "IDENTIFIER", "FILEIDENT", "CURLYCLOSE", "EOF").kind == "ELSE":
            else_tok = self.take("ELSE")
            els = self.parse_instruction()
            self.maybe("EOI")
        return Node("if", [kw, cond, then] + ([extra] if extra else []) + ([else_tok, els] if els else []), {"cond": cond, "then": then, "else": els})

    def parse_until(self) -> Node:
        kw = self.take("UNTIL")
        cond = self.parse_expr()
        body = self.parse_instruction()
        self.maybe("EOI")
        return Node("until", [kw, cond, body], {"cond": cond, "body": body})

    def parse_from(self) -> Node:
        kw = self.take("FROM")
        init = self.parse_block(False)
        u = self.take("UNTIL")
        cond = self.parse_expr()
        s = self.take("STEP")
        step = self.parse_block(False)
        d = self.take("DO")
        body = self.parse_instruction()
        self.maybe("EOI")
        return Node("from", [kw, init, u, cond, s, step, d, body], {"init": init, "cond": cond, "step": step, "body": body})

    def parse_print(self) -> Node:
        items = [self.take("PRINT"), self.parse_expr()]
        if self.scanner.lookahead("AT", "EOI").kind == "AT":
            items += [self.take("AT"), self.take("BRACKETOPEN"), self.parse_expr(), self.take("COMMA"), self.parse_expr(), self.take("BRACKETCLOSE")]
        items.append(self.take("EOI"))
        return Node("print", items)

    def parse_on(self) -> Node:
        kw = self.take("ON")
        target = self.parse_suffix()
        body = self.parse_instruction()
        self.maybe("EOI")
        return Node("on", [kw, target, body], {"target": target, "body": body})

    def parse_wait(self) -> Node:
        items = [self.take("WAIT")]
        if self.scanner.lookahead("UNTIL", "PLUSMINUS", "NOT", "DEFINED", "INTEGER", "DOUBLE", "TRUEFALSE", "IDENTIFIER", "FILEIDENT", "BRACKETOPEN", "STRING", "CURLYOPEN", "CHOOSE").kind == "UNTIL":
            items.append(self.take("UNTIL"))
        items += [self.parse_expr(), self.take("EOI")]
        return Node("wait", items)

    def parse_when(self) -> Node:
        kw = self.take("WHEN")
        cond = self.parse_expr()
        then = self.take("THEN")
        body = self.parse_instruction()
        self.maybe("EOI")
        return Node("when", [kw, cond, then, body], {"cond": cond, "body": body})

    def parse_log(self) -> Node:
        return Node("log", [self.take("LOG"), self.parse_expr(), self.take("TO"), self.parse_expr(), self.take("EOI")])

    def parse_declare(self) -> Node:
        prefix = []
        modifier = None
        tok = self.scanner.lookahead("PARAMETER", "FUNCTION", "LOCK", "DECLARE", "LOCAL", "GLOBAL")
        if tok.kind == "DECLARE":
            prefix.append(self.take("DECLARE"))
            m = self.scanner.lookahead("LOCAL", "GLOBAL", "PARAMETER", "FUNCTION", "LOCK", "IDENTIFIER")
            if m.kind in {"LOCAL", "GLOBAL"}:
                modifier = m.kind.lower()
                prefix.append(self.take(m.kind))
        elif tok.kind in {"LOCAL", "GLOBAL"}:
            modifier = tok.kind.lower()
            prefix.append(self.take(tok.kind))
        head = self.scanner.lookahead("PARAMETER", "FUNCTION", "LOCK", "IDENTIFIER")
        if head.kind == "PARAMETER":
            return self.parse_parameter_clause(prefix, modifier)
        if head.kind == "FUNCTION":
            return self.parse_function_clause(prefix, modifier)
        if head.kind == "LOCK":
            return self.parse_lock_clause(prefix, modifier)
        return self.parse_identifier_clause(prefix, modifier)

    def parse_parameter_clause(self, prefix, modifier) -> Node:
        items = list(prefix) + [self.take("PARAMETER")]
        params = []
        while True:
            name = self.take("IDENTIFIER")
            op = None; default = None
            look = self.scanner.lookahead("TO", "IS", "COMMA", "EOI")
            if look.kind in {"TO", "IS"}:
                op = self.take(look.kind)
                default = self.parse_expr()
            params.append((name, op, default))
            c = self.maybe("COMMA")
            if not c: break
            items.append(c)
        items.append(self.take("EOI"))
        return Node("parameter_decl", items, {"modifier": modifier, "params": params})

    def parse_function_clause(self, prefix, modifier) -> Node:
        items = list(prefix) + [self.take("FUNCTION")]
        name = self.take("IDENTIFIER")
        body = self.parse_block(expression=False)
        self.maybe("EOI")
        items += [name, body]
        return Node("function_decl", items, {"modifier": modifier, "name": name, "body": body})

    def parse_lock_clause(self, prefix, modifier) -> Node:
        items = list(prefix) + [self.take("LOCK")]
        name = self.take("IDENTIFIER")
        to = self.take("TO")
        value = self.parse_expr()
        end = self.take("EOI")
        items += [name, to, value, end]
        return Node("lock_decl", items, {"modifier": modifier, "name": name, "value": value})

    def parse_identifier_clause(self, prefix, modifier) -> Node:
        items = list(prefix)
        decls = []
        while True:
            name = self.take("IDENTIFIER")
            op = self.scanner.lookahead("TO", "IS")
            if op.kind not in {"TO", "IS"}: self.error("expected TO or IS", op)
            op = self.take(op.kind)
            value = self.parse_expr()
            decls.append((name, op, value))
            c = self.maybe("COMMA")
            if not c: break
            items.append(c)
        items.append(self.take("EOI"))
        return Node("var_decl", items, {"modifier": modifier, "decls": decls})

    def parse_return(self) -> Node:
        items = [self.take("RETURN")]
        if self.scanner.lookahead("EOI", "PLUSMINUS", "NOT", "DEFINED", "INTEGER", "DOUBLE", "TRUEFALSE", "IDENTIFIER", "FILEIDENT", "BRACKETOPEN", "STRING", "CURLYOPEN", "CHOOSE").kind != "EOI":
            items.append(self.parse_expr())
        items.append(self.take("EOI"))
        return Node("return", items)

    def parse_switch(self) -> Node:
        return Node("switch", [self.take("SWITCH"), self.take("TO"), self.parse_expr(), self.take("EOI")])

    def parse_copy(self) -> Node:
        items = [self.take("COPY"), self.parse_expr()]
        d = self.scanner.lookahead("FROM", "TO")
        items += [self.take(d.kind), self.parse_expr(), self.take("EOI")]
        return Node("copy", items)

    def parse_rename(self) -> Node:
        items = [self.take("RENAME")]
        x = self.scanner.lookahead("VOLUME", "FILE", "PLUSMINUS", "NOT", "DEFINED", "INTEGER", "DOUBLE", "TRUEFALSE", "IDENTIFIER", "FILEIDENT", "BRACKETOPEN", "STRING", "CURLYOPEN", "CHOOSE")
        if x.kind in {"VOLUME", "FILE"}: items.append(self.take(x.kind))
        items += [self.parse_expr(), self.take("TO"), self.parse_expr(), self.take("EOI")]
        return Node("rename", items)

    def parse_delete(self) -> Node:
        items = [self.take("DELETE"), self.parse_expr()]
        if self.scanner.lookahead("FROM", "EOI").kind == "FROM": items += [self.take("FROM"), self.parse_expr()]
        items.append(self.take("EOI"))
        return Node("delete", items)

    def parse_run(self) -> Node:
        items = [self.take("RUN")]
        if self.scanner.lookahead("ONCE", "FILEIDENT", "STRING").kind == "ONCE": items.append(self.take("ONCE"))
        f = self.scanner.lookahead("FILEIDENT", "STRING")
        items.append(self.take(f.kind))
        if self.scanner.lookahead("BRACKETOPEN", "ON", "EOI").kind == "BRACKETOPEN":
            items.append(self.take("BRACKETOPEN"))
            if self.scanner.lookahead("BRACKETCLOSE", "PLUSMINUS", "NOT", "DEFINED", "INTEGER", "DOUBLE", "TRUEFALSE", "IDENTIFIER", "FILEIDENT", "BRACKETOPEN", "STRING", "CURLYOPEN", "CHOOSE").kind != "BRACKETCLOSE":
                items.append(self.parse_arglist())
            items.append(self.take("BRACKETCLOSE"))
        if self.scanner.lookahead("ON", "EOI").kind == "ON": items += [self.take("ON"), self.parse_expr()]
        items.append(self.take("EOI"))
        return Node("run", items)

    def parse_runpath(self, once: bool) -> Node:
        k = "RUNONCEPATH" if once else "RUNPATH"
        items = [self.take(k), self.take("BRACKETOPEN"), self.parse_expr()]
        if self.scanner.lookahead("COMMA", "BRACKETCLOSE").kind == "COMMA":
            items += [self.take("COMMA"), self.parse_arglist()]
        items += [self.take("BRACKETCLOSE"), self.take("EOI")]
        return Node("runoncepath" if once else "runpath", items)

    def parse_compile(self) -> Node:
        items = [self.take("COMPILE"), self.parse_expr()]
        if self.scanner.lookahead("TO", "EOI").kind == "TO": items += [self.take("TO"), self.parse_expr()]
        items.append(self.take("EOI"))
        return Node("compile", items)

    def parse_list_stmt(self) -> Node:
        items = [self.take("LIST")]
        if self.scanner.lookahead("IDENTIFIER", "EOI").kind == "IDENTIFIER":
            items.append(self.take("IDENTIFIER"))
            if self.scanner.lookahead("IN", "EOI").kind == "IN":
                items += [self.take("IN"), self.take("IDENTIFIER")]
        items.append(self.take("EOI"))
        return Node("list", items)

    def parse_for(self) -> Node:
        kw = self.take("FOR")
        iterator = self.take("IDENTIFIER")
        inn = self.take("IN")
        collection = self.parse_suffix()
        body = self.parse_instruction()
        self.maybe("EOI")
        return Node("for", [kw, iterator, inn, collection, body], {"iterator": iterator, "collection": collection, "body": body})

    def parse_directive(self) -> Node:
        items = [self.take("ATSIGN")]
        k = self.scanner.lookahead("LAZYGLOBAL", "CLOBBERBUILTINS")
        items.append(self.take(k.kind))
        v = self.scanner.lookahead("ON", "OFF")
        items += [self.take(v.kind), self.take("EOI")]
        return Node("directive", items, {"name": k.kind.lower(), "value": v.kind.lower()})

    def parse_identifier_led_stmt(self) -> Node:
        s = self.parse_suffix()
        items = [s]
        k = self.scanner.lookahead("ON", "OFF", "EOI")
        if k.kind in {"ON", "OFF"}: items.append(self.take(k.kind))
        items.append(self.take("EOI"))
        return Node("expr_stmt", items)

    def parse_block(self, expression: bool) -> Node:
        op = self.take("CURLYOPEN")
        stmts = []
        while self.scanner.lookahead(*(self.INSTRUCTION_STARTS + ("CURLYCLOSE",))).kind != "CURLYCLOSE":
            stmts.append(self.parse_instruction())
        cl = self.take("CURLYCLOSE")
        return Node("block_expr" if expression else "block", [op] + stmts + [cl], {"statements": stmts})

    # Expressions
    def parse_expr(self) -> Node:
        k = self.scanner.lookahead("CHOOSE", "CURLYOPEN", "PLUSMINUS", "NOT", "DEFINED", "INTEGER", "DOUBLE", "TRUEFALSE", "IDENTIFIER", "FILEIDENT", "BRACKETOPEN", "STRING")
        if k.kind == "CHOOSE": return self.parse_ternary()
        if k.kind == "CURLYOPEN": return self.parse_block(expression=True)
        return self.parse_or()

    def parse_ternary(self) -> Node:
        return Node("ternary", [self.take("CHOOSE"), self.parse_expr(), self.take("IF"), self.parse_expr(), self.take("ELSE"), self.parse_expr()])

    def parse_or(self) -> Node:
        node = self.parse_and(); children = [node]
        while self.scanner.lookahead("OR", "EOI", "COMMA", "BRACKETCLOSE", "SQUARECLOSE", "COLON", "POWER", "MULT", "DIV", "PLUSMINUS", "COMPARATOR", "AND", "IF", "ELSE", "TO", "FROM", "AT", "ON", "THEN", "STEP", "DO", "CURLYCLOSE").kind == "OR":
            children += [self.take("OR"), self.parse_and()]
        return Node("or", children)

    def parse_and(self) -> Node:
        node = self.parse_compare(); children=[node]
        while self.scanner.lookahead("AND", "OR", "EOI", "COMMA", "BRACKETCLOSE", "SQUARECLOSE", "COLON", "POWER", "MULT", "DIV", "PLUSMINUS", "COMPARATOR", "IF", "ELSE", "TO", "FROM", "AT", "ON", "THEN", "STEP", "DO", "CURLYCLOSE").kind == "AND":
            children += [self.take("AND"), self.parse_compare()]
        return Node("and", children)

    def parse_compare(self) -> Node:
        node=self.parse_arith(); children=[node]
        while self.scanner.lookahead("COMPARATOR", "AND", "OR", "EOI", "COMMA", "BRACKETCLOSE", "SQUARECLOSE", "IF", "ELSE", "TO", "FROM", "AT", "ON", "THEN", "STEP", "DO", "CURLYCLOSE").kind == "COMPARATOR":
            children += [self.take("COMPARATOR"), self.parse_arith()]
        return Node("compare", children)

    def parse_arith(self) -> Node:
        node=self.parse_mult(); children=[node]
        while self.scanner.lookahead("PLUSMINUS", "COMPARATOR", "AND", "OR", "EOI", "COMMA", "BRACKETCLOSE", "SQUARECLOSE", "IF", "ELSE", "TO", "FROM", "AT", "ON", "THEN", "STEP", "DO", "CURLYCLOSE").kind == "PLUSMINUS":
            children += [self.take("PLUSMINUS"), self.parse_mult()]
        return Node("arith", children)

    def parse_mult(self) -> Node:
        node=self.parse_unary(); children=[node]
        while self.scanner.lookahead("MULT", "DIV", "PLUSMINUS", "COMPARATOR", "AND", "OR", "EOI", "COMMA", "BRACKETCLOSE", "SQUARECLOSE", "IF", "ELSE", "TO", "FROM", "AT", "ON", "THEN", "STEP", "DO", "CURLYCLOSE").kind in {"MULT","DIV"}:
            k=self.scanner.lookahead("MULT","DIV").kind
            children += [self.take(k), self.parse_unary()]
        return Node("mult", children)

    def parse_unary(self) -> Node:
        items=[]
        k=self.scanner.lookahead("PLUSMINUS","NOT","DEFINED","INTEGER","DOUBLE","TRUEFALSE","IDENTIFIER","FILEIDENT","BRACKETOPEN","STRING")
        if k.kind in {"PLUSMINUS","NOT","DEFINED"}: items.append(self.take(k.kind))
        items.append(self.parse_factor())
        return Node("unary",items)

    def parse_factor(self) -> Node:
        children=[self.parse_suffix()]
        while self.scanner.lookahead("POWER","MULT","DIV","PLUSMINUS","COMPARATOR","AND","OR","EOI","COMMA","BRACKETCLOSE","SQUARECLOSE","IF","ELSE","TO","FROM","AT","ON","THEN","STEP","DO","CURLYCLOSE").kind=="POWER":
            children += [self.take("POWER"), self.parse_suffix()]
        return Node("factor",children)

    def parse_suffix(self) -> Node:
        children=[self.parse_suffixterm()]
        while self.scanner.lookahead("COLON","POWER","MULT","DIV","PLUSMINUS","COMPARATOR","AND","OR","EOI","COMMA","BRACKETCLOSE","SQUARECLOSE","IF","ELSE","TO","FROM","AT","ON","THEN","STEP","DO","CURLYCLOSE").kind=="COLON":
            children += [self.take("COLON"), self.parse_suffixterm()]
        return Node("suffix",children)

    def parse_suffixterm(self) -> Node:
        children=[self.parse_atom()]
        while True:
            k=self.scanner.lookahead("BRACKETOPEN","ATSIGN","ARRAYINDEX","SQUAREOPEN","COLON","POWER","MULT","DIV","PLUSMINUS","COMPARATOR","AND","OR","EOI","COMMA","BRACKETCLOSE","SQUARECLOSE","IF","ELSE","TO","FROM","AT","ON","THEN","STEP","DO","CURLYCLOSE").kind
            if k=="BRACKETOPEN":
                children.append(self.take("BRACKETOPEN"))
                if self.scanner.lookahead("BRACKETCLOSE","CHOOSE","CURLYOPEN","PLUSMINUS","NOT","DEFINED","INTEGER","DOUBLE","TRUEFALSE","IDENTIFIER","FILEIDENT","BRACKETOPEN","STRING").kind!="BRACKETCLOSE":
                    children.append(self.parse_arglist())
                children.append(self.take("BRACKETCLOSE"))
            elif k=="ATSIGN": children.append(self.take("ATSIGN"))
            elif k=="ARRAYINDEX":
                children.append(self.take("ARRAYINDEX"))
                a=self.scanner.lookahead("IDENTIFIER","INTEGER")
                children.append(self.take(a.kind))
            elif k=="SQUAREOPEN":
                children += [self.take("SQUAREOPEN"), self.parse_expr(), self.take("SQUARECLOSE")]
            else: break
        return Node("suffixterm",children)

    def parse_arglist(self) -> Node:
        children=[self.parse_expr()]
        while self.scanner.lookahead("COMMA","BRACKETCLOSE").kind=="COMMA":
            children += [self.take("COMMA"), self.parse_expr()]
        return Node("arglist",children)

    def parse_atom(self) -> Node:
        k=self.scanner.lookahead("INTEGER","DOUBLE","TRUEFALSE","IDENTIFIER","FILEIDENT","BRACKETOPEN","STRING")
        if k.kind in {"INTEGER","DOUBLE"}:
            return self.parse_scientific()
        if k.kind in {"TRUEFALSE","IDENTIFIER","FILEIDENT","STRING"}:
            return Node("atom",[self.take(k.kind)], {"token_kind":k.kind})
        if k.kind=="BRACKETOPEN":
            return Node("group",[self.take("BRACKETOPEN"),self.parse_expr(),self.take("BRACKETCLOSE")])
        self.error("expected atom",k)

    def parse_scientific(self) -> Node:
        k=self.scanner.lookahead("INTEGER","DOUBLE")
        children=[self.take(k.kind)]
        if self.scanner.lookahead("E","POWER","MULT","DIV","PLUSMINUS","COMPARATOR","AND","OR","EOI","COMMA","BRACKETCLOSE","SQUARECLOSE","IF","ELSE","TO","FROM","AT","ON","THEN","STEP","DO","CURLYCLOSE").kind=="E":
            children.append(self.take("E"))
            if self.scanner.lookahead("PLUSMINUS","INTEGER").kind=="PLUSMINUS": children.append(self.take("PLUSMINUS"))
            children.append(self.take("INTEGER"))
        return Node("number",children)

# ---------------------------------------------------------------------------
# Scope and identifier analysis
# ---------------------------------------------------------------------------

@dataclasses.dataclass
class Scope:
    parent: Optional["Scope"]
    owner: Node
    depth: int
    children: list["Scope"] = dataclasses.field(default_factory=list)
    symbols: list["Symbol"] = dataclasses.field(default_factory=list)
    # Nearest deferred-execution body (anonymous/user function or LOCK body)
    # whose runtime call captures this scope chain.  References below
    # this boundary can observe variables added later to captured parent
    # VariableScopes, because kOS closures retain the live VariableScope
    # objects rather than snapshotting their contents.
    deferred_root: Optional["Scope"] = None

    def is_ancestor_of(self, other: "Scope") -> bool:
        cur: Optional[Scope] = other
        while cur is not None:
            if cur is self:
                return True
            cur = cur.parent
        return False

@dataclasses.dataclass
class Symbol:
    name: str
    token: Token
    scope: Scope
    kind: str
    available_from_start: bool
    renamable: bool
    available_at: int
    decl_tokens: list[Token] = dataclasses.field(default_factory=list)
    refs: list[Token] = dataclasses.field(default_factory=list)
    new_name: Optional[str] = None

    @property
    def occurrences(self) -> int:
        return len(self.decl_tokens) + len(self.refs)

    @property
    def declaration_pos(self) -> int:
        return min((t.start for t in self.decl_tokens), default=self.token.start)


_STORAGE_KINDS = {"local", "parameter", "for", "global"}
_CALLABLE_KINDS = {"function", "lock"}


def _node_last_end(node: Optional[Node], fallback: int = 0) -> int:
    if node is None:
        return fallback
    return max((t.end for t in node.terminals()), default=fallback)


class SymbolAnalyzer:
    """Binding model derived from the kOS 1.6.0.1 compiler.

    Important compiler behaviours mirrored here:
      * Start, instruction blocks, FOR, and LOCK expressions own scopes.
      * bare file-scope functions are GLOBAL; bare nested functions are LOCAL.
      * bare LOCK declarations are GLOBAL even when written in a nested block.
      * ordinary declarations/default parameters are stored only *after* their
        initializer/default expression has been evaluated.
      * a FOR iterator is stored only after its collection expression is evaluated.
      * FROM is analysed after the compiler's RearrangeLoopFromNode transform: the
        initializer block encloses the condition/body/step, while STEP's own braces
        do not introduce a surviving scope.
      * functions/locks use the compiler's user-function namespace, which has
        precedence over ordinary variable lookup for expression suffix heads.
      * deferred bodies capture live VariableScope objects.  A later store into a
        captured parent scope can therefore shadow an ancestor name when the body
        eventually executes, even though it was unavailable at declaration time.

    Alpha-renaming is binding-aware: distinct symbols may deliberately reuse the
    same generated spelling when replaying the compiler/runtime lookup rules shows
    that every reference still resolves to the same symbol.  Intrinsically dynamic
    cases such as duplicate local stores or a declaration sharing a spelling with
    an unresolved/external reference remain fail-closed.
    """

    def __init__(self, tree: Node):
        self.tree = tree
        self.root = Scope(None, tree, 0)
        self.node_scope: dict[int, Scope] = {id(tree): self.root}
        self.symbols: list[Symbol] = []
        self.unresolved: set[str] = set()
        self.unresolved_refs: list[Token] = []
        self.ambiguous: set[str] = set()
        self.binding_by_span: dict[tuple[int, int], Symbol] = {}
        # For every bound reference remember the exact lookup mode and lexical
        # scope used by the compiler model.  This lets the allocator determine
        # whether two symbols may safely share a final spelling instead of
        # conservatively forbidding all ancestor/descendant shadowing.
        self.ref_context_by_span: dict[tuple[int, int], tuple[Scope, str]] = {}
        self.ref_token_by_span: dict[tuple[int, int], Token] = {}
        self._conflict_cache: dict[tuple[int, int], bool] = {}
        self._build_scopes_and_decls(tree, self.root, is_root=True, stable=True)
        self._collect_refs(tree, self.root)
        self._finalize_rename_safety()

    def _new_scope(self, node: Node, parent: Scope, *, deferred: bool = False) -> Scope:
        scope = Scope(parent, node, parent.depth + 1)
        # Anonymous function expressions are always deferred and compiled as
        # UserDelegates with closure capture.  Named function bodies can request
        # the same treatment without mutating the parsed AST.
        if deferred or node.kind == "block_expr":
            scope.deferred_root = scope
        else:
            scope.deferred_root = parent.deferred_root
        parent.children.append(scope)
        self.node_scope[id(node)] = scope
        return scope

    def _declare_storage(self, token: Token, scope: Scope, kind: str,
                         available_at: int, renamable: bool) -> Symbol:
        lname = token.text.lower()
        # LOCAL/PARAMETER/FOR stores all use the current VariableScope.  Repeating
        # the same spelling in that scope overwrites/reuses that same storage.
        for sym in scope.symbols:
            if sym.kind in _STORAGE_KINDS and sym.name == lname:
                sym.decl_tokens.append(token)
                sym.available_at = min(sym.available_at, available_at)
                sym.renamable = sym.renamable and renamable
                self.binding_by_span[(token.start, token.end)] = sym
                return sym
        sym = Symbol(
            lname, token, scope, kind, False, renamable, available_at,
            decl_tokens=[token],
        )
        scope.symbols.append(sym)
        self.symbols.append(sym)
        self.binding_by_span[(token.start, token.end)] = sym
        return sym

    def _declare_callable(self, token: Token, scope: Scope, kind: str,
                          renamable: bool) -> Symbol:
        sym = Symbol(
            token.text.lower(), token, scope, kind, True, renamable, -1,
            decl_tokens=[token],
        )
        scope.symbols.append(sym)
        self.symbols.append(sym)
        self.binding_by_span[(token.start, token.end)] = sym
        return sym

    def _build_existing_block(self, node: Node, scope: Scope, *, stable: bool) -> None:
        node.attrs["scope"] = scope
        self.node_scope[id(node)] = scope
        for stmt in node.attrs.get("statements", []):
            self._build_scopes_and_decls(stmt, scope, stable=stable)

    def _build_scopes_and_decls(self, node: Node, scope: Scope, is_root=False,
                                stable: bool = True, deferred: bool = False):
        node.attrs["scope"] = scope
        k = node.kind

        if k == "program":
            for stmt in node.children:
                if isinstance(stmt, Node):
                    self._build_scopes_and_decls(stmt, scope, stable=True)
            return

        if k in {"block", "block_expr"}:
            child = self._new_scope(node, scope, deferred=deferred)
            self._build_existing_block(node, child, stable=True)
            return

        if k == "from":
            # Compiler.RearrangeLoopFromNode turns FROM {init} ... STEP {step}
            # DO body into { init; UNTIL cond { body; step; } }.  Reproduce the
            # surviving scopes rather than the source brace layout.
            init = node.attrs["init"]
            loop_scope = self._new_scope(init, scope)
            node.attrs["scope"] = loop_scope
            self.node_scope[id(node)] = loop_scope
            self._build_existing_block(init, loop_scope, stable=True)
            self._build_scopes_and_decls(node.attrs["cond"], loop_scope, stable=True)

            body = node.attrs["body"]
            if body.kind in {"block", "block_expr"}:
                self._build_scopes_and_decls(body, loop_scope, stable=True)
                effective_step_scope = body.attrs["scope"]
            else:
                # A declaration used as a naked loop body is repeatedly/conditionally
                # executed in the loop scope; leave such declarations unrenamed.
                self._build_scopes_and_decls(body, loop_scope, stable=False)
                effective_step_scope = loop_scope

            step = node.attrs["step"]
            # STEP's source braces are removed by RearrangeLoopFromNode.  Its
            # statements execute after the body and are inherently cyclic, so
            # declarations there are conservatively fixed.
            self._build_existing_block(step, effective_step_scope, stable=False)
            return

        if k == "for":
            child = self._new_scope(node, scope)
            node.attrs["scope"] = child
            self._build_scopes_and_decls(node.attrs["collection"], child, stable=True)
            it: Token = node.attrs["iterator"]
            self._declare_storage(
                it, child, "for", _node_last_end(node.attrs["collection"], it.end), True
            )
            body = node.attrs["body"]
            self._build_scopes_and_decls(
                body, child, stable=(body.kind in {"block", "block_expr"})
            )
            return

        if k == "function_decl":
            tok: Token = node.attrs["name"]
            modifier = node.attrs.get("modifier")
            # Compiler.GetStorageModifierForDeclare: a bare function is GLOBAL
            # only when its containing block is Start; nested bare functions are LOCAL.
            is_global = modifier == "global" or (modifier is None and scope is self.root)
            target_scope = self.root if is_global else scope
            self._declare_callable(tok, target_scope, "function", not is_global)
            # Function body lexical parent is where it was written, even for an
            # explicitly GLOBAL nested function.  It executes later, so captured
            # parent scopes may contain stores that occur after this declaration.
            self._build_scopes_and_decls(
                node.attrs["body"], scope, stable=True, deferred=True
            )
            return

        if k == "lock_decl":
            tok: Token = node.attrs["name"]
            modifier = node.attrs.get("modifier")
            # Compiler.GetStorageModifierForDeclare: bare LOCK defaults GLOBAL,
            # while an explicit LOCAL LOCK is stored in the containing lexical
            # scope.  Ordinary local user-locks are safe alpha-rename targets.
            # The four system-lock spellings are special: renaming one changes
            # FlyByWire behaviour, so they remain fixed even when explicitly LOCAL.
            is_global = modifier != "local"
            is_system_lock = tok.text.lower() in SYSTEM_LOCKS
            target_scope = self.root if is_global else scope
            self._declare_callable(
                tok, target_scope, "lock",
                renamable=(not is_global and not is_system_lock and stable),
            )
            # LOCK expressions are deferred/callback-like as well.  Mark the
            # explicit expression scope as a deferred root before descending.
            lock_scope = self._new_scope(node.attrs["value"], scope)
            lock_scope.deferred_root = lock_scope
            self._build_scopes_and_decls(node.attrs["value"], lock_scope, stable=True)
            return

        if k == "var_decl":
            target_scope = self.root if node.attrs.get("modifier") == "global" else scope
            for name, _op, value in node.attrs["decls"]:
                # kOS evaluates RHS first, then StoreLocal/StoreGlobal.
                self._build_scopes_and_decls(value, scope, stable=stable)
                self._declare_storage(
                    name,
                    target_scope,
                    "global" if target_scope is self.root and node.attrs.get("modifier") == "global" else "local",
                    _node_last_end(value, name.end),
                    renamable=(node.attrs.get("modifier") != "global" and target_scope is scope and stable),
                )
            return

        if k == "parameter_decl":
            # Compiler rejects GLOBAL parameters.  Keep malformed grammar-accepted
            # input fixed rather than pretending it is a valid rename target.
            target_scope = scope
            valid_local = node.attrs.get("modifier") != "global"
            for name, _op, default in node.attrs["params"]:
                if default is not None:
                    self._build_scopes_and_decls(default, scope, stable=stable)
                self._declare_storage(
                    name, target_scope, "parameter",
                    _node_last_end(default, name.end),
                    renamable=(valid_local and stable),
                )
            return

        # Declarations used as naked control bodies can execute conditionally in
        # their parent's scope.  A brace block creates its own safe sequential
        # scope and therefore resets stability inside the branch.
        if k == "if":
            self._build_scopes_and_decls(node.attrs["cond"], scope, stable=stable)
            then = node.attrs["then"]
            self._build_scopes_and_decls(
                then, scope, stable=(then.kind in {"block", "block_expr"})
            )
            els = node.attrs.get("else")
            if isinstance(els, Node):
                self._build_scopes_and_decls(
                    els, scope, stable=(els.kind in {"block", "block_expr"})
                )
            return

        if k in {"until", "on", "when"}:
            for key in ("cond", "target"):
                expr = node.attrs.get(key)
                if isinstance(expr, Node):
                    self._build_scopes_and_decls(expr, scope, stable=stable)
            body = node.attrs.get("body")
            if isinstance(body, Node):
                self._build_scopes_and_decls(
                    body, scope, stable=(body.kind in {"block", "block_expr"})
                )
            return

        for child in _iter_child_nodes(node):
            self._build_scopes_and_decls(child, scope, stable=stable)

    def _resolve_variable(self, name: str, scope: Scope, pos: int) -> Optional[Symbol]:
        lname = name.lower()
        cur: Optional[Scope] = scope
        while cur is not None:
            candidates = [
                s for s in cur.symbols
                if s.kind in _STORAGE_KINDS and s.name == lname and
                   (s.available_from_start or s.available_at <= pos)
            ]
            if candidates:
                # Duplicate stores in one scope are merged into one Symbol.
                return min(candidates, key=lambda s: s.declaration_pos)
            cur = cur.parent
        return None

    def _resolve_callable(self, name: str, scope: Scope) -> Optional[Symbol]:
        lname = name.lower()
        cur: Optional[Scope] = scope
        while cur is not None:
            candidates = [
                s for s in cur.symbols if s.kind in _CALLABLE_KINDS and s.name == lname
            ]
            if candidates:
                # Duplicate callable declarations are compiler-weird; safety pass
                # freezes the spelling.  Returning the first keeps analysis stable.
                return min(candidates, key=lambda s: s.declaration_pos)
            cur = cur.parent
        return None

    def _bind(self, token: Token, sym: Symbol, scope: Scope, mode: str):
        if token not in sym.refs:
            sym.refs.append(token)
        span = (token.start, token.end)
        self.binding_by_span[span] = sym
        self.ref_context_by_span[span] = (scope, mode)
        self.ref_token_by_span[span] = token

    def _unresolved(self, token: Token):
        self.unresolved.add(token.text.lower())
        self.unresolved_refs.append(token)

    def _ref_variable(self, token: Token, scope: Scope):
        sym = self._resolve_variable(token.text, scope, token.start)
        if sym is None:
            self._unresolved(token)
        else:
            self._bind(token, sym, scope, "variable")

    def _ref_callable_or_variable(self, token: Token, scope: Scope):
        # Compiler.VisitSuffix asks GetUserFunctionWithScopeWalk first.
        sym = self._resolve_callable(token.text, scope)
        if sym is None:
            sym = self._resolve_variable(token.text, scope, token.start)
        if sym is None:
            self._unresolved(token)
        else:
            self._bind(token, sym, scope, "callable_or_variable")

    def _ref_callable(self, token: Token, scope: Scope):
        sym = self._resolve_callable(token.text, scope)
        if sym is None:
            self._unresolved(token)
        else:
            self._bind(token, sym, scope, "callable")

    def _collect_refs(self, node: Node, scope: Scope):
        scope = node.attrs.get("scope", scope)
        k = node.kind
        if k == "program":
            for stmt in node.children:
                if isinstance(stmt, Node):
                    self._collect_refs(stmt, scope)
            return
        if k in {"block", "block_expr"}:
            for stmt in node.attrs.get("statements", []):
                self._collect_refs(stmt, scope)
            return
        if k == "from":
            self._collect_refs(node.attrs["init"], node.attrs["init"].attrs["scope"])
            self._collect_refs(node.attrs["cond"], node.attrs["scope"])
            self._collect_refs(node.attrs["body"], node.attrs["body"].attrs.get("scope", node.attrs["scope"]))
            self._collect_refs(node.attrs["step"], node.attrs["step"].attrs["scope"])
            return
        if k == "for":
            self._collect_refs(node.attrs["collection"], scope)
            self._collect_refs(node.attrs["body"], node.attrs["body"].attrs.get("scope", scope))
            return
        if k == "var_decl":
            for _name, _op, value in node.attrs["decls"]:
                self._collect_refs(value, scope)
            return
        if k == "parameter_decl":
            for _name, _op, default in node.attrs["params"]:
                if default is not None:
                    self._collect_refs(default, scope)
            return
        if k == "function_decl":
            self._collect_refs(node.attrs["body"], node.attrs["body"].attrs.get("scope", scope))
            return
        if k == "lock_decl":
            self._collect_refs(node.attrs["value"], node.attrs["value"].attrs.get("scope", scope))
            return
        if k == "set":
            for target, _to, value in node.attrs["pairs"]:
                self._collect_set_target(target, scope)
                self._collect_refs(value, scope)
            return
        if k == "suffix":
            terms = [c for c in node.children if isinstance(c, Node)]
            if terms:
                self._collect_suffixterm(terms[0], scope, head_mode="read")
                for term in terms[1:]:
                    self._collect_suffixterm(term, scope, head_mode="suffix")
            return
        if k == "unlock":
            for c in node.children:
                if isinstance(c, Token) and c.kind == "IDENTIFIER":
                    self._ref_callable(c, scope)
            return
        if k == "unset":
            for c in node.children:
                if isinstance(c, Token) and c.kind == "IDENTIFIER":
                    self._ref_variable(c, scope)
            return
        if k == "list":
            # LIST category IN destination: category is an enum-like word, while
            # destination is a real variable store target (Compiler.VisitListStatement).
            ids = [c for c in node.children if isinstance(c, Token) and c.kind == "IDENTIFIER"]
            if len(ids) >= 2:
                self._ref_variable(ids[-1], scope)
            return
        if k == "atom":
            tok = node.children[0] if node.children else None
            if isinstance(tok, Token) and tok.kind == "IDENTIFIER":
                self._ref_callable_or_variable(tok, scope)
            return
        for child in _iter_child_nodes(node):
            self._collect_refs(child, scope)

    def _collect_set_target(self, node: Node, scope: Scope):
        if node.kind != "suffix":
            self._collect_refs(node, scope)
            return
        terms = [c for c in node.children if isinstance(c, Node)]
        if not terms:
            return
        first = terms[0]
        # Simple SET foo TO ... explicitly suppresses user-function resolution.
        simple = len(terms) == 1 and len(first.children) == 1
        self._collect_suffixterm(first, scope, head_mode="variable" if simple else "read")
        for term in terms[1:]:
            self._collect_suffixterm(term, scope, head_mode="suffix")

    def _collect_suffixterm(self, node: Node, scope: Scope, head_mode: str):
        if not node.children:
            return
        head = node.children[0]
        if isinstance(head, Node):
            if head.kind == "atom":
                tok = head.children[0] if head.children else None
                if isinstance(tok, Token) and tok.kind == "IDENTIFIER":
                    if head_mode == "read":
                        self._ref_callable_or_variable(tok, scope)
                    elif head_mode == "variable":
                        self._ref_variable(tok, scope)
                    # suffix names deliberately remain untouched
            else:
                self._collect_refs(head, scope)
        # Remaining Nodes are call argument lists / index expressions.
        for child in node.children[1:]:
            if isinstance(child, Node):
                self._collect_refs(child, scope)


    def _runtime_storage_target(self, token: Token, scope: Scope) -> Optional[Symbol]:
        """Resolve a storage reference as kOS will when a deferred body executes.

        Ordinary code obeys declaration/store timing.  For a reference inside a
        deferred body, however, captured parent VariableScopes are live objects;
        stores performed after delegate creation are visible when the body later
        runs and may shadow an ancestor spelling.
        """
        lname = token.text.lower()
        deferred_root = scope.deferred_root
        cur: Optional[Scope] = scope
        while cur is not None:
            captured_parent = (
                deferred_root is not None
                and cur is not deferred_root
                and cur.is_ancestor_of(deferred_root)
            )
            candidates = [
                s for s in cur.symbols
                if s.kind in _STORAGE_KINDS and s.name == lname and
                   (captured_parent or s.available_from_start or s.available_at <= token.start)
            ]
            if candidates:
                return min(candidates, key=lambda s: s.declaration_pos)
            cur = cur.parent
        return None

    def runtime_target_for_span(self, span: tuple[int, int]) -> Optional[Symbol]:
        """Return the runtime target of a statically-bound reference span."""
        sym = self.binding_by_span.get(span)
        context = self.ref_context_by_span.get(span)
        if sym is None or context is None:
            return sym
        scope, _mode = context
        if sym.kind not in _STORAGE_KINDS:
            return sym
        token = self.ref_token_by_span.get(span)
        if token is None:
            return sym
        return self._runtime_storage_target(token, scope)

    def _resolve_pair_candidate(
        self, scope: Scope, pos: int, mode: str, a: Symbol, b: Symbol
    ) -> Optional[Symbol]:
        """Resolve a synthetic spelling shared by exactly ``a`` and ``b``.

        kOS does not bind ordinary variables to static slots at compile time: the
        emitted variable name is looked up through the runtime lexical scopes.
        User functions/locks are a separate compile-time namespace and take
        precedence for normal expression suffix heads.  Replaying those exact
        rules for a hypothetical shared spelling tells us whether shadowing is
        semantically safe.
        """
        pair = (a, b)

        def resolve_callable() -> Optional[Symbol]:
            cur: Optional[Scope] = scope
            while cur is not None:
                candidates = [
                    s for s in cur.symbols
                    if s in pair and s.kind in _CALLABLE_KINDS
                ]
                if candidates:
                    return min(candidates, key=lambda s: s.declaration_pos)
                cur = cur.parent
            return None

        def resolve_variable() -> Optional[Symbol]:
            cur: Optional[Scope] = scope
            while cur is not None:
                # Inside a deferred body, parent VariableScopes are captured
                # by reference.  By the time the delegate/function/LOCK executes,
                # a declaration textually later than the delegate initializer may
                # already have stored into that captured scope and shadow an outer
                # name.  Only captured *ancestors* ignore source-order availability;
                # the deferred body's own params/locals and its descendant scopes
                # retain ordinary store timing.
                deferred_root = scope.deferred_root
                captured_parent = (
                    deferred_root is not None
                    and cur is not deferred_root
                    and cur.is_ancestor_of(deferred_root)
                )
                candidates = [
                    s for s in cur.symbols
                    if s in pair and s.kind in _STORAGE_KINDS and
                       (captured_parent or s.available_from_start or s.available_at <= pos)
                ]
                if candidates:
                    return min(candidates, key=lambda s: s.declaration_pos)
                cur = cur.parent
            return None

        if mode == "callable":
            return resolve_callable()
        if mode == "variable":
            return resolve_variable()
        if mode == "callable_or_variable":
            return resolve_callable() or resolve_variable()
        raise MinifyError(f"internal error: unknown identifier lookup mode {mode!r}")

    def _conflicts(self, a: Symbol, b: Symbol) -> bool:
        """Whether ``a`` and ``b`` may *not* safely share a final identifier.

        Same-scope stores in the same namespace necessarily alias/overwrite one
        another, so they always interfere.  Otherwise only reject sharing when
        an actual reference would resolve to the other symbol under kOS's lookup
        rules.  This permits useful lexical shadowing such as reusing ``A`` for a
        function parameter even when an unrelated outer symbol is also ``A``.
        """
        if a is b:
            return False
        key = (min(id(a), id(b)), max(id(a), id(b)))
        cached = self._conflict_cache.get(key)
        if cached is not None:
            return cached

        conflict = False
        if a.scope is b.scope:
            if a.kind in _STORAGE_KINDS and b.kind in _STORAGE_KINDS:
                conflict = True
            elif a.kind in _CALLABLE_KINDS and b.kind in _CALLABLE_KINDS:
                conflict = True

        if not conflict:
            for sym in (a, b):
                for tok in sym.refs:
                    span = (tok.start, tok.end)
                    context = self.ref_context_by_span.get(span)
                    if context is None:
                        # All bound refs should have context; fail closed if the AST
                        # ever grows a reference path not covered by this model.
                        conflict = True
                        break
                    scope, mode = context
                    if self._resolve_pair_candidate(scope, tok.start, mode, a, b) is not sym:
                        conflict = True
                        break
                if conflict:
                    break

        self._conflict_cache[key] = conflict
        return conflict

    def _finalize_rename_safety(self) -> None:
        by_name: dict[str, list[Symbol]] = defaultdict(list)
        for sym in self.symbols:
            by_name[sym.name].append(sym)

        for name, syms in by_name.items():
            unsafe = False
            # If the same spelling is also used as an unresolved/external name,
            # runtime lookup before a store could intentionally fall through to it.
            if name in self.unresolved:
                unsafe = True
            # Repeated StoreLocal in one scope is one runtime storage location.
            if any(len(s.decl_tokens) > 1 for s in syms):
                unsafe = True
            # Existing same-name declarations are only unsafe when replaying the
            # actual lookup rules shows that separating/renaming them could alter
            # a binding.  Ordinary lexical shadowing with correct store timing is
            # therefore allowed rather than blanket-frozen.
            for i, a in enumerate(syms):
                for b in syms[i + 1:]:
                    if self._conflicts(a, b):
                        unsafe = True
                        break
                if unsafe:
                    break
            # User-functions/locks and ordinary variables do use different lookup
            # rules, but that only matters when the declarations can be visible to
            # one another.  Unrelated sibling scopes may safely reuse a spelling
            # (for example helper parameters named bottomAltRadar and a LOCAL LOCK
            # of that name inside a separate exported closure).  Ancestor/same-scope
            # mixtures were already frozen by the conflict check above.

            if unsafe:
                self.ambiguous.add(name)
                for sym in syms:
                    sym.renamable = False

    def allocate_names(self) -> dict[tuple[int, int], str]:
        """Assign short identifiers using binding-aware, weighted graph colouring.

        The interference graph is derived from the actual kOS lookup rules rather
        than lexical ancestry alone.  Several deterministic greedy orderings are
        evaluated and the allocation with the lowest total emitted identifier-byte
        cost is selected.  This matters for outer user functions: because callable
        lookup precedes ordinary variable lookup, spending a one-character name on
        a lightly-used outer function can prevent that character being reused by
        many hot inner locals/parameters.
        """
        globally_forbidden = (
            set(self.unresolved) | KEYWORD_TEXT | ONE_CHAR_BUILTINS | SYSTEM_LOCKS
        )

        candidates = list(ONE_CHAR_POOL)
        alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
        for tail_len in itertools.count(1):
            for chars in itertools.product(alphabet, repeat=tail_len):
                candidates.append("_" + "".join(chars))
            if len(candidates) > max(1000, len(self.symbols) * 20):
                break

        renamable = [s for s in self.symbols if s.renamable]
        fixed = [s for s in self.symbols if not s.renamable]
        if not renamable:
            return {}

        # Build the semantic interference graph once.  A graph edge means those
        # two symbols cannot share a case-insensitive final spelling without
        # changing at least one binding under kOS's callable/variable lookup rules.
        neighbours: dict[int, set[int]] = {id(s): set() for s in renamable}
        symbol_by_id = {id(s): s for s in renamable}
        for i, sym in enumerate(renamable):
            for other in renamable[i + 1:]:
                if self._conflicts(sym, other):
                    neighbours[id(sym)].add(id(other))
                    neighbours[id(other)].add(id(sym))

        fixed_forbidden: dict[int, set[str]] = {}
        for sym in renamable:
            fixed_forbidden[id(sym)] = {
                other.name for other in fixed if self._conflicts(sym, other)
            }

        degree = {id(s): len(neighbours[id(s)]) for s in renamable}
        pressure = {
            id(s): sum(symbol_by_id[n].occurrences for n in neighbours[id(s)])
            for s in renamable
        }
        one_char_count = max(1, len(ONE_CHAR_POOL))

        def greedy(order: list[Symbol]) -> tuple[dict[int, str], int]:
            assigned: dict[int, str] = {}
            for sym in order:
                sid = id(sym)
                chosen = None
                for cand in candidates:
                    lc = cand.lower()
                    if lc in globally_forbidden or lc in fixed_forbidden[sid]:
                        continue
                    if any(
                        assigned.get(other_id, "").lower() == lc
                        for other_id in neighbours[sid]
                    ):
                        continue
                    chosen = cand
                    break
                if chosen is None:
                    raise MinifyError(
                        f"unable to allocate a collision-free identifier for {sym.token.text!r}"
                    )
                assigned[sid] = chosen
            cost = sum(
                sym.occurrences * len(assigned[id(sym)]) for sym in renamable
            )
            return assigned, cost

        # No single greedy ordering is globally optimal for weighted colouring.
        # Evaluate complementary deterministic priorities and keep the cheapest.
        # The pressure terms estimate the aggregate downstream cost of occupying a
        # scarce one-character colour.
        strategies: list[list[Symbol]] = [
            sorted(
                renamable,
                key=lambda s: (-s.occurrences, -degree[id(s)], s.declaration_pos),
            ),
            sorted(
                renamable,
                key=lambda s: (
                    -(s.occurrences - pressure[id(s)] / one_char_count),
                    -s.occurrences,
                    s.declaration_pos,
                ),
            ),
            sorted(
                renamable,
                key=lambda s: (
                    -(s.occurrences / (1 + pressure[id(s)] / one_char_count)),
                    -s.occurrences,
                    s.declaration_pos,
                ),
            ),
            sorted(
                renamable,
                key=lambda s: (
                    -(s.occurrences * one_char_count - pressure[id(s)]),
                    -s.scope.depth,
                    -s.occurrences,
                    s.declaration_pos,
                ),
            ),
            sorted(
                renamable,
                key=lambda s: (
                    -s.scope.depth, -s.occurrences, degree[id(s)], s.declaration_pos
                ),
            ),
            sorted(
                renamable,
                key=lambda s: (
                    -s.occurrences, degree[id(s)], -s.scope.depth, s.declaration_pos
                ),
            ),
        ]

        best_assigned: Optional[dict[int, str]] = None
        best_cost: Optional[int] = None
        for order in strategies:
            assigned, cost = greedy(order)
            if best_cost is None or cost < best_cost:
                best_assigned, best_cost = assigned, cost

        assert best_assigned is not None
        for sym in renamable:
            sym.new_name = best_assigned[id(sym)]

        replacements: dict[tuple[int, int], str] = {}
        for sym in renamable:
            assert sym.new_name is not None
            for decl in sym.decl_tokens:
                if decl.text != sym.new_name:
                    replacements[(decl.start, decl.end)] = sym.new_name
            for ref in sym.refs:
                if ref.text != sym.new_name:
                    replacements[(ref.start, ref.end)] = sym.new_name
        return replacements

def _binding_signature(analyzer: SymbolAnalyzer):
    """Return a name-independent description of identifier/callable binding."""
    ordered = sorted(analyzer.symbols, key=lambda s: s.declaration_pos)
    index = {id(sym): i for i, sym in enumerate(ordered)}
    declarations = tuple(
        (sym.kind, sym.scope.depth, sym.available_from_start, sym.renamable, len(sym.decl_tokens))
        for sym in ordered
    )
    occurrences = []
    declaration_spans = {
        (tok.start, tok.end): index[id(sym)]
        for sym in ordered for tok in sym.decl_tokens
    }
    for span, sym in sorted(analyzer.binding_by_span.items()):
        is_decl = span in declaration_spans
        runtime_target = sym if is_decl else analyzer.runtime_target_for_span(span)
        runtime_index = index.get(id(runtime_target), -1) if runtime_target is not None else -1
        occurrences.append((
            "D" if is_decl else "R",
            index[id(sym)],
            runtime_index,
        ))
    return declarations, tuple(occurrences)


def _validate_binding_preservation(before: SymbolAnalyzer, after: SymbolAnalyzer) -> None:
    if _binding_signature(before) != _binding_signature(after):
        raise MinifyError(
            "internal validation failure: identifier renaming changed lexical binding "
            "(possible case-insensitive symbol collision)"
        )


def _iter_child_nodes(node: Node) -> Iterator[Node]:
    seen: set[int] = set()
    # attrs contain important expression nodes omitted from children in compact AST forms.
    def visit_value(v):
        if isinstance(v, Node):
            if id(v) not in seen:
                seen.add(id(v)); yield v
        elif isinstance(v, (list, tuple)):
            for x in v:
                yield from visit_value(x)
        elif isinstance(v, dict):
            for x in v.values(): yield from visit_value(x)
    for child in node.children:
        if isinstance(child, Node) and id(child) not in seen:
            seen.add(id(child)); yield child
        elif isinstance(child, list):
            for x in child:
                if isinstance(x, Node) and id(x) not in seen:
                    seen.add(id(x)); yield x
    for key, value in node.attrs.items():
        if key in {"scope", "symbol"}: continue
        yield from visit_value(value)

# ---------------------------------------------------------------------------
# Conservative lexicon-key analysis
# ---------------------------------------------------------------------------

class AValue:
    __slots__ = ()

class UnknownValue(AValue):
    __slots__ = ()
UNKNOWN_VALUE = UnknownValue()

class SchemaValue(AValue):
    __slots__ = ("keys", "dynamic_values", "escaped", "opaque", "origin_token", "labels", "construction_labels", "unsafe_reasons", "reserved_keys", "reserved_accesses")
    def __init__(self, origin_token: Optional[Token] = None):
        self.keys: dict[str, KeyInfo] = {}
        # Values inserted under keys whose names are only known at runtime.
        # The containing lexicon cannot have its own keys renamed safely, but
        # retaining these values lets analysis continue through :VALUES and
        # dynamic indexing into nested, independently renameable lexicons.
        self.dynamic_values: set[AValue] = set()
        self.escaped = False
        self.opaque = False
        self.origin_token = origin_token
        self.labels: set[str] = set()
        self.construction_labels: set[str] = set()
        self.unsafe_reasons: set[str] = set()
        self.reserved_keys: set[str] = set()
        self.reserved_accesses: dict[str, set[tuple[int, int]]] = defaultdict(set)

class ListValue(AValue):
    __slots__ = ("elements", "escaped")
    def __init__(self):
        self.elements: set[AValue] = set()
        self.escaped = False

class MapValue(AValue):
    __slots__ = ("values", "escaped")
    def __init__(self):
        self.values: set[AValue] = set()
        self.escaped = False

class FixedRecordValue(AValue):
    """Structured value with externally-fixed field names.

    Used for wrappers such as the project-level ApiOK/ApiFail helpers.  The
    wrapper's own keys are never candidates for lexicon-key renaming, but
    structured payloads remain traceable through fields such as :VAL.
    """
    __slots__ = ("fields", "escaped")
    def __init__(self):
        self.fields: dict[str, set[AValue]] = defaultdict(set)
        self.escaped = False

class DelegateValue(AValue):
    __slots__ = ("body", "params", "escaped", "returns", "bound")
    def __init__(self, body: Node, params: list[Symbol], bound=0):
        self.body = body
        self.params = params
        self.escaped = False
        self.returns: set[AValue] = set()
        self.bound = bound

@dataclasses.dataclass
class KeyInfo:
    name: str
    literals: list[Token] = dataclasses.field(default_factory=list)
    accesses: list[Token] = dataclasses.field(default_factory=list)
    values: set[AValue] = dataclasses.field(default_factory=set)
    new_name: Optional[str] = None

    @property
    def occurrences(self) -> int:
        return len(self.literals) + len(self.accesses)


def _kos_string_value(tok: Token) -> Optional[str]:
    text = tok.text
    if text.startswith('@"'):
        # Compiler.VisitString sets shouldEscape=false for @ strings.
        return text[2:-1] if text.endswith('"') else None
    if len(text) < 2 or not (text.startswith('"') and text.endswith('"')):
        return None
    return text[1:-1].replace('""', '"')


def _kos_quote_string(value: str, original: Token) -> str:
    prefix = '@' if original.text.startswith('@"') else ''
    return prefix + '"' + value.replace('"', '""') + '"'


def _single_node_child(node: Node) -> Optional[Node]:
    nodes = [c for c in node.children if isinstance(c, Node)]
    tokens = [c for c in node.children if isinstance(c, Token)]
    if len(nodes) == 1 and not tokens:
        return nodes[0]
    return None


def _unwrap_expr(node: Node) -> Node:
    while node.kind in {"or", "and", "compare", "arith", "mult", "unary", "factor"}:
        child = _single_node_child(node)
        if child is None:
            break
        node = child
    return node


def _arg_nodes(arglist: Optional[Node]) -> list[Node]:
    if arglist is None:
        return []
    return [c for c in arglist.children if isinstance(c, Node)]


def _suffix_terms(node: Node) -> list[Node]:
    node = _unwrap_expr(node)
    if node.kind != "suffix":
        return []
    return [c for c in node.children if isinstance(c, Node) and c.kind == "suffixterm"]


def _term_head_token(term: Node) -> Optional[Token]:
    if not term.children or not isinstance(term.children[0], Node):
        return None
    atom = term.children[0]
    if atom.kind != "atom" or not atom.children or not isinstance(atom.children[0], Token):
        return None
    return atom.children[0]


def _term_call_args(term: Node) -> Optional[list[Node]]:
    # suffixterm: atom, then zero or more trailers.  Return args for its first () trailer.
    for i, child in enumerate(term.children[1:], start=1):
        if isinstance(child, Token) and child.kind == "BRACKETOPEN":
            arglist = term.children[i + 1] if i + 1 < len(term.children) and isinstance(term.children[i + 1], Node) and term.children[i + 1].kind == "arglist" else None
            return _arg_nodes(arglist)
    return None


@dataclasses.dataclass
class LexiconPlan:
    schema: SchemaValue
    label: str
    line: int
    column: int
    mappings: list[tuple[str, str]]
    can_minify: bool
    reasons: list[str]


class LexiconKeyAnalyzer:
    """Discover and optionally rename statically-known lexicon keys.

    This analysis only approves a lexicon-key rewrite when the complete key
    contract is statically rewriteable *and* the lexicon remains private to the
    analyzed implementation.  A lexicon that escapes through EXPORT, an unknown
    call, an escaping delegate/return value, or another externally-visible value
    is a public contract and its keys are never renamed automatically.

    Values are tracked through local symbols, delegates/:BIND, LIST containers,
    lexicon values and helper calls.  The analysis is deliberately fail-closed:
    uncertainty or escape disables key renaming rather than guessing.
    """

    SAFE_BUILTIN_CALLS = {
        "list", "lex", "exists", "volume", "create", "open", "deletepath",
        "movepath", "dmsg", "notify", "apifail", "apiok", "max", "min",
        "abs", "floor", "ceiling", "round", "mod", "sqrt", "sin", "cos",
        "tan", "arcsin", "arccos", "arctan", "arctan2", "toscalar",
    }

    # Lexicon.cs resolves normal Structure suffixes before falling back to a
    # string key.  These names therefore must be modelled as Lexicon API
    # suffixes, not as user keys, when colon syntax is used.
    LEXICON_CALL_SUFFIXES = {"add", "haskey", "hasvalue", "remove"}
    LEXICON_VALUE_SUFFIXES = {
        "clear", "keys", "values", "copy", "length", "dump",
        "casesensitive", "case",
    }
    STRUCTURE_CALL_SUFFIXES = {"hassuffix", "istype"}
    STRUCTURE_VALUE_SUFFIXES = {
        "tostring", "suffixnames", "isserializable", "typename", "inheritance",
    }

    def _is_real_lexicon_suffix(self, name: str) -> bool:
        return (name in self.LEXICON_CALL_SUFFIXES or
                name in self.LEXICON_VALUE_SUFFIXES or
                name in self.STRUCTURE_CALL_SUFFIXES or
                name in self.STRUCTURE_VALUE_SUFFIXES)

    def __init__(self, tree: Node, symbols: SymbolAnalyzer):
        self.tree = tree
        self.symbols = symbols
        self.symbol_values: dict[int, set[AValue]] = defaultdict(set)
        self.node_values: dict[int, AValue] = {}
        self.delegate_by_body: dict[int, DelegateValue] = {}
        # Canonical bound-delegate abstract values.  Without memoization, each
        # fixed-point pass would create a fresh DelegateValue for the same :BIND
        # expression, making the monotone value sets grow forever by identity.
        self.bound_delegates: dict[tuple[int, int], DelegateValue] = {}
        self.changed = False
        # Escape is intentionally analysed only after value/type propagation has
        # reached a fixed point.  Otherwise an early "unknown receiver" pass can
        # permanently taint a value that a later pass proves is a local List/Lexicon.
        self.escape_phase = False
        self._initialize_delegates(tree)

    def _symbol_for(self, tok: Token) -> Optional[Symbol]:
        return self.symbols.binding_by_span.get((tok.start, tok.end))

    def _add_values(self, target: set[AValue], values: Iterable[AValue]):
        before = len(target)
        target.update(v for v in values if v is not UNKNOWN_VALUE)
        if len(target) != before:
            self.changed = True

    def _label_values(self, values: Iterable[AValue], label: str, construction: bool = False) -> None:
        for value in values:
            if isinstance(value, SchemaValue):
                value.labels.add(label)
                if construction:
                    value.construction_labels.add(label)

    def _is_direct_lex_expr(self, node: Node) -> bool:
        terms=_suffix_terms(node)
        if len(terms)!=1:
            return False
        head=_term_head_token(terms[0])
        return (
            head is not None
            and head.kind=="IDENTIFIER"
            and head.text.lower() in {"lex", "lexicon"}
            and _term_call_args(terms[0]) is not None
            and self._symbol_for(head) is None
        )

    def _simple_suffix_path(self, terms: Sequence[Node]) -> Optional[str]:
        """Return a construction-site suffix path such as runnerState:steps.

        This is deliberately syntactic only: every term must be a plain
        identifier with no call/index trailers.  It is used only to make
        interactive lexicon labels more informative, never to infer types.
        """
        names: list[str] = []
        for term in terms:
            head = _term_head_token(term)
            if head is None or head.kind != "IDENTIFIER" or len(term.children) != 1:
                return None
            names.append(head.text)
        return ":".join(names) if names else None

    def _label_collection_item_construction(
        self, receiver_terms: Sequence[Node], method: Token, args: list[Node]
    ) -> None:
        """Label direct LEX(...) arguments from their construction site.

        This is deliberately syntactic only; it does not infer the receiver's
        runtime type.  Examples:

            runnerState:steps:add(lex(...))
                -> runnerState:steps[item]

            runnerState:events:add(name, lex(...))
                -> runnerState:events[name]

        For a two-argument :ADD whose key expression is not a simple suffix
        path, ``[key]`` is used rather than guessing its runtime value.
        """
        name = method.text.lower()
        base = self._simple_suffix_path(receiver_terms)
        if not base:
            return

        if name == "add":
            if len(args) == 1:
                value_arg = args[0]
                label = f"{base}[item]"
            elif len(args) >= 2:
                value_arg = args[-1]
                key_terms = _suffix_terms(args[0])
                key_label = self._simple_suffix_path(key_terms) if key_terms else None
                label = f"{base}[{key_label or 'key'}]"
            else:
                return
        elif name == "insert" and len(args) >= 2:
            value_arg = args[-1]
            label = f"{base}[item]"
        else:
            return

        if self._is_direct_lex_expr(value_arg):
            self._label_values(self.eval_expr(value_arg), label, construction=True)

    def _sym_values(self, sym: Optional[Symbol]) -> set[AValue]:
        return self.symbol_values[id(sym)] if sym is not None else set()

    def _initialize_delegates(self, node: Node):
        if node.kind == "function_decl":
            sym = self._symbol_for(node.attrs["name"])
            if sym is not None:
                body = node.attrs["body"]
                d = self._delegate_for_body(body)
                self._add_values(self.symbol_values[id(sym)], {d})
        for child in _iter_child_nodes(node):
            self._initialize_delegates(child)

    def _delegate_for_body(self, body: Node) -> DelegateValue:
        existing = self.delegate_by_body.get(id(body))
        if existing:
            return existing
        params: list[Symbol] = []
        for stmt in body.attrs.get("statements", []):
            if stmt.kind != "parameter_decl":
                # kOS parameters conventionally lead the function/delegate; later
                # declarations are still discovered by scanning all parameter nodes.
                continue
            for tok, _op, _default in stmt.attrs["params"]:
                sym = self._symbol_for(tok)
                if sym is not None:
                    params.append(sym)
        d = DelegateValue(body, params)
        self.delegate_by_body[id(body)] = d
        self.node_values[id(body)] = d
        return d

    def _schema_for_lex(self, call_node: Node, args: list[Node]) -> AValue:
        cached = self.node_values.get(id(call_node))
        if cached is not None:
            return cached

        schema = SchemaValue(_term_head_token(call_node))
        self.node_values[id(call_node)] = schema

        if not args:
            return schema

        # kOS also permits LEX(singleEnumerable).  Its keys are determined at
        # runtime, so there is nothing soundly renameable without evaluating the
        # enumerable.  Likewise, odd argument counts are runtime-invalid rather
        # than a fixed key/value schema.
        if len(args) % 2:
            schema.opaque = True
            schema.unsafe_reasons.add("constructor keys are not a literal key/value list")
            return schema

        for i in range(0, len(args), 2):
            key_expr = _unwrap_expr(args[i])
            # Walk down to a literal atom.  Only literal string keys can be
            # rewritten safely; computed constructor keys make this lexicon
            # ineligible for key minification.
            cur = key_expr
            while isinstance(cur, Node) and cur.kind in {"suffix", "suffixterm", "factor", "unary", "mult", "arith", "compare", "and", "or"}:
                child = _single_node_child(cur)
                if child is None:
                    break
                cur = child
            tok = cur.children[0] if isinstance(cur, Node) and cur.kind == "atom" and cur.children and isinstance(cur.children[0], Token) else None
            if not isinstance(tok, Token) or tok.kind != "STRING":
                schema.opaque = True
                schema.unsafe_reasons.add("constructor contains a computed/non-string key")
                continue
            key = _kos_string_value(tok)
            if key is None:
                schema.opaque = True
                schema.unsafe_reasons.add("constructor contains an unreadable string key")
                continue
            lk = key.lower()
            info = schema.keys.setdefault(lk, KeyInfo(key))
            info.literals.append(tok)
        return schema

    def _list_for_call(self, call_node: Node, args: list[Node]) -> ListValue:
        cached = self.node_values.get(id(call_node))
        if isinstance(cached, ListValue):
            value = cached
        else:
            value = ListValue()
            self.node_values[id(call_node)] = value
        # Re-evaluate arguments on every fixed-point pass.  Parameter values may
        # only become known after a caller/:BIND is analysed later in an earlier
        # pass; returning the cached LIST without revisiting its arguments loses
        # those newly-known flows.
        for arg in args:
            self._add_values(value.elements, self.eval_expr(arg))
        return value

    def _mark_escape(self, values: Iterable[AValue], seen=None):
        # During the propagation phase unknown calls/receivers are provisional:
        # their types may become known on a later fixed-point pass.  Escape marks
        # are therefore deferred until the dedicated escape phase.
        if not self.escape_phase:
            return
        if seen is None: seen=set()
        for value in values:
            if id(value) in seen or value is UNKNOWN_VALUE: continue
            seen.add(id(value))
            if isinstance(value, SchemaValue):
                if not value.escaped:
                    value.escaped=True; self.changed=True
                for info in value.keys.values(): self._mark_escape(info.values, seen)
                self._mark_escape(value.dynamic_values, seen)
            elif isinstance(value, ListValue):
                if not value.escaped: value.escaped=True; self.changed=True
                self._mark_escape(value.elements, seen)
            elif isinstance(value, MapValue):
                if not value.escaped: value.escaped=True; self.changed=True
                self._mark_escape(value.values, seen)
            elif isinstance(value, FixedRecordValue):
                if not value.escaped: value.escaped=True; self.changed=True
                for field_values in value.fields.values():
                    self._mark_escape(field_values, seen)
            elif isinstance(value, DelegateValue):
                if not value.escaped: value.escaped=True; self.changed=True
                self._mark_escape(value.returns, seen)

    @staticmethod
    def _reserve_key(schema: SchemaValue, name: str, token: Token) -> None:
        lname = name.lower()
        schema.reserved_keys.add(lname)
        schema.reserved_accesses[lname].add((token.start, token.end))

    def _record_key(self, schema: SchemaValue, token: Token) -> set[AValue]:
        name = token.text.lower()
        info = schema.keys.get(name)
        if info is None:
            # This may be a key created through a runtime key expression.  Keep
            # the spelling reserved and conservatively propagate every value
            # known to have been inserted under a dynamic key.
            self._reserve_key(schema, name, token)
            return set(schema.dynamic_values)
        if token not in info.accesses:
            info.accesses.append(token); self.changed=True
        return set(info.values)

    def _record_string_key(self, schema: SchemaValue, token: Token) -> set[AValue]:
        key = _kos_string_value(token)
        if key is None:
            schema.opaque=True
            schema.unsafe_reasons.add("contains an unreadable string key access")
            return set()
        info=schema.keys.get(key.lower())
        if info is None:
            self._reserve_key(schema, key, token)
            return set(schema.dynamic_values)
        if token not in info.literals and token not in info.accesses:
            info.accesses.append(token); self.changed=True
        return set(info.values)

    def _apply_index(self, values: set[AValue], index_expr: Node) -> set[AValue]:
        out:set[AValue]=set()
        # The index expression is executable code in its own right.  Evaluate it
        # even for LIST/MAP receivers so nested lexicon accesses such as
        # steps[runnerState:currentStep] are not silently skipped.
        self.eval_expr(index_expr)
        const_string=self._constant_string(index_expr)
        for value in values:
            if isinstance(value,ListValue):
                out.update(value.elements)
            elif isinstance(value,MapValue):
                out.update(value.values)
            elif isinstance(value,FixedRecordValue):
                if const_string is None:
                    for field_values in value.fields.values():
                        out.update(field_values)
                else:
                    _tok,key=const_string
                    out.update(value.fields.get(key.lower(), set()))
            elif isinstance(value,SchemaValue):
                if const_string is None:
                    value.opaque = True
                    value.unsafe_reasons.add("contains a dynamic index key")
                    for info in value.keys.values():
                        out.update(info.values)
                    out.update(value.dynamic_values)
                else:
                    tok,_const=const_string
                    out.update(self._record_string_key(value,tok))
                    # A value inserted with a computed key could also occupy this
                    # literal key at runtime, so include those values as well.
                    out.update(value.dynamic_values)
        return out

    def _constant_string(self,node:Node)->Optional[tuple[Token,str]]:
        cur=_unwrap_expr(node)
        while cur.kind in {"suffix","suffixterm","factor","unary","mult","arith","compare","and","or"}:
            child=_single_node_child(cur)
            if child is None: break
            cur=child
        if cur.kind=="atom" and cur.children and isinstance(cur.children[0],Token) and cur.children[0].kind=="STRING":
            val=_kos_string_value(cur.children[0])
            if val is not None:return cur.children[0],val
        return None

    def _api_result_for_call(self, call_node: Node, name: str, args: list[Node]) -> FixedRecordValue:
        """Model kLib's fixed ApiOK/ApiFail result wrapper.

        ApiOK(value, message)  -> { ok, val:value, msg:message }
        ApiFail(message, value)-> { ok, val:value, msg:message }

        The wrapper field names are an external API contract and are never
        renamed, but the value carried through :VAL remains analyzable and may
        still be private if the wrapper itself never escapes.
        """
        cached=self.node_values.get(id(call_node))
        if isinstance(cached,FixedRecordValue):
            record=cached
        else:
            record=FixedRecordValue()
            self.node_values[id(call_node)]=record

        argvals=[self.eval_expr(a) for a in args]
        if name=="apiok":
            if len(argvals)>=1:self._add_values(record.fields["val"],argvals[0])
            if len(argvals)>=2:self._add_values(record.fields["msg"],argvals[1])
        else:  # apifail(message, value)
            if len(argvals)>=1:self._add_values(record.fields["msg"],argvals[0])
            if len(argvals)>=2:self._add_values(record.fields["val"],argvals[1])
        return record

    def _call_delegate(self, values:set[AValue], args:list[Node]) -> set[AValue]:
        result:set[AValue]=set()
        argvals=[self.eval_expr(a) for a in args]
        known=False
        for value in values:
            if not isinstance(value,DelegateValue): continue
            known=True
            params=value.params[value.bound:]
            for sym,vals in zip(params,argvals): self._add_values(self.symbol_values[id(sym)],vals)
            result.update(value.returns)
        if not known:
            for vals in argvals:self._mark_escape(vals)
        return result

    def _method(self, receivers:set[AValue], name_tok:Token, args:list[Node]) -> set[AValue]:
        name=name_tok.text.lower()
        argvals=[self.eval_expr(a) for a in args]
        out:set[AValue]=set()
        all_handled=bool(receivers)
        for recv in receivers:
            handled=False
            if isinstance(recv,ListValue):
                if name=="add" and argvals:
                    self._add_values(recv.elements,argvals[0]); handled=True
                elif name=="insert" and len(argvals)>=2:
                    # kOS ListValue:INSERT(index, value) retains the second arg
                    # in the local list exactly like ADD(value).
                    self._add_values(recv.elements,argvals[-1]); handled=True
                elif name=="values":
                    out.update(recv.elements); handled=True
                elif name in {"length","clear","copy","dump","contains","find","indexof","sublist","join","iterator"}:
                    handled=True
            elif isinstance(recv,MapValue):
                if name=="add" and len(argvals)>=2:
                    self._add_values(recv.values,argvals[1]); handled=True
                elif name=="values":
                    lv=self.node_values.get(id(name_tok))
                    if not isinstance(lv,ListValue):
                        lv=ListValue(); self.node_values[id(name_tok)]=lv
                    self._add_values(lv.elements,recv.values); out.add(lv); handled=True
            elif isinstance(recv,SchemaValue):
                if name in {"case","casesensitive"}:
                    # Changing case sensitivity clears the Lexicon and changes key
                    # identity rules.  Flow-sensitive proof is not worth the risk.
                    recv.opaque=True
                    recv.unsafe_reasons.add("uses :CASE/:CASESENSITIVE, so key identity can become case-sensitive")
                    handled=True
                elif name=="add" and len(args)>=2:
                    cs=self._constant_string(args[0])
                    if cs is None:
                        recv.opaque = True
                        recv.unsafe_reasons.add("adds a key whose name is computed at runtime")
                        self._add_values(recv.dynamic_values,argvals[1])
                    else:
                        tok,key=cs; info=recv.keys.get(key.lower())
                        if info is None:
                            info=KeyInfo(key); recv.keys[key.lower()]=info
                        if tok not in info.literals: info.literals.append(tok); self.changed=True
                        self._add_values(info.values,argvals[1])
                    handled=True
                elif name=="values":
                    lv=self.node_values.get(id(name_tok))
                    if not isinstance(lv,ListValue):
                        lv=ListValue(); self.node_values[id(name_tok)]=lv
                    for info in recv.keys.values():
                        self._add_values(lv.elements,info.values)
                    self._add_values(lv.elements,recv.dynamic_values)
                    out.add(lv); handled=True
                elif name=="copy":
                    out.add(recv); handled=True
                elif name in {"haskey","remove"} and args:
                    cs=self._constant_string(args[0])
                    if cs is None:
                        recv.opaque = True
                        recv.unsafe_reasons.add(f"uses :{name.upper()} with a computed key")
                    else:
                        self._record_string_key(recv,cs[0])
                    handled=True
                elif name in {"hasvalue","length","keys","clear","dump"}:
                    handled=True
            elif isinstance(recv,DelegateValue) and name=="bind":
                params=recv.params[recv.bound:recv.bound+len(argvals)]
                for sym,vals in zip(params,argvals):
                    self._add_values(self.symbol_values[id(sym)],vals)
                new_bound=min(len(recv.params),recv.bound+len(args))
                key=(id(recv),new_bound)
                bound=self.bound_delegates.get(key)
                if bound is None:
                    bound=DelegateValue(recv.body,recv.params,new_bound)
                    bound.returns=recv.returns
                    self.bound_delegates[key]=bound
                out.add(bound); handled=True
            elif name in self.STRUCTURE_CALL_SUFFIXES:
                # HASSUFFIX/ISTYPE inspect their arguments but do not retain them.
                handled=True

            if not handled:
                all_handled=False

        if not all_handled:
            # Unknown receiver+method combinations may retain structured args.
            for vals in argvals:
                self._mark_escape(vals)
        return out

    def eval_expr(self,node:Optional[Node]) -> set[AValue]:
        if node is None:return set()
        if node.kind=="block_expr": return {self._delegate_for_body(node)}
        if node.kind=="group":
            for c in node.children:
                if isinstance(c,Node): return self.eval_expr(c)
            return set()
        if node.kind=="suffix": return self._eval_suffix(node)
        # Operators generally destroy structure values, but still evaluate operands
        # for propagation/escape side effects. A single-child wrapper preserves value.
        child_nodes=[c for c in node.children if isinstance(c,Node)]
        token_ops=[c for c in node.children if isinstance(c,Token) and c.kind not in {"BRACKETOPEN","BRACKETCLOSE"}]
        if len(child_nodes)==1 and not token_ops:
            return self.eval_expr(child_nodes[0])
        for c in child_nodes:self.eval_expr(c)
        return set()

    def _eval_suffix(self,node:Node)->set[AValue]:
        terms=[c for c in node.children if isinstance(c,Node) and c.kind=="suffixterm"]
        if not terms:return set()
        values=self._eval_term(terms[0],head_is_variable=True)
        for term_index, term in enumerate(terms[1:], start=1):
            head=_term_head_token(term)
            if head is None:
                values=set(); continue
            name=head.text.lower()
            args=_term_call_args(term)
            if args is not None:
                receiver_was_unknown = not values
                # Lexicon's real Structure suffixes take precedence over key
                # fallback.  Only a non-built-in suffix may denote a callable
                # lexicon key.
                keyed:set[AValue]=set(); method_receivers:set[AValue]=set(); had_key=False
                for recv in values:
                    if (isinstance(recv,SchemaValue) and
                            not self._is_real_lexicon_suffix(name) and
                            name in recv.keys):
                        had_key=True
                        keyed.update(self._record_key(recv,head))
                    else:
                        if isinstance(recv,SchemaValue) and not self._is_real_lexicon_suffix(name):
                            # It may be a key introduced dynamically.  Reserving
                            # the spelling also lets post-rewrite validation catch
                            # stale callable key accesses such as oldKey(...).
                            self._reserve_key(recv, name, head)
                        method_receivers.add(recv)
                called=self._call_delegate(keyed,args) if keyed else set()
                if had_key and not keyed:
                    # The key exists but its value is supplied dynamically/externally.
                    # Invoking it is an unknown call, so structured arguments escape.
                    for arg in args:self._mark_escape(self.eval_expr(arg))
                if method_receivers:
                    self._label_collection_item_construction(
                        terms[:term_index], head, args
                    )
                if method_receivers:
                    method_values=self._method(method_receivers,head,args)
                else:
                    method_values=set()
                    if receiver_was_unknown:
                        # No tracked receiver type: this is an unknown external
                        # call and structured arguments may escape regardless of
                        # the method spelling (including ADD/REMOVE/etc.).
                        for arg in args:
                            self._mark_escape(self.eval_expr(arg))
                values=called|method_values
            else:
                new:set[AValue]=set()
                for recv in values:
                    if isinstance(recv,SchemaValue):
                        if name=="values":
                            lv=self.node_values.get(id(term))
                            if not isinstance(lv,ListValue):
                                lv=ListValue();self.node_values[id(term)]=lv
                            for info in recv.keys.values():
                                self._add_values(lv.elements,info.values)
                            self._add_values(lv.elements,recv.dynamic_values)
                            new.add(lv)
                        elif name=="copy":
                            new.add(recv)
                        elif self._is_real_lexicon_suffix(name):
                            # A real Lexicon/Structure suffix, not a string key.
                            if name in {"case", "casesensitive"}:
                                recv.opaque = True
                                recv.unsafe_reasons.add(
                                    "uses :CASE/:CASESENSITIVE, so key identity can become case-sensitive"
                                )
                        else:
                            new.update(self._record_key(recv,head))
                    elif isinstance(recv,MapValue) and name=="values":
                        lv=self.node_values.get(id(term))
                        if not isinstance(lv,ListValue): lv=ListValue();self.node_values[id(term)]=lv
                        self._add_values(lv.elements,recv.values);new.add(lv)
                    elif isinstance(recv,ListValue) and name=="values": new.add(recv)
                    elif isinstance(recv,FixedRecordValue):
                        new.update(recv.fields.get(name,set()))
                values=new
                # Apply any non-call array trailers on the member term.
                values=self._apply_term_trailers(term,values,skip_call=True)
        return values

    def _eval_term(self,term:Node,head_is_variable:bool)->set[AValue]:
        head_node=term.children[0] if term.children and isinstance(term.children[0],Node) else None
        values:set[AValue]=set()
        head_tok=_term_head_token(term)
        if head_tok is not None and head_tok.kind=="IDENTIFIER" and head_is_variable:
            lname=head_tok.text.lower()
            args=_term_call_args(term)
            if args is not None and self._symbol_for(head_tok) is None:
                if lname in {"lex", "lexicon"}:
                    values={self._schema_for_lex(term,args)}
                    # Populate values for literal key/value constructor pairs.
                    schema=next(iter(values))
                    if isinstance(schema,SchemaValue) and len(args) % 2 == 0:
                        for idx in range(0,len(args),2):
                            cs=self._constant_string(args[idx])
                            if cs:
                                info=schema.keys.get(cs[1].lower())
                                if info:self._add_values(info.values,self.eval_expr(args[idx+1]))
                    return values
                if lname=="list": return {self._list_for_call(term,args)}
                if lname in {"apiok","apifail"}:
                    return {self._api_result_for_call(term,lname,args)}
                if lname=="export":
                    for arg in args:
                        vals=self.eval_expr(arg)
                        self._label_values(vals, "export", construction=self._is_direct_lex_expr(arg))
                        self._mark_escape(vals)
                    return set()
                if lname in self.SAFE_BUILTIN_CALLS:
                    # These calls inspect/use their arguments but do not retain
                    # structured values beyond the call.  Evaluate arguments so
                    # nested key accesses still participate in analysis.
                    for arg in args:self.eval_expr(arg)
                    return set()
            sym=self._symbol_for(head_tok)
            values=set(self._sym_values(sym))
        elif isinstance(head_node,Node):
            values=self.eval_expr(head_node)
        return self._apply_term_trailers(term,values,skip_call=False)

    def _apply_term_trailers(self,term:Node,values:set[AValue],skip_call:bool)->set[AValue]:
        i=1; children=term.children
        while i<len(children):
            c=children[i]
            if isinstance(c,Token) and c.kind=="BRACKETOPEN":
                arglist=children[i+1] if i+1<len(children) and isinstance(children[i+1],Node) and children[i+1].kind=="arglist" else None
                args=_arg_nodes(arglist)
                if not skip_call: values=self._call_delegate(values,args)
                i += 3 if arglist is not None else 2
                continue
            if isinstance(c,Token) and c.kind=="ATSIGN": i+=1;continue
            if isinstance(c,Token) and c.kind=="ARRAYINDEX":
                # #IDENT/#INTEGER is an index/member shorthand.  Dynamic identifiers
                # make fixed schemas opaque; lists/maps simply yield their element type.
                idx_tok=children[i+1] if i+1<len(children) and isinstance(children[i+1],Token) else None
                out:set[AValue]=set()
                for v in values:
                    if isinstance(v,ListValue):out.update(v.elements)
                    elif isinstance(v,MapValue):out.update(v.values)
                    elif isinstance(v,SchemaValue):
                        if idx_tok and idx_tok.kind=="IDENTIFIER":
                            v.opaque=True
                            v.unsafe_reasons.add("contains a dynamic #identifier key access")
                values=out;i+=2;continue
            if isinstance(c,Token) and c.kind=="SQUAREOPEN":
                expr=children[i+1] if i+1<len(children) and isinstance(children[i+1],Node) else None
                if expr is not None: values=self._apply_index(values,expr)
                i+=3;continue
            i+=1
        return values

    def _simple_target_symbol(self,node:Node)->Optional[Symbol]:
        terms=_suffix_terms(node)
        if len(terms)!=1:return None
        term=terms[0]
        # no call/index trailers
        if len(term.children)!=1:return None
        tok=_term_head_token(term)
        return self._symbol_for(tok) if tok is not None else None

    def _assign_schema_index(self, receivers:set[AValue], index_expr:Node, vals:set[AValue]) -> None:
        self.eval_expr(index_expr)
        cs=self._constant_string(index_expr)
        for recv in receivers:
            if isinstance(recv,ListValue):
                self._add_values(recv.elements,vals)
            elif isinstance(recv,MapValue):
                self._add_values(recv.values,vals)
            elif isinstance(recv,SchemaValue):
                if cs is None:
                    recv.opaque=True
                    recv.unsafe_reasons.add("sets a key whose name is computed at runtime")
                    self._add_values(recv.dynamic_values,vals)
                else:
                    tok,key=cs
                    lk=key.lower()
                    info=recv.keys.get(lk)
                    if info is None:
                        info=KeyInfo(key);recv.keys[lk]=info
                    if tok not in info.accesses and tok not in info.literals:
                        info.accesses.append(tok);self.changed=True
                    self._add_values(info.values,vals)

    def _assign_target(self,node:Node,vals:set[AValue]) -> None:
        """Propagate structured RHS values into lexicon/list assignment targets.

        This is monotone type-flow metadata only; it does not model runtime
        replacement/destruction.  Its purpose is to keep aliases created by
        SET target:key / target[index] visible to later key-use analysis.
        """
        terms=_suffix_terms(node)
        if not terms:
            return
        last=terms[-1]

        # Final [index] trailer: evaluate the target expression up to, but not
        # including, that trailer and add the RHS to the addressed container.
        sq_positions=[i for i,c in enumerate(last.children)
                      if isinstance(c,Token) and c.kind=="SQUAREOPEN"]
        if sq_positions:
            pos=sq_positions[-1]
            index_expr=last.children[pos+1] if pos+1<len(last.children) and isinstance(last.children[pos+1],Node) else None
            if index_expr is None:
                return
            base_term=Node("suffixterm",list(last.children[:pos]))
            base_terms=list(terms[:-1])+[base_term]
            receivers=self._eval_suffix(Node("suffix",base_terms))
            self._assign_schema_index(receivers,index_expr,vals)
            return

        # Plain final :suffix assignment.  Evaluate the receiver path without
        # the final suffix and attach the RHS to that key's abstract value set.
        if len(terms)<2 or len(last.children)!=1:
            return
        head=_term_head_token(last)
        if head is None:
            return
        receivers=self._eval_suffix(Node("suffix",list(terms[:-1])))
        name=head.text.lower()
        for recv in receivers:
            if not isinstance(recv,SchemaValue):
                continue
            if self._is_real_lexicon_suffix(name):
                if name in {"case", "casesensitive"}:
                    recv.opaque = True
                    recv.unsafe_reasons.add(
                        "uses :CASE/:CASESENSITIVE, so key identity can become case-sensitive"
                    )
                continue
            info=recv.keys.get(name)
            if info is None:
                info=KeyInfo(head.text);recv.keys[name]=info
            if head not in info.accesses:
                info.accesses.append(head);self.changed=True
            self._add_values(info.values,vals)

    def _walk(self,node:Node,current_delegate:Optional[DelegateValue]=None):
        k=node.kind
        if k=="program":
            for s in node.children:
                if isinstance(s,Node):self._walk(s,current_delegate)
            return
        if k in {"block","block_expr"}:
            d=self._delegate_for_body(node) if k=="block_expr" else current_delegate
            for s in node.attrs.get("statements",[]):self._walk(s,d)
            return
        if k=="function_decl":
            d=self._delegate_for_body(node.attrs["body"])
            self._walk(node.attrs["body"],d);return
        if k=="var_decl":
            for name,_op,value in node.attrs["decls"]:
                sym=self._symbol_for(name);vals=self.eval_expr(value)
                self._label_values(vals, name.text, construction=self._is_direct_lex_expr(value))
                if sym:self._add_values(self.symbol_values[id(sym)],vals)
                self._walk(value,current_delegate)
            return
        if k=="parameter_decl":
            for _name,_op,default in node.attrs["params"]:
                if default:self._walk(default,current_delegate)
            return
        if k=="set":
            for target,_to,value in node.attrs["pairs"]:
                vals=self.eval_expr(value);sym=self._simple_target_symbol(target)
                if sym:
                    self._label_values(vals, sym.token.text, construction=self._is_direct_lex_expr(value))
                    self._add_values(self.symbol_values[id(sym)],vals)
                self.eval_expr(target)
                self._assign_target(target,vals)
                self._walk(value,current_delegate)
            return
        if k=="return":
            vals:set[AValue]=set()
            for c in node.children:
                if isinstance(c,Node):vals.update(self.eval_expr(c))
            if current_delegate:
                self._add_values(current_delegate.returns,vals)
                if current_delegate.escaped:self._mark_escape(vals)
            return
        if k=="expr_stmt":
            for c in node.children:
                if isinstance(c,Node):self.eval_expr(c)
            return
        # Control statements: evaluate expression pieces and walk nested instructions.
        if k=="if":
            self.eval_expr(node.attrs["cond"]);self._walk(node.attrs["then"],current_delegate)
            if node.attrs.get("else"):self._walk(node.attrs["else"],current_delegate)
            return
        if k in {"until","on","when","for"}:
            for key in ("cond","target"):
                if isinstance(node.attrs.get(key),Node):self.eval_expr(node.attrs[key])
            if k=="for":
                coll=self.eval_expr(node.attrs["collection"])
                iter_values:set[AValue]=set()
                for v in coll:
                    if isinstance(v,ListValue):iter_values.update(v.elements)
                    elif isinstance(v,MapValue):iter_values.update(v.values)
                sym=self._symbol_for(node.attrs["iterator"])
                if sym:self._add_values(self.symbol_values[id(sym)],iter_values)
            body=node.attrs.get("body")
            if isinstance(body,Node):self._walk(body,current_delegate)
            return
        if k=="from":
            self._walk(node.attrs["init"],current_delegate);self.eval_expr(node.attrs["cond"])
            self._walk(node.attrs["step"],current_delegate);self._walk(node.attrs["body"],current_delegate);return
        # Generic expressions/statements: evaluating suffixes catches calls and key use.
        if k in {"suffix","or","and","compare","arith","mult","unary","factor","suffixterm","group","atom","ternary"}:
            self.eval_expr(node);return
        for child in _iter_child_nodes(node):self._walk(child,current_delegate)

    def _reset_escape_flags(self) -> None:
        seen:set[int]=set()

        def visit(value:AValue) -> None:
            if value is UNKNOWN_VALUE or id(value) in seen:return
            seen.add(id(value))
            if isinstance(value,SchemaValue):
                value.escaped=False
                for info in value.keys.values():
                    for nested in info.values:visit(nested)
                for nested in value.dynamic_values:visit(nested)
            elif isinstance(value,ListValue):
                value.escaped=False
                for nested in value.elements:visit(nested)
            elif isinstance(value,MapValue):
                value.escaped=False
                for nested in value.values:visit(nested)
            elif isinstance(value,FixedRecordValue):
                value.escaped=False
                for field_values in value.fields.values():
                    for nested in field_values:visit(nested)
            elif isinstance(value,DelegateValue):
                value.escaped=False
                for nested in value.returns:visit(nested)

        for value in self.node_values.values():visit(value)
        for values in self.symbol_values.values():
            for value in values:visit(value)
        for value in self.delegate_by_body.values():visit(value)
        for value in self.bound_delegates.values():visit(value)

    def _analysis_pass(self) -> None:
        self._walk(self.tree,None)
        # Anonymous block delegates can contain lexicons even when no call path
        # is statically exercised.  Analyze every discovered delegate body.
        for d in list(self.delegate_by_body.values()):
            self._walk(d.body,d)
        # During the escape phase, an escaped delegate exposes its return value.
        for d in list(self.delegate_by_body.values()):
            if d.escaped:self._mark_escape(d.returns)

    def analyze(self):
        # Phase 1: monotone value/type propagation with escape marking disabled.
        # This prevents provisional unknown receivers from permanently tainting
        # values whose concrete List/Lexicon/delegate type is learned later.
        self._reset_escape_flags()
        self.escape_phase=False
        for _ in range(64):
            self.changed=False
            self._analysis_pass()
            if not self.changed:break
        else:
            raise MinifyError("lexicon-key value analysis did not converge")

        # Phase 2: with receiver/call types stable, classify genuine escapes.
        # Repeat because escaping a delegate/container can expose nested values.
        self._reset_escape_flags()
        self.escape_phase=True
        for _ in range(64):
            self.changed=False
            self._analysis_pass()
            if not self.changed:break
        else:
            raise MinifyError("lexicon-key escape analysis did not converge")
        self.escape_phase=False

        self._propagate_nested_labels()

    def _schemas(self) -> list[SchemaValue]:
        schemas=[];seen=set()
        for v in self.node_values.values():
            if isinstance(v,SchemaValue) and id(v) not in seen:
                seen.add(id(v));schemas.append(v)
        schemas.sort(key=lambda s: s.origin_token.start if s.origin_token else 10**18)
        return schemas

    def _propagate_nested_labels(self) -> None:
        # A lexicon constructed directly as the value of another lexicon key is
        # identified by that construction path, e.g. runnerState:events.  This
        # is deliberately based only on the parent's construction identity, not
        # on later aliases such as `local events is runnerState:events`, because
        # prompt labels should tell the user where the lexicon was constructed.
        schemas=self._schemas()
        changed=True
        while changed:
            changed=False
            for parent in schemas:
                if not parent.construction_labels:
                    continue
                for info in parent.keys.values():
                    for value in info.values:
                        if not isinstance(value,SchemaValue):
                            continue
                        for base in parent.construction_labels:
                            label=f"{base}:{info.name}"
                            if label not in value.construction_labels:
                                value.construction_labels.add(label)
                                value.labels.add(label)
                                changed=True

    def _schema_key_rewriteable(self, schema: SchemaValue) -> bool:
        return bool(schema.keys) and not schema.opaque and not schema.escaped and not schema.unsafe_reasons

    def _key_equivalence_groups(self) -> list[list[tuple[SchemaValue,KeyInfo]]]:
        """Group key definitions that share a physical source access token.

        A union-typed value such as a valid/invalid transfer result can make the
        same `result:valid` token refer to the `valid` key in two different
        schemas.  Those KeyInfo objects must therefore receive the same renamed
        spelling.  Constructor literals do not create such a constraint; only
        shared access tokens do.
        """
        entries:list[tuple[SchemaValue,KeyInfo]]=[]
        for schema in self._schemas():
            for info in schema.keys.values():
                entries.append((schema,info))
        if not entries:return []

        parent=list(range(len(entries)))
        rank=[0]*len(entries)
        def find(x:int)->int:
            while parent[x]!=x:
                parent[x]=parent[parent[x]]
                x=parent[x]
            return x
        def union(a:int,b:int)->None:
            ra,rb=find(a),find(b)
            if ra==rb:return
            if rank[ra]<rank[rb]:ra,rb=rb,ra
            parent[rb]=ra
            if rank[ra]==rank[rb]:rank[ra]+=1

        by_access:dict[tuple[int,int],int]={}
        for idx,(_schema,info) in enumerate(entries):
            for tok in info.accesses:
                span=(tok.start,tok.end)
                other=by_access.get(span)
                if other is None:by_access[span]=idx
                else:union(idx,other)

        grouped:dict[int,list[tuple[SchemaValue,KeyInfo]]]=defaultdict(list)
        for idx,entry in enumerate(entries):grouped[find(idx)].append(entry)
        return list(grouped.values())

    def _schema_union_components(
        self, groups: Optional[list[list[tuple[SchemaValue,KeyInfo]]]] = None
    ) -> tuple[dict[int,int],dict[int,list[SchemaValue]]]:
        """Return schema components that can flow through the same key access.

        Once two schemas share even one source access token, *all* of their
        distinct renamed keys must avoid collisions.  Otherwise, for example,
        `reason -> B` in an invalid-result schema and `dvTotal -> B` in a valid
        result schema would turn every union-typed `result:B` access into both
        keys after rewriting.
        """
        schemas=self._schemas()
        if groups is None:groups=self._key_equivalence_groups()
        pos={id(schema):i for i,schema in enumerate(schemas)}
        parent=list(range(len(schemas)))
        rank=[0]*len(schemas)
        def find(x:int)->int:
            while parent[x]!=x:
                parent[x]=parent[parent[x]]
                x=parent[x]
            return x
        def union(a:int,b:int)->None:
            ra,rb=find(a),find(b)
            if ra==rb:return
            if rank[ra]<rank[rb]:ra,rb=rb,ra
            parent[rb]=ra
            if rank[ra]==rank[rb]:rank[ra]+=1
        for group in groups:
            members=list({pos[id(schema)] for schema,_info in group})
            for other in members[1:]:union(members[0],other)
        component_by_schema={id(schema):find(i) for i,schema in enumerate(schemas)}
        component_schemas:dict[int,list[SchemaValue]]=defaultdict(list)
        for schema in schemas:component_schemas[component_by_schema[id(schema)]].append(schema)
        return component_by_schema,component_schemas

    def _coordinated_mappings(self) -> dict[int,list[tuple[KeyInfo,str]]]:
        """Allocate short key names while respecting union-schema accesses.

        This is analogous to register allocation: key groups that coexist in a
        schema interfere and must have different names, while unrelated schemas
        may freely reuse A/B/etc.  A group touched by an unsafe/public schema is
        left at its original spelling so a shared access token can never rename
        only one side of a public/private union.
        """
        schemas=self._schemas()
        groups=self._key_equivalence_groups()
        component_by_schema,component_schemas=self._schema_union_components(groups)
        # `reserved_keys` is recorded per schema.  In a union-typed receiver, the
        # *same physical access token* can be a known key on one schema and a
        # reserved/missing key on a sibling schema (for example invalid.reason
        # versus valid.dvTotal).  Those cross-schema misses must not reserve the
        # spelling component-wide, or an already-minified union will permute its
        # keys again on the next pass.  Track access spans so only proven shared
        # accesses are exempted; an unrelated/dynamic reserved access still blocks
        # the spelling as before.
        component_known_accesses:dict[int,dict[str,set[tuple[int,int]]]]=defaultdict(
            lambda:defaultdict(set)
        )
        for schema in schemas:
            component_id=component_by_schema[id(schema)]
            for info in schema.keys.values():
                component_known_accesses[component_id][info.name.lower()].update(
                    (tok.start,tok.end) for tok in info.accesses
                )
        protected=(
            self.LEXICON_CALL_SUFFIXES | self.LEXICON_VALUE_SUFFIXES |
            self.STRUCTURE_CALL_SUFFIXES | self.STRUCTURE_VALUE_SUFFIXES
        )

        alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        generated:list[str]=[]
        key_count=sum(len(s.keys) for s in schemas)
        for length in itertools.count(1):
            generated.extend("".join(x) for x in itertools.product(alphabet,repeat=length))
            if len(generated)>max(1000,key_count*20):break

        # Names are unique across an entire union-schema component, not merely
        # within one schema.  Unrelated components can still reuse A/B/etc.
        assigned:dict[int,set[str]]=defaultdict(set)
        chosen_by_info:dict[int,str]={}

        # First reserve every key belonging to a non-rewriteable schema.  These
        # names are fixed and must constrain neighbouring renameable groups.
        renameable_groups=[]
        for group in groups:
            group_rewriteable=all(self._schema_key_rewriteable(schema) for schema,_ in group)
            if not group_rewriteable:
                for schema,info in group:
                    chosen_by_info[id(info)]=info.name
                    assigned[component_by_schema[id(schema)]].add(info.name.lower())
            else:
                renameable_groups.append(group)

        def first_pos(group:list[tuple[SchemaValue,KeyInfo]])->int:
            return min((t.start for _s,info in group for t in (info.literals+info.accesses)),default=10**18)

        renameable_groups.sort(key=lambda g:(-sum(info.occurrences for _s,info in g),first_pos(g)))
        for group in renameable_groups:
            # One source access token cannot spell two different keys.  This
            # should not arise for a statically-safe schema union; fail closed if
            # the analysis ever constructs such a contradictory group.
            originals={info.name.lower() for _schema,info in group}
            schemas_in_group={id(schema):schema for schema,_info in group}
            if len({(id(schema),info.name.lower()) for schema,info in group}) != len(group):
                # Exact duplicate KeyInfo membership is harmless.
                pass
            per_schema:dict[int,set[str]]=defaultdict(set)
            for schema,info in group:per_schema[id(schema)].add(info.name.lower())
            if any(len(names)>1 for names in per_schema.values()):
                for schema,_info in group:
                    schema.unsafe_reasons.add("one source key access resolves to multiple keys in the same schema")
                for schema,info in group:
                    chosen_by_info[id(info)]=info.name
                    assigned[component_by_schema[id(schema)]].add(info.name.lower())
                continue

            existing=None
            if len(originals)==1:
                existing=next(info.name for _schema,info in group)
            options=([existing] if existing is not None else [])+generated
            options=sorted(dict.fromkeys(options),key=lambda c:(len(c),0 if c==existing else 1,c))
            chosen=None
            for cand in options:
                lc=cand.lower()
                if lc in protected:continue
                blocked=False
                component_ids={component_by_schema[sid] for sid in schemas_in_group}
                if len(component_ids)!=1:
                    raise MinifyError("internal error: shared key group spans disconnected schema components")
                component_id=next(iter(component_ids))
                if lc in assigned[component_id]:
                    blocked=True
                else:
                    # A reserved spelling in any schema of the union component
                    # may become observable through the same receiver flow.
                    for component_schema in component_schemas[component_id]:
                        if lc in component_schema.reserved_keys:
                            reserved_spans=component_schema.reserved_accesses.get(lc,set())
                            known_spans=component_known_accesses[component_id].get(lc,set())
                            if not reserved_spans or not reserved_spans.issubset(known_spans):
                                blocked=True;break
                if not blocked:
                    chosen=cand;break
            if chosen is None:
                names=", ".join(sorted(originals))
                raise MinifyError(f"unable to allocate a lexicon key name for shared key group {names}")
            for schema,info in group:
                chosen_by_info[id(info)]=chosen
                assigned[component_by_schema[id(schema)]].add(chosen.lower())

        result:dict[int,list[tuple[KeyInfo,str]]]={id(schema):[] for schema in schemas}
        for schema in schemas:
            infos=list(schema.keys.values())
            def info_pos(info:KeyInfo)->int:
                toks=info.literals+info.accesses
                return min((t.start for t in toks),default=10**18)
            infos.sort(key=lambda x:(-x.occurrences,info_pos(x)))
            result[id(schema)]=[(info,chosen_by_info.get(id(info),info.name)) for info in infos]
        return result

    def _mapping_for(self, schema: SchemaValue) -> list[tuple[KeyInfo, str]]:
        return self._coordinated_mappings().get(id(schema),[])

    @staticmethod
    def _line_col(source: str, pos: int) -> tuple[int,int]:
        line=source.count("\n",0,pos)+1
        prev=source.rfind("\n",0,pos)
        col=pos+1 if prev<0 else pos-prev
        return line,col

    def plans(self, source: str) -> list[LexiconPlan]:
        self.analyze()
        plans:list[LexiconPlan]=[]
        for schema in self._schemas():
            tok=schema.origin_token
            pos=tok.start if tok is not None else min(
                (t.start for info in schema.keys.values() for t in info.literals),
                default=0,
            )
            line,col=self._line_col(source,pos)
            if schema.construction_labels:
                # Construction identity takes precedence over every later alias.
                # Prefer the most structurally specific path if more than one
                # construction label was learned for the same abstract schema.
                label=max(schema.construction_labels,key=lambda x:(x.count(":"),-len(x),x))
            elif schema.labels:
                label=min(schema.labels,key=lambda x:(len(x),x))
            else:
                label="anonymous lexicon"
            mapping=self._mapping_for(schema) if schema.keys else []
            reasons=sorted(schema.unsafe_reasons)
            if schema.opaque and not reasons:
                reasons=["contains a key access that cannot be statically rewritten"]
            if schema.escaped:
                reasons.append("escapes local scope, so its key names are part of an external/public contract")
            plans.append(LexiconPlan(
                schema=schema,
                label=label,
                line=line,
                column=col,
                mappings=[(info.name,new_name) for info,new_name in mapping],
                can_minify=(
                    bool(schema.keys)
                    and not schema.opaque
                    and not schema.escaped
                    and not reasons
                ),
                reasons=reasons,
            ))
        return plans

    def replacements_for(self, approved: set[int]) -> dict[tuple[int,int],str]:
        replacements:dict[tuple[int,int],str]={}
        schemas=self._schemas()
        index_by_schema={id(schema):index for index,schema in enumerate(schemas)}
        mappings=self._coordinated_mappings()

        # A shared source access token must be renamed for every participating
        # schema or for none of them.  Refuse a partial interactive approval
        # rather than silently changing an unapproved schema's contract.
        for group in self._key_equivalence_groups():
            member_indexes={index_by_schema[id(schema)] for schema,_info in group}
            changed=any(
                cand.lower()!=info.name.lower()
                for schema,info in group
                for mapped_info,cand in mappings.get(id(schema),[])
                if mapped_info is info
            )
            if not changed or len(member_indexes)<=1:
                continue
            selected=member_indexes & approved
            if selected and selected!=member_indexes:
                nums=", ".join(str(i+1) for i in sorted(member_indexes))
                raise MinifyError(
                    "lexicon schemas #"+nums+
                    " share a key access and must be approved together"
                )

        for index,schema in enumerate(schemas):
            if (
                index not in approved
                or schema.opaque
                or schema.escaped
                or schema.unsafe_reasons
                or not schema.keys
            ):
                continue
            for info,cand in mappings.get(id(schema),[]):
                info.new_name=cand
                for tok in info.literals:
                    replacement=_kos_quote_string(cand,tok)
                    if tok.text!=replacement:
                        replacements[(tok.start,tok.end)]=replacement
                for tok in info.accesses:
                    replacement=_kos_quote_string(cand,tok) if tok.kind=="STRING" else cand
                    if tok.text!=replacement:
                        replacements[(tok.start,tok.end)]=replacement
        return replacements


def _validate_lexicon_rewrite(
    before: Sequence[LexiconPlan],
    after: Sequence[LexiconPlan],
    approved: set[int],
) -> None:
    if len(before) != len(after):
        raise MinifyError(
            "internal validation failure: lexicon rewrite changed the number of discovered lexicons"
        )

    for index,(old_plan,new_plan) in enumerate(zip(before,after)):
        rename={old.lower():new.lower() for old,new in old_plan.mappings} if index in approved else {}
        expected={}
        for info in old_plan.schema.keys.values():
            name=rename.get(info.name.lower(),info.name.lower())
            expected[name]=expected.get(name,0)+info.occurrences
        actual={}
        for info in new_plan.schema.keys.values():
            name=info.name.lower()
            actual[name]=actual.get(name,0)+info.occurrences
        if expected != actual:
            raise MinifyError(
                "internal validation failure: lexicon key rewrite did not preserve "
                f"all tracked key occurrences for lexicon #{index + 1}"
            )

        if index in approved:
            # After a key has been renamed, any still-reachable use of its old
            # spelling will appear as an unknown/reserved key on the rewritten
            # schema.  Treat that as a hard validation failure rather than
            # emitting a script with a stale :suffix/["key"] access.
            renamed_old = {
                old.lower() for old,new in old_plan.mappings
                if old.lower() != new.lower()
            }
            stale = sorted(renamed_old & new_plan.schema.reserved_keys)
            if stale:
                raise MinifyError(
                    "internal validation failure: stale lexicon key access(es) "
                    f"remain after rewrite for lexicon #{index + 1}: " + ", ".join(stale)
                )


# ---------------------------------------------------------------------------
# Numeric literal minification
# ---------------------------------------------------------------------------

_INT_MIN = -(2**31)
_INT_MAX = 2**31 - 1

def _scalar_semantic(text: str):
    """Model ScalarValue.TryParse/TryParseDouble/Create for a positive literal.

    The unary sign is a separate grammar token in KerboScript, so `number` nodes
    contain only the unsigned literal.  Return (storage_kind, value) where
    storage_kind is "int" or "double".  Non-finite/invalid values return None.
    """
    s = text.replace("_", "").lower()
    try:
        needs_double = any(ch in s for ch in ".e")
        if not needs_double:
            try:
                n = int(s, 10)
            except ValueError:
                return None
            if _INT_MIN <= n <= _INT_MAX:
                return ("int", n)
            v = float(s)
        else:
            v = float(s)
    except (ValueError, OverflowError):
        return None

    if not math.isfinite(v):
        return None

    # ScalarValue.Create(double) converts exact integral doubles strictly inside
    # Int32 bounds back to ScalarIntValue.
    if _INT_MIN < v < _INT_MAX and v.is_integer():
        return ("int", int(v))
    return ("double", struct.pack(">d", v))


def _normalise_number_text(text: str) -> str:
    """Remove representation-only bytes while retaining kOS numeric grammar."""
    s = text.replace("_", "").lower()
    if "e" in s:
        mantissa, exponent = s.split("e", 1)
    else:
        mantissa, exponent = s, None

    if "." in mantissa:
        whole, frac = mantissa.split(".", 1)
        frac = frac.rstrip("0")
        if frac:
            mantissa = (whole if whole != "0" else "") + "." + frac
        else:
            mantissa = whole or "0"

    if exponent is None:
        return mantissa

    sign = ""
    if exponent.startswith(("+", "-")):
        if exponent[0] == "-":
            sign = "-"
        exponent = exponent[1:]
    exponent = exponent.lstrip("0") or "0"

    # e0 is always redundant.
    if exponent == "0":
        return mantissa
    return mantissa + "e" + sign + exponent


def _number_source(node: Node) -> str:
    return "".join(c.text for c in node.children if isinstance(c, Token))


def _equivalent_decimal_placements(text: str) -> set[str]:
    """Return exact base-10-equivalent mantissa/exponent placements.

    Python's ``g``/``e`` formatters conventionally keep one digit before the
    decimal point in scientific notation.  KerboScript does not require that
    convention, so spellings such as ``14e3`` and ``1234e-7`` can be shorter
    than ``1.4e4`` and ``1.234e-4`` respectively.

    This helper moves the decimal point through every position in the existing
    digit sequence and compensates the exponent exactly.  The caller still
    validates every result with ``_scalar_semantic`` before accepting it.
    """
    s = _normalise_number_text(text)
    if not s:
        return set()

    if "e" in s:
        mantissa, exponent_text = s.split("e", 1)
        try:
            exponent = int(exponent_text, 10)
        except ValueError:
            return {s}
    else:
        mantissa = s
        exponent = 0

    if "." in mantissa:
        whole, frac = mantissa.split(".", 1)
        digits = whole + frac
        point = len(whole)
    else:
        digits = mantissa
        point = len(mantissa)

    if not digits or not digits.isdigit():
        return {s}

    out = {s}
    for new_point in range(len(digits) + 1):
        if new_point == 0:
            new_mantissa = "." + digits
        elif new_point == len(digits):
            new_mantissa = digits
        else:
            new_mantissa = digits[:new_point] + "." + digits[new_point:]

        new_exponent = exponent + point - new_point
        candidate = new_mantissa
        if new_exponent:
            candidate += "e" + str(new_exponent)
        out.add(_normalise_number_text(candidate))

    return out


def _shortest_number_literal(node: Node) -> str:
    """Return the shortest byte representation with identical Scalar semantics."""
    original = _number_source(node)
    target = _scalar_semantic(original)
    if target is None:
        return original

    base = _normalise_number_text(original)
    candidates = {original, base}

    # Python's binary64 conversion and formatting are correctly rounded for
    # ordinary finite IEEE-754 doubles, matching .NET Double.Parse semantics.
    # Generate both general and explicit-exponent forms, then accept a candidate
    # only if our ScalarValue model says its storage kind/value is identical.
    try:
        raw = original.replace("_", "")
        value = float(raw)
    except (ValueError, OverflowError):
        value = None

    if value is not None and math.isfinite(value):
        candidates.add(_normalise_number_text(repr(value)))
        # 17 significant digits are sufficient to round-trip any binary64.
        for precision in range(1, 18):
            candidates.add(_normalise_number_text(format(value, f".{precision}g")))
        for decimals in range(0, 17):
            candidates.add(_normalise_number_text(format(value, f".{decimals}e")))

        if value.is_integer():
            # This is often useful for values which originated as doubles but
            # whose plain integer spelling is shorter.
            try:
                candidates.add(str(int(value)))
            except (OverflowError, ValueError):
                pass

    # Scientific notation does not require the conventional one-digit
    # mantissa.  Explore every exact decimal-point placement for every
    # candidate before the semantic guard chooses the true shortest spelling.
    expanded = set(candidates)
    for candidate in tuple(candidates):
        expanded.update(_equivalent_decimal_placements(candidate))
    candidates = expanded

    valid = []
    for candidate in candidates:
        if not candidate:
            continue
        # Grammar shape: INTEGER or DOUBLE, optionally followed by E +/- INTEGER.
        if not re.fullmatch(r"(?:\d+|\d*\.\d+)(?:e[+-]?\d+)?", candidate):
            continue
        if _scalar_semantic(candidate) == target:
            valid.append(candidate)

    if not valid:
        return original

    # Keep the existing spelling on equal length; changing it gains no bytes.
    return min(valid, key=lambda s: (len(s), 0 if s == original else 1, s))


def _number_parts(node: Node) -> list[str]:
    """Split a minimized literal into the exact tokens expected by the parser."""
    text = _shortest_number_literal(node)
    if "e" not in text:
        return [text]
    mantissa, exponent = text.split("e", 1)
    out = [mantissa, "e"]
    if exponent.startswith(("+", "-")):
        out.append(exponent[0])
        exponent = exponent[1:]
    out.append(exponent)
    return out


# ---------------------------------------------------------------------------
# Rendering / structural minification
# ---------------------------------------------------------------------------
#
# This pass is deliberately syntax-only apart from the explicitly user-approved
# lexicon-key rewrite performed before it.  It merges grammar-equivalent
# declarations/SETs, removes proven-redundant braces, shortens numeric literals,
# renames private symbols, and later removes parser-safe whitespace.  Other string
# literals/runtime data remain opaque.  It does NOT perform semantic peepholes (dead expression removal, constant folding,
# bound-variable shortcuts such as SHIP:ORBIT -> OBT, or built-in alias changes
# such as LEXICON -> LEX).  Those belong in the manual normalization stage.

class Renderer:
    def __init__(self, replacements: dict[tuple[int, int], str]):
        self.replacements = replacements

    def token(self, tok: Token) -> str:
        return self.replacements.get((tok.start, tok.end), tok.text)

    def render(self, tree: Node) -> list[str]:
        return self._node(tree)

    def _node(self, node: Node) -> list[str]:
        k = node.kind
        if k == "program":
            return self._statement_sequence([x for x in node.children if isinstance(x, Node)])
        if k == "number":
            return _number_parts(node)
        if k in {"block", "block_expr"}:
            return ["{"] + self._statement_sequence(node.attrs.get("statements", [])) + ["}"]
        if k == "set":
            return self._render_set_pairs(node.attrs["pairs"])
        if k == "var_decl":
            return self._render_var_decl(node.attrs.get("modifier"), node.attrs["decls"])
        if k == "parameter_decl":
            return self._render_parameter_decl(node.attrs.get("modifier"), node.attrs["params"])
        if k == "function_decl":
            prefix = []
            if node.attrs.get("modifier") in {"local", "global"}: prefix.append(node.attrs["modifier"])
            prefix += ["function", self.token(node.attrs["name"])]
            return prefix + self._node(node.attrs["body"])
        if k == "lock_decl":
            prefix=[]
            if node.attrs.get("modifier") in {"local", "global"}: prefix.append(node.attrs["modifier"])
            return prefix + ["lock", self.token(node.attrs["name"]), "to"] + self._node(node.attrs["value"]) + ["."]
        if k == "if":
            out=["if"] + self._node(node.attrs["cond"]) + self._instruction_body(node.attrs["then"], parent_if_has_else=node.attrs.get("else") is not None)
            if node.attrs.get("else") is not None:
                out += ["else"] + self._instruction_body(node.attrs["else"], parent_if_has_else=False)
            return out
        if k == "until":
            return ["until"] + self._node(node.attrs["cond"]) + self._instruction_body(node.attrs["body"])
        if k == "on":
            return ["on"] + self._node(node.attrs["target"]) + self._instruction_body(node.attrs["body"])
        if k == "when":
            return ["when"] + self._node(node.attrs["cond"]) + ["then"] + self._instruction_body(node.attrs["body"])
        if k == "for":
            return ["for", self.token(node.attrs["iterator"]), "in"] + self._node(node.attrs["collection"]) + self._instruction_body(node.attrs["body"])
        if k == "from":
            return ["from"] + self._node(node.attrs["init"]) + ["until"] + self._node(node.attrs["cond"]) + ["step"] + self._node(node.attrs["step"]) + ["do"] + self._instruction_body(node.attrs["body"])
        # Generic nodes retain parser-consumed terminal ordering.
        out=[]
        for child in node.children:
            if isinstance(child, Token): out.append(self.token(child))
            elif isinstance(child, Node): out += self._node(child)
            elif isinstance(child, list):
                for item in child:
                    if isinstance(item, Token): out.append(self.token(item))
                    elif isinstance(item, Node): out += self._node(item)
        return out

    def _instruction_body(self, node: Node, parent_if_has_else=False) -> list[str]:
        if node.kind == "block":
            stmts = [s for s in node.attrs.get("statements", []) if s.kind != "empty"]
            # Adjacent SET statements are emitted as one comma-SET by the normal
            # statement-sequence pass.  Treat that merged form as one instruction
            # here too, so braces are not retained merely because the source had
            # two or more adjacent SET statements.
            if stmts and all(s.kind == "set" for s in stmts):
                pairs = []
                for stmt in stmts:
                    pairs.extend(stmt.attrs["pairs"])
                return self._render_set_pairs(pairs)
            if self._can_unbrace(node, parent_if_has_else):
                return self._node(stmts[0])
        return self._node(node)

    def _can_unbrace(self, block: Node, parent_if_has_else=False) -> bool:
        stmts=[s for s in block.attrs.get("statements", []) if s.kind != "empty"]
        if len(stmts) != 1:
            return False
        stmt=stmts[0]
        # Removing a lexical scope containing a declaration is not semantics-neutral.
        if stmt.kind in {"var_decl", "parameter_decl", "function_decl", "lock_decl"}:
            return False
        # Avoid dangling-else reassociation.  Other single instructions are safe;
        # FOR itself owns the iterator scope in the kOS compiler.
        if parent_if_has_else and stmt.kind == "if" and stmt.attrs.get("else") is None:
            return False
        return True

    def _statement_sequence(self, statements: Sequence[Node]) -> list[str]:
        out=[]; i=0
        stmts=[s for s in statements if s.kind != "empty"]
        while i < len(stmts):
            cur=stmts[i]
            if cur.kind == "set":
                pairs=list(cur.attrs["pairs"]); j=i+1
                while j<len(stmts) and stmts[j].kind=="set":
                    pairs.extend(stmts[j].attrs["pairs"]); j+=1
                out += self._render_set_pairs(pairs); i=j; continue
            if cur.kind == "var_decl":
                mod=cur.attrs.get("modifier"); decls=list(cur.attrs["decls"]); j=i+1
                while j<len(stmts) and stmts[j].kind=="var_decl" and stmts[j].attrs.get("modifier")==mod:
                    decls.extend(stmts[j].attrs["decls"]); j+=1
                out += self._render_var_decl(mod,decls); i=j; continue
            if cur.kind == "parameter_decl":
                mod=cur.attrs.get("modifier"); params=list(cur.attrs["params"]); j=i+1
                while j<len(stmts) and stmts[j].kind=="parameter_decl" and stmts[j].attrs.get("modifier")==mod:
                    params.extend(stmts[j].attrs["params"]); j+=1
                out += self._render_parameter_decl(mod,params); i=j; continue
            out += self._node(cur); i+=1
        return out

    def _render_set_pairs(self, pairs) -> list[str]:
        out=["set"]
        for idx,(target,_to,value) in enumerate(pairs):
            if idx: out.append(",")
            out += self._node(target) + ["to"] + self._node(value)
        return out+["."]

    def _render_var_decl(self, modifier, decls) -> list[str]:
        # Bare variable declarations require DECLARE; local/global are shorter.
        out=[modifier] if modifier in {"local","global"} else ["declare"]
        for idx,(name,op,value) in enumerate(decls):
            if idx: out.append(",")
            out += [self.token(name), self.token(op)] + self._node(value)
        return out+["."]

    def _render_parameter_decl(self, modifier, params) -> list[str]:
        out=[]
        if modifier in {"local","global"}: out.append(modifier)
        out.append("parameter")
        for idx,(name,op,default) in enumerate(params):
            if idx: out.append(",")
            out.append(self.token(name))
            if op is not None:
                out.append(self.token(op)); out += self._node(default)
        return out+["."]

# ---------------------------------------------------------------------------
# Scanner-trace whitespace minimization
# ---------------------------------------------------------------------------

def parse_source(source: str) -> Node:
    return Parser(source).parse()

def parse_source_with_trace(source: str) -> tuple[Node, list[ScanEvent]]:
    parser = Parser(source, capture_trace=True)
    tree = parser.parse()
    return tree, parser.scanner.trace

def join_parts(parts: Sequence[str], separators: Sequence[str]) -> str:
    if not parts:
        return ""
    buf = [parts[0]]
    for sep, part in zip(separators, parts[1:]):
        buf += [sep, part]
    return "".join(buf)

def _same_token_text(kind: str, actual: str, intended: str) -> bool:
    if kind in {"IDENTIFIER", "FILEIDENT"}:
        return actual.lower() == intended.lower()
    return actual == intended

def _validate_trace_parts(parts: Sequence[str], trace: Sequence[ScanEvent]) -> None:
    if len(parts) != len(trace):
        raise MinifyError(
            "internal validation failure: rendered token count does not match parser trace "
            f"({len(parts)} parts, {len(trace)} tokens)"
        )
    for i, (part, event) in enumerate(zip(parts, trace)):
        if not _same_token_text(event.kind, event.text, part):
            raise MinifyError(
                "internal validation failure: rendered token does not match parser trace "
                f"at token {i}: {part!r} vs {event.kind} {event.text!r}"
            )
        if not event.probes or event.probes[-1].result_kind != event.kind:
            raise MinifyError(
                "internal validation failure: scanner trace has no successful final probe "
                f"for token {i} ({event.kind} {event.text!r})"
            )

def _match_kind_at(source: str, lower: str, kind: str, pos: int) -> int:
    if kind == "IDENTIFIER":
        n = _match_identifier(source, pos)
        return n if n else -1
    if kind == "FILEIDENT":
        n = _match_fileident(source, pos)
        return n if n else -1
    if kind == "EOF":
        return 0 if pos == len(source) else -1
    m = TOKEN_REGEX[kind].match(source, pos)
    return (m.end() - pos) if m and m.start() == pos else -1

def _probe_at(source: str, lower: str, pos: int,
              expected: Sequence[str]) -> tuple[str, int]:
    # TinyPG considers skip tokens before the grammar token.  In minified output
    # there must never be whitespace/comment text *at* an intended token start.
    ws_end = _skip_kos_whitespace(source, pos)
    if ws_end != pos:
        return "SKIP", ws_end - pos
    m = COMMENT_RE.match(source, pos)
    if m:
        return "SKIP", m.end() - pos

    best_kind = "UNDETERMINED"
    best_len = -1
    best_order = 10**9
    candidates = expected or tuple(name for name, _ in TOKEN_SPECS)
    for kind in candidates:
        n = _match_kind_at(source, lower, kind, pos)
        if n < 0:
            continue
        order = TOKEN_ORDER.get(kind, 10**8)
        if n > best_len or (n == best_len and order < best_order):
            best_kind = kind
            best_len = n
            best_order = order
    return best_kind, best_len

def _segment_is_valid(parts: Sequence[str], trace: Sequence[ScanEvent],
                      start: int, end: int) -> bool:
    """Validate one contiguous no-whitespace token segment.

    A trailing space is deliberate: later tokens have not been joined yet.
    If a future join can extend an earlier token (e.g. TRUE '.' IF becoming
    FILEIDENT 'true.if'), that earlier probe is rechecked when the segment grows.
    """
    segment_parts = parts[start:end + 1]
    text = "".join(segment_parts) + " "
    lower = text  # kept as an argument for the local probe API; regexes are IGNORECASE
    offsets = []
    pos = 0
    for part in segment_parts:
        offsets.append(pos)
        pos += len(part)

    for rel, token_index in enumerate(range(start, end + 1)):
        event = trace[token_index]
        token_pos = offsets[rel]
        intended_len = len(parts[token_index])
        for probe in event.probes:
            kind, length = _probe_at(text, lower, token_pos, probe.expected)
            if kind != probe.result_kind:
                return False
            if kind != "UNDETERMINED":
                if kind != event.kind or length != intended_len:
                    return False
    return True

def minimize_whitespace(parts: list[str], trace: Sequence[ScanEvent],
                        progress: Optional[callable] = None) -> str:
    """Greedily emit the shortest safe separator at each token boundary.

    This does *not* reparse the file for each boundary.  It grows one contiguous
    no-space segment and replays only the scanner probes belonging to that local
    segment.  When joining the next token would change any TinyPG lookahead, a
    single space is emitted and the segment restarts.

    The choice is fail-closed and context-sensitive: `parameter A.return` may be
    accepted where the parser had already committed to EOI, while
    `...else true.if...` is rejected because FILEIDENT would win the atom probe.

    STRING tokens are opaque parts; their internal whitespace is never touched.
    """
    if not parts:
        return ""

    _validate_trace_parts(parts, trace)
    separators = [""] * (len(parts) - 1)
    segment_start = 0
    retained = 0
    total = len(separators)
    next_report = 10

    for boundary in range(total):
        # Try extending the current no-space segment through the next token.
        if not _segment_is_valid(parts, trace, segment_start, boundary + 1):
            separators[boundary] = " "
            retained += 1
            segment_start = boundary + 1
            # A single token followed by a barrier must always reproduce its
            # original scanner probes; otherwise our trace model is inconsistent.
            if not _segment_is_valid(parts, trace, segment_start, segment_start):
                raise MinifyError(
                    "internal validation failure: isolated token does not reproduce "
                    f"scanner trace at token {segment_start}"
                )

        if progress and total:
            pct = int(100 * (boundary + 1) / total)
            if pct >= next_report:
                progress(
                    f"Whitespace scan: {boundary + 1}/{total} boundaries "
                    f"({pct}%), {retained} separators retained"
                )
                next_report += 10

    return join_parts(parts, separators)

def _digest_value(value, memo: dict[int, bytes]) -> bytes:
    h = hashlib.blake2b(digest_size=20)
    if isinstance(value, Token):
        h.update(b"T\0")
        h.update(value.kind.encode())
        h.update(b"\0")
        text = value.text.lower() if value.kind in {"IDENTIFIER", "FILEIDENT"} else value.text
        h.update(text.encode("utf-8"))
    elif isinstance(value, Node):
        oid = id(value)
        cached = memo.get(oid)
        if cached is not None:
            return cached
        # Store a temporary cycle marker. Scope/symbol attrs are excluded and
        # the parser AST should otherwise be acyclic.
        memo[oid] = b"\xff" * 20
        h.update(b"N\0")
        h.update(value.kind.encode())
        h.update(b"\0C")
        for child in value.children:
            h.update(_digest_value(child, memo))
        h.update(b"\0A")
        for key in sorted(k for k in value.attrs if k not in {"scope", "symbol"}):
            h.update(key.encode())
            h.update(b"=")
            h.update(_digest_value(value.attrs[key], memo))
        digest = h.digest()
        memo[oid] = digest
        return digest
    elif isinstance(value, (list, tuple)):
        h.update(b"L\0")
        for item in value:
            h.update(_digest_value(item, memo))
    elif isinstance(value, dict):
        h.update(b"D\0")
        for key in sorted(value):
            h.update(str(key).encode())
            h.update(b"=")
            h.update(_digest_value(value[key], memo))
    elif value is None:
        h.update(b"0")
    elif isinstance(value, bool):
        h.update(b"B1" if value else b"B0")
    else:
        h.update(b"V\0")
        h.update(repr(value).encode("utf-8"))
    return h.digest()

def tree_digest(tree: Node) -> bytes:
    """Compact, memoized structural digest; avoids giant recursive fingerprints."""
    return _digest_value(tree, {})

def minify_source(
    source: str,
    progress: Optional[callable] = None,
    lexicon_decider: Optional[callable] = None,
) -> tuple[str, dict[str, str]]:
    status = progress or (lambda _msg: None)

    status("Parsing input")
    original_tree = parse_source(source)

    # Lexicon keys are runtime data, so the tool never decides on its own that
    # they are private.  It discovers statically-rewriteable schemas and lets
    # the caller/user opt in one lexicon at a time.
    status("Analysing lexicon keys")
    lex_symbols = SymbolAnalyzer(original_tree)
    lex_analyzer = LexiconKeyAnalyzer(original_tree, lex_symbols)
    lex_plans = lex_analyzer.plans(source)
    approved_lexicons: set[int] = set()
    if lexicon_decider is not None:
        for index, plan in enumerate(lex_plans):
            if lexicon_decider(plan):
                if not plan.can_minify:
                    raise MinifyError(
                        f"internal error: lexicon decision approved an unsafe lexicon at line {plan.line}"
                    )
                approved_lexicons.add(index)
    key_replacements = lex_analyzer.replacements_for(approved_lexicons)

    # Structural simplification can remove lexical blocks that contain no
    # declarations and can merge adjacent statements.  Perform it BEFORE symbol
    # allocation so the interference graph describes the code that will actually
    # be emitted, rather than requiring repeated external minifier passes.
    status("Applying structural, numeric and approved lexicon-key minification before symbol allocation")
    structural_parts = Renderer(key_replacements).render(original_tree)
    structural_safe = " ".join(structural_parts)

    status("Re-parsing transformed structure for final scope graph")
    working_tree = parse_source(structural_safe)

    if approved_lexicons:
        status("Validating approved lexicon-key rewrites")
        post_lex_symbols=SymbolAnalyzer(working_tree)
        post_lex_analyzer=LexiconKeyAnalyzer(working_tree,post_lex_symbols)
        post_lex_plans=post_lex_analyzer.plans(structural_safe)
        _validate_lexicon_rewrite(lex_plans,post_lex_plans,approved_lexicons)

    status("Analysing lexical scopes and symbols")
    analyzer = SymbolAnalyzer(working_tree)
    replacements = analyzer.allocate_names()

    status("Rendering final structural transforms, renaming and numeric literals")
    renderer = Renderer(replacements)
    parts = renderer.render(working_tree)
    safe = " ".join(parts)

    status("Validating renamed bindings and capturing exact scanner probes")
    transformed_tree, trace = parse_source_with_trace(safe)
    renamed_analyzer = SymbolAnalyzer(transformed_tree)
    _validate_binding_preservation(analyzer, renamed_analyzer)
    transformed_digest = tree_digest(transformed_tree)

    status(f"Minimizing whitespace across {max(0, len(parts) - 1)} token boundaries")
    out = minimize_whitespace(parts, trace, progress=status)

    status("Validating final minified source")
    final_tree = parse_source(out)
    if tree_digest(final_tree) != transformed_digest:
        raise MinifyError(
            "internal validation failure: final parse differs from transformed parse"
        )

    mapping = {}
    for sym in analyzer.symbols:
        if sym.new_name and sym.token.text.lower() != sym.new_name.lower():
            mapping[f"{sym.kind}:{sym.token.text}@{sym.token.start}"] = sym.new_name
    for index in sorted(approved_lexicons):
        plan=lex_plans[index]
        for old_key,new_key in plan.mappings:
            if old_key != new_key:
                mapping[f"lexicon:{plan.label}:{old_key}@line{plan.line}"] = new_key
    return out, mapping


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _prompt_lexicon_keys(plan: LexiconPlan) -> bool:
    exposure = " [escapes local scope]" if plan.schema.escaped else ""
    print(
        f"[minify] Lexicon at line {plan.line}, column {plan.column}: "
        f"{plan.label}{exposure}",
        file=sys.stderr,
        flush=True,
    )

    if not plan.mappings:
        if plan.reasons:
            print("[minify]   Cannot minify keys:", file=sys.stderr)
            for reason in plan.reasons:
                print(f"[minify]     - {reason}", file=sys.stderr)
        else:
            print("[minify]   No statically-known keys to minify.", file=sys.stderr)
        return False

    if not plan.can_minify:
        print("[minify]   Keys:", file=sys.stderr)
        for old_key,new_key in plan.mappings:
            print(f"[minify]     {old_key}", file=sys.stderr)
        print("[minify]   Cannot minify keys:", file=sys.stderr)
        for reason in plan.reasons:
            print(f"[minify]     - {reason}", file=sys.stderr)
        return False

    print("[minify]   Proposed key mapping:", file=sys.stderr)
    for old_key,new_key in plan.mappings:
        marker = "" if old_key != new_key else " (unchanged)"
        print(f"[minify]     {old_key} -> {new_key}{marker}", file=sys.stderr)
    print("[minify]   Minify these keys? [y/N]: ", end="", file=sys.stderr, flush=True)
    answer=sys.stdin.readline()
    if answer == "":
        print("[minify]   No input available; leaving keys unchanged.", file=sys.stderr)
        return False
    return answer.strip().lower() in {"y", "yes"}

def main(argv: Optional[Sequence[str]]=None) -> int:
    ap=argparse.ArgumentParser(
        description=f"Parser-validated KerboScript minifier (kOS {KOS_VERSION} grammar).")
    ap.add_argument("input", type=Path)
    ap.add_argument("output", type=Path)
    ap.add_argument("--show-map", action="store_true", help="print identifier rename map to stderr")
    ap.add_argument(
        "--accept-safe-lexicon-keys", action="store_true",
        help="non-interactively approve every lexicon-key rewrite proven safe by the analyzer",
    )
    ns=ap.parse_args(argv)

    src=ns.input.expanduser()
    dst=ns.output.expanduser()
    if not src.is_file():
        ap.error(f"input file does not exist or is not a file: {src}")
    # resolve(strict=False) permits a not-yet-created output path.
    if src.resolve() == dst.resolve(strict=False):
        ap.error("input and output paths resolve to the same file")
    if dst.exists():
        ap.error(f"output file already exists; refusing to overwrite: {dst}")

    try:
        print(f"[minify] Reading {src}", file=sys.stderr, flush=True)
        text=src.read_text(encoding="utf-8")
        lexicon_decider = (
            (lambda plan: plan.can_minify)
            if ns.accept_safe_lexicon_keys else _prompt_lexicon_keys
        )
        result,mapping=minify_source(
            text,
            progress=lambda msg: print(f"[minify] {msg}", file=sys.stderr, flush=True),
            lexicon_decider=lexicon_decider,
        )
    except (OSError,UnicodeError,MinifyError) as exc:
        print(f"minify.py: error: {exc}",file=sys.stderr)
        return 2

    # Do not create/truncate the destination until all parsing and validation succeeds.
    try:
        print(f"[minify] Writing {dst}", file=sys.stderr, flush=True)
        dst.parent.mkdir(parents=True,exist_ok=True)
        # Exclusive creation also closes the race between the exists() check and write.
        with dst.open("x",encoding="utf-8",newline="") as f:
            f.write(result)
    except FileExistsError:
        print(f"minify.py: error: output file already exists; refusing to overwrite: {dst}",file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"minify.py: error: {exc}",file=sys.stderr)
        return 2

    if ns.show_map:
        for old,new in mapping.items():
            print(f"{old} -> {new}",file=sys.stderr)
    print(f"{src}: {len(text.encode('utf-8'))} bytes -> {len(result.encode('utf-8'))} bytes -> {dst}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
