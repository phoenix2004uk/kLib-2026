#!/usr/bin/env python3
from __future__ import annotations

import argparse
import dataclasses
import re
import sys
from pathlib import Path
from typing import Optional, Sequence

KOS_VERSION = "1.6.0.1"

# Direct aliases registered by the same kOS [Function(...)] implementation.
# Only standalone calls are rewritten: LONGNAME(...) -> SHORTNAME(...).
FUNCTION_ALIASES = {
    "lexicon": "lex",
    "vectorcrossproduct": "vcrs",
    "vectordotproduct": "vdot",
    "vectorexclude": "vxcl",
    "vectorangle": "vang",
    "chdir": "cd",
    "timestamp": "time",
}

# Exact/prefix bound-expression shortcuts.
#
# A rule may match the prefix of a longer suffix chain.  For example:
#   ship:facing:forevector -> facing:forevector
# because FACING is documented as exactly the same value as SHIP:FACING.
#
# Longer rules are tried first, so:
#   ship:orbit:apoapsis -> apoapsis
# wins over:
#   ship:orbit -> obt
#
# No receiver-dependent suffix aliases are included here.
BOUND_SHORTCUTS = {
    # Longer current-orbit shortcuts.
    ("ship", "orbit", "apoapsis"): "apoapsis",
    ("ship", "obt", "apoapsis"): "apoapsis",
    ("ship", "orbit", "periapsis"): "periapsis",
    ("ship", "obt", "periapsis"): "periapsis",
    ("ship", "orbit", "eta"): "eta",
    ("ship", "obt", "eta"): "eta",

    # ORBIT and OBT are aliases on Orbitable, while OBT is a SHIP shortcut.
    ("ship", "orbit"): "obt",

    # Documented SHIP field shortcuts.
    ("ship", "heading"): "heading",
    ("ship", "prograde"): "prograde",
    ("ship", "retrograde"): "retrograde",
    ("ship", "facing"): "facing",
    ("ship", "maxthrust"): "maxthrust",
    ("ship", "availablethrust"): "availablethrust",
    ("ship", "velocity"): "velocity",
    ("ship", "geoposition"): "geoposition",
    ("ship", "latitude"): "latitude",
    ("ship", "longitude"): "longitude",
    ("ship", "up"): "up",
    ("ship", "north"): "north",
    ("ship", "body"): "body",
    ("ship", "angularmomentum"): "angularmomentum",
    ("ship", "angularvel"): "angularvel",
    ("ship", "mass"): "mass",
    ("ship", "verticalspeed"): "verticalspeed",
    ("ship", "groundspeed"): "groundspeed",
    ("ship", "airspeed"): "airspeed",
    ("ship", "altitude"): "altitude",
    ("ship", "apoapsis"): "apoapsis",
    ("ship", "periapsis"): "periapsis",
    ("ship", "sensors"): "sensors",
    ("ship", "srfprograde"): "srfprograde",
    ("ship", "srfretrograde"): "srfretrograde",
    ("ship", "obt"): "obt",
    ("ship", "status"): "status",
    ("ship", "name"): "shipname",
    ("ship", "shipname"): "shipname",
}

# Match the longest shortcut first.
BOUND_RULES = sorted(BOUND_SHORTCUTS.items(), key=lambda item: len(item[0]), reverse=True)

_IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
_NUMBER_RE = re.compile(
    r"(?:\d+(?:_\d*)*\.\d*(?:_\d*)*|\.\d+(?:_\d*)*|\d+(?:_\d*)*)"
    r"(?:[eE][+-]?\d+(?:_\d*)*)?"
)

class NormalizeError(Exception):
    pass

@dataclasses.dataclass(frozen=True)
class Token:
    kind: str
    text: str
    start: int
    end: int
    line: int
    col: int

    @property
    def lower(self) -> str:
        return self.text.lower()

@dataclasses.dataclass(frozen=True)
class Change:
    start: int
    end: int
    replacement: str
    line: int
    col: int
    old: str
    reason: str


def tokenize(source: str) -> list[Token]:
    out: list[Token] = []
    i = 0
    line = 1
    col = 1
    n = len(source)

    def emit(kind: str, start: int, end: int, start_line: int, start_col: int):
        out.append(Token(kind, source[start:end], start, end, start_line, start_col))

    while i < n:
        start = i
        start_line = line
        start_col = col
        ch = source[i]

        if ch.isspace():
            i += 1
            while i < n and source[i].isspace():
                i += 1
            text = source[start:i]
            emit("WS", start, i, start_line, start_col)
            breaks = list(re.finditer(r"\r\n|\r|\n", text))
            if breaks:
                line += len(breaks)
                col = len(text) - breaks[-1].end() + 1
            else:
                col += len(text)
            continue

        if source.startswith("//", i):
            i += 2
            while i < n and source[i] not in "\r\n":
                i += 1
            emit("COMMENT", start, i, start_line, start_col)
            col += i - start
            continue

        # kOS string token: optional @ then "...", with doubled "" escapes.
        if ch == '"' or (ch == "@" and i + 1 < n and source[i + 1] == '"'):
            if ch == "@":
                i += 1
            i += 1  # opening quote
            while i < n:
                if source[i] == '"':
                    if i + 1 < n and source[i + 1] == '"':
                        i += 2
                        continue
                    i += 1
                    break
                if source[i] in "\r\n":
                    raise NormalizeError(
                        f"unterminated string at {start_line}:{start_col}"
                    )
                i += 1
            else:
                raise NormalizeError(
                    f"unterminated string at {start_line}:{start_col}"
                )
            emit("STRING", start, i, start_line, start_col)
            col += i - start
            continue

        m = _IDENT_RE.match(source, i)
        if m:
            i = m.end()
            emit("IDENT", start, i, start_line, start_col)
            col += i - start
            continue

        m = _NUMBER_RE.match(source, i)
        if m:
            i = m.end()
            emit("NUMBER", start, i, start_line, start_col)
            col += i - start
            continue

        i += 1
        emit("PUNC", start, i, start_line, start_col)
        col += 1

    return out


def significant(tokens: list[Token]) -> list[Token]:
    return [t for t in tokens if t.kind not in {"WS", "COMMENT"}]


def contains_clobberbuiltins_on(sig: list[Token]) -> bool:
    for i in range(len(sig) - 2):
        if (
            sig[i].text == "@"
            and sig[i + 1].kind == "IDENT"
            and sig[i + 1].lower == "clobberbuiltins"
            and sig[i + 2].kind == "IDENT"
            and sig[i + 2].lower == "on"
        ):
            return True
    return False


def _collect_decl_list(sig: list[Token], i: int, names: set[str]) -> int:
    """Collect top-level comma-separated declaration names until statement EOI."""
    paren = square = curly = 0
    expect_name = True

    while i < len(sig):
        t = sig[i]
        s = t.text

        if expect_name and t.kind == "IDENT":
            names.add(t.lower)
            expect_name = False
            i += 1
            continue

        if s == "(":
            paren += 1
        elif s == ")":
            paren = max(0, paren - 1)
        elif s == "[":
            square += 1
        elif s == "]":
            square = max(0, square - 1)
        elif s == "{":
            curly += 1
        elif s == "}":
            if curly:
                curly -= 1
            else:
                return i
        elif s == "," and paren == square == curly == 0:
            expect_name = True
        elif s == "." and paren == square == curly == 0:
            return i + 1

        i += 1
    return i


def _collect_set_targets(sig: list[Token], i: int, names: set[str]) -> int:
    """Conservatively record root identifiers written by SET."""
    paren = square = curly = 0
    expect_target = True

    while i < len(sig):
        t = sig[i]
        s = t.text

        if expect_target and t.kind == "IDENT":
            names.add(t.lower)
            expect_target = False

        if s == "(":
            paren += 1
        elif s == ")":
            paren = max(0, paren - 1)
        elif s == "[":
            square += 1
        elif s == "]":
            square = max(0, square - 1)
        elif s == "{":
            curly += 1
        elif s == "}":
            if curly:
                curly -= 1
            else:
                return i
        elif s == "," and paren == square == curly == 0:
            expect_target = True
        elif s == "." and paren == square == curly == 0:
            return i + 1

        i += 1
    return i


def collect_user_names(sig: list[Token]) -> set[str]:
    """Conservative whole-file shadowing guard.

    If a possibly conflicting name is declared/written anywhere in the file,
    automatic alias substitution involving that name is skipped everywhere.
    This intentionally sacrifices some substitutions for safety.
    """
    names: set[str] = set()
    i = 0

    while i < len(sig):
        t = sig[i]
        if t.kind != "IDENT":
            i += 1
            continue

        word = t.lower

        if word == "function":
            if i + 1 < len(sig) and sig[i + 1].kind == "IDENT":
                names.add(sig[i + 1].lower)
            i += 2
            continue

        if word == "for":
            if i + 1 < len(sig) and sig[i + 1].kind == "IDENT":
                names.add(sig[i + 1].lower)
            i += 2
            continue

        if word == "lock":
            if i + 1 < len(sig) and sig[i + 1].kind == "IDENT":
                names.add(sig[i + 1].lower)
            i += 2
            continue

        if word == "parameter":
            i = _collect_decl_list(sig, i + 1, names)
            continue

        if word in {"local", "global", "declare"}:
            j = i + 1
            if word == "declare" and j < len(sig) and sig[j].kind == "IDENT" and sig[j].lower in {"local", "global"}:
                j += 1
            if j < len(sig) and sig[j].kind == "IDENT":
                head = sig[j].lower
                if head == "function":
                    if j + 1 < len(sig) and sig[j + 1].kind == "IDENT":
                        names.add(sig[j + 1].lower)
                    i = j + 2
                    continue
                if head == "parameter":
                    i = _collect_decl_list(sig, j + 1, names)
                    continue
                if head == "lock":
                    if j + 1 < len(sig) and sig[j + 1].kind == "IDENT":
                        names.add(sig[j + 1].lower)
                    i = j + 2
                    continue
            i = _collect_decl_list(sig, j, names)
            continue

        if word == "set":
            i = _collect_set_targets(sig, i + 1, names)
            continue

        i += 1

    return names


def comment_intersects(tokens: list[Token], start: int, end: int) -> bool:
    for t in tokens:
        if t.kind == "COMMENT" and t.start < end and t.end > start:
            return True
    return False


def find_function_alias_changes(
    sig: list[Token],
    user_names: set[str],
) -> list[Change]:
    out: list[Change] = []

    for i, t in enumerate(sig):
        if t.kind != "IDENT":
            continue
        short = FUNCTION_ALIASES.get(t.lower)
        if not short:
            continue

        prev = sig[i - 1] if i > 0 else None
        nxt = sig[i + 1] if i + 1 < len(sig) else None

        # Only standalone builtin calls.  Never touch a suffix method.
        if prev is not None and prev.text == ":":
            continue
        if nxt is None or nxt.text != "(":
            continue

        # Fail closed if either spelling is user-defined/written anywhere.
        if t.lower in user_names or short.lower() in user_names:
            continue

        out.append(Change(
            t.start, t.end, short,
            t.line, t.col, t.text,
            "builtin function alias",
        ))

    return out


def _chain_at(sig: list[Token], i: int) -> tuple[list[str], list[int]]:
    """Return IDENT(:IDENT)* names and token indexes from sig[i]."""
    names: list[str] = []
    indexes: list[int] = []

    if i >= len(sig) or sig[i].kind != "IDENT":
        return names, indexes

    names.append(sig[i].lower)
    indexes.append(i)
    j = i + 1

    while (
        j + 1 < len(sig)
        and sig[j].text == ":"
        and sig[j + 1].kind == "IDENT"
    ):
        names.append(sig[j + 1].lower)
        indexes.append(j + 1)
        j += 2

    return names, indexes


def find_bound_shortcut_changes(
    source: str,
    tokens: list[Token],
    sig: list[Token],
    user_names: set[str],
) -> list[Change]:
    out: list[Change] = []

    # If SHIP itself is user-defined/written, none of these rules are safe.
    if "ship" in user_names:
        return out

    for i, t in enumerate(sig):
        if t.kind != "IDENT" or t.lower != "ship":
            continue

        prev = sig[i - 1] if i > 0 else None
        if prev is not None and prev.text == ":":
            continue

        names, indexes = _chain_at(sig, i)
        if len(names) < 2:
            continue

        for pattern, replacement in BOUND_RULES:
            plen = len(pattern)
            if len(names) < plen or tuple(names[:plen]) != pattern:
                continue

            # Do not replace a bound shortcut with a name the file may shadow.
            root = replacement.split(":", 1)[0].lower()
            if root in user_names:
                continue

            end_tok = sig[indexes[plen - 1]]
            if comment_intersects(tokens, t.start, end_tok.end):
                continue

            old = source[t.start:end_tok.end]
            out.append(Change(
                t.start, end_tok.end, replacement,
                t.line, t.col, old,
                "bound expression shortcut",
            ))
            break

    return out


def apply_changes(source: str, changes: list[Change]) -> str:
    changes = sorted(changes, key=lambda c: (c.start, c.end))

    # Ensure no accidental overlap.  Longest bound rules already collapse
    # nested opportunities to one change.
    last_end = -1
    for c in changes:
        if c.start < last_end:
            raise NormalizeError(
                f"internal error: overlapping replacements near {c.line}:{c.col}"
            )
        last_end = c.end

    out: list[str] = []
    pos = 0
    for c in changes:
        out.append(source[pos:c.start])
        out.append(c.replacement)
        pos = c.end
    out.append(source[pos:])
    return "".join(out)


def normalize(source: str) -> tuple[str, list[Change], set[str]]:
    tokens = tokenize(source)
    sig = significant(tokens)

    if contains_clobberbuiltins_on(sig):
        raise NormalizeError(
            "@CLOBBERBUILTINS ON is present; refusing automatic builtin/bound alias rewriting"
        )

    user_names = collect_user_names(sig)

    changes = find_function_alias_changes(sig, user_names)
    changes += find_bound_shortcut_changes(source, tokens, sig, user_names)
    changes.sort(key=lambda c: c.start)

    return apply_changes(source, changes), changes, user_names


def print_maps() -> None:
    print(f"kOS {KOS_VERSION} direct builtin function aliases:")
    for long_name, short_name in sorted(FUNCTION_ALIASES.items()):
        print(f"  {long_name}() -> {short_name}()")

    print("\nBound-expression shortcuts:")
    for pattern, replacement in BOUND_RULES:
        print(f"  {':'.join(pattern)} -> {replacement}")


def main(argv: Optional[Sequence[str]] = None) -> int:
    ap = argparse.ArgumentParser(
        description=(
            f"Conservative kOS {KOS_VERSION} normalization pass for verified "
            "builtin function aliases and bound-expression shortcuts."
        )
    )
    ap.add_argument("input", nargs="?", type=Path)
    ap.add_argument("output", nargs="?", type=Path)
    ap.add_argument(
        "--list",
        action="store_true",
        help="list all built-in mappings and exit",
    )
    ap.add_argument(
        "--quiet",
        action="store_true",
        help="do not print each replacement",
    )
    ns = ap.parse_args(argv)

    if ns.list:
        print_maps()
        return 0

    if ns.input is None or ns.output is None:
        ap.error("input and output paths are required unless --list is used")

    src = ns.input.expanduser()
    dst = ns.output.expanduser()

    if not src.is_file():
        ap.error(f"input file does not exist or is not a file: {src}")
    if src.resolve() == dst.resolve(strict=False):
        ap.error("input and output paths resolve to the same file")
    if dst.exists():
        ap.error(f"output file already exists; refusing to overwrite: {dst}")

    try:
        source = src.read_text(encoding="utf-8")
        result, changes, _user_names = normalize(source)
    except (OSError, UnicodeError, NormalizeError) as exc:
        print(f"normalize_aliases.py: error: {exc}", file=sys.stderr)
        return 2

    if not ns.quiet:
        for c in changes:
            old = c.old.replace("\n", "\\n").replace("\r", "\\r")
            print(
                f"{src}:{c.line}:{c.col}: {old} -> {c.replacement} "
                f"[{c.reason}]",
                file=sys.stderr,
            )

    try:
        dst.parent.mkdir(parents=True, exist_ok=True)
        with dst.open("x", encoding="utf-8", newline="") as f:
            f.write(result)
    except FileExistsError:
        print(
            f"normalize_aliases.py: error: output file already exists; "
            f"refusing to overwrite: {dst}",
            file=sys.stderr,
        )
        return 2
    except OSError as exc:
        print(f"normalize_aliases.py: error: {exc}", file=sys.stderr)
        return 2

    before = len(source.encode("utf-8"))
    after = len(result.encode("utf-8"))
    print(
        f"{src}: {len(changes)} replacements, "
        f"{before} bytes -> {after} bytes -> {dst}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
