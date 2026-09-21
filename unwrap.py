#!/usr/bin/env python3
"""Readable KerboScript reformatter for minified kOS source.

Usage:
    python unwrap.py INPUT.ks OUTPUT.ks

The script deliberately performs the inverse of the *presentation* side of
minification, not symbol recovery:

* parses using the adjacent ``minify.py`` KerboScript parser;
* adds explicit braces around control-statement bodies;
* expands comma-packed SET statements to one SET per assignment;
* expands comma-packed LOCAL/GLOBAL/DECLARE statements to one declaration per
  variable;
* expands comma-packed PARAMETER statements to one parameter per statement;
* restores line breaks and tab indentation;
* preserves identifier names, string contents and numeric spellings from the
  input;
* reparses the generated output before writing it.

It does NOT attempt to recover original long variable/function names or infer
which manual structural optimisations were used.  Its purpose is to turn a
minified file into a readable guide for back-porting those changes into a
normalised source file.
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Iterator, Sequence


class UnwrapError(RuntimeError):
    pass


def load_minify_module():
    """Load minify.py from the same directory as this script."""
    path = Path(__file__).resolve().with_name("minify.py")
    if not path.is_file():
        raise UnwrapError(
            f"required parser not found: {path}\n"
            "Place unwrap.py beside the current minify.py."
        )
    spec = importlib.util.spec_from_file_location("kos_minify_for_unwrap", path)
    if spec is None or spec.loader is None:
        raise UnwrapError(f"unable to load parser module: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@dataclass(frozen=True)
class Atom:
    text: str
    kind: str = "TEXT"
    block: bool = False


# Token kinds for which using the original text is desirable.  Keywords are
# also left as-written; minified kOS normally already uses lowercase, and this
# avoids needlessly changing case in hand-minified input.
OPEN_TOKENS = {"(", "["}
CLOSE_TOKENS = {")", "]"}
NO_SPACE_BEFORE = {")", "]", ",", ":", ".", "#", "@"}
NO_SPACE_AFTER = {"(", "[", ":", "#"}
BINARY_OPERATORS = {
    "+", "-", "*", "/", "^", "=", "<>", "<", ">", "<=", ">=",
    "and", "or",
}
PREFIX_WORDS = {"not", "defined", "choose"}
TERNARY_WORDS = {"if", "else"}


class PrettyPrinter:
    def __init__(self, kos, indent: str = "\t"):
        self.kos = kos
        self.indent_text = indent

    def indent(self, level: int) -> str:
        return self.indent_text * level

    # ------------------------------------------------------------------
    # Public entry point
    # ------------------------------------------------------------------

    def render(self, tree) -> str:
        if tree.kind != "program":
            raise UnwrapError(f"expected program node, got {tree.kind!r}")
        lines: list[str] = []
        for stmt in tree.children:
            if isinstance(stmt, self.kos.Node):
                lines.extend(self.statement(stmt, 0))
        return "\n".join(lines).rstrip() + "\n"

    # ------------------------------------------------------------------
    # Statements
    # ------------------------------------------------------------------

    def statement(self, node, level: int) -> list[str]:
        k = node.kind
        if k == "empty":
            return []
        if k == "block":
            return self.explicit_block(node, level)
        if k == "set":
            return self.set_lines(node, level)
        if k == "var_decl":
            return self.var_decl_lines(node, level)
        if k == "parameter_decl":
            return self.parameter_lines(node, level)
        if k == "function_decl":
            return self.function_lines(node, level)
        if k == "lock_decl":
            return self.lock_lines(node, level)
        if k == "if":
            return self.if_lines(node, level)
        if k == "until":
            return self.control_lines("until", node.attrs["cond"], node.attrs["body"], level)
        if k == "for":
            header = (
                "for " + node.attrs["iterator"].text + " in "
                + self.expr(node.attrs["collection"], level)
            )
            return self.control_body(header, node.attrs["body"], level)
        if k == "on":
            header = "on " + self.expr(node.attrs["target"], level)
            return self.control_body(header, node.attrs["body"], level)
        if k == "when":
            header = "when " + self.expr(node.attrs["cond"], level) + " then"
            return self.control_body(header, node.attrs["body"], level)
        if k == "from":
            return self.from_lines(node, level)

        # All remaining statement forms preserve the parser's token order.
        text = self.inline_node(node, level).strip()
        return self.multiline_statement(text, level)

    def explicit_block(self, block, level: int) -> list[str]:
        lines = [self.indent(level) + "{"]
        for stmt in block.attrs.get("statements", []):
            lines.extend(self.statement(stmt, level + 1))
        lines.append(self.indent(level) + "}")
        return lines

    def block_contents(self, body, level: int) -> list[str]:
        if body.kind == "block":
            lines: list[str] = []
            for stmt in body.attrs.get("statements", []):
                lines.extend(self.statement(stmt, level))
            return lines
        return self.statement(body, level)

    def control_body(self, header: str, body, level: int) -> list[str]:
        lines = [self.indent(level) + header.rstrip() + " {"]
        lines.extend(self.block_contents(body, level + 1))
        lines.append(self.indent(level) + "}")
        return lines

    def control_lines(self, keyword: str, cond, body, level: int) -> list[str]:
        return self.control_body(f"{keyword} {self.expr(cond, level)}", body, level)

    def if_lines(self, node, level: int) -> list[str]:
        lines = self.control_body(
            "if " + self.expr(node.attrs["cond"], level),
            node.attrs["then"],
            level,
        )
        other = node.attrs.get("else")
        if other is not None:
            # Deliberately formal: even an `else if` is emitted as an explicit
            # ELSE block containing an IF block.  The file is a readable guide,
            # not an attempt to reproduce the author's preferred compact style.
            lines[-1] = self.indent(level) + "} else {"
            lines.extend(self.block_contents(other, level + 1))
            lines.append(self.indent(level) + "}")
        return lines

    def from_lines(self, node, level: int) -> list[str]:
        lines = [self.indent(level) + "from {"]
        lines.extend(self.block_contents(node.attrs["init"], level + 1))
        lines.append(self.indent(level) + "}")
        lines.append(self.indent(level) + "until " + self.expr(node.attrs["cond"], level))
        lines.append(self.indent(level) + "step {")
        lines.extend(self.block_contents(node.attrs["step"], level + 1))
        lines.append(self.indent(level) + "}")
        lines.append(self.indent(level) + "do {")
        lines.extend(self.block_contents(node.attrs["body"], level + 1))
        lines.append(self.indent(level) + "}")
        return lines

    def set_lines(self, node, level: int) -> list[str]:
        lines = []
        for target, _to, value in node.attrs["pairs"]:
            text = f"set {self.expr(target, level)} to {self.expr(value, level)}."
            lines.extend(self.multiline_statement(text, level))
        return lines

    def var_decl_lines(self, node, level: int) -> list[str]:
        modifier = node.attrs.get("modifier")
        head = modifier if modifier in {"local", "global"} else "declare"
        lines = []
        for name, op, value in node.attrs["decls"]:
            text = f"{head} {name.text} {op.text.lower()} {self.expr(value, level)}."
            lines.extend(self.multiline_statement(text, level))
        return lines

    def parameter_lines(self, node, level: int) -> list[str]:
        modifier = node.attrs.get("modifier")
        head = ((modifier + " ") if modifier in {"local", "global"} else "") + "parameter"
        lines = []
        for name, op, default in node.attrs["params"]:
            text = f"{head} {name.text}"
            if op is not None:
                text += f" {op.text.lower()} {self.expr(default, level)}"
            text += "."
            lines.extend(self.multiline_statement(text, level))
        return lines

    def function_lines(self, node, level: int) -> list[str]:
        modifier = node.attrs.get("modifier")
        prefix = (modifier + " ") if modifier in {"local", "global"} else ""
        lines = [self.indent(level) + f"{prefix}function {node.attrs['name'].text} {{"]
        lines.extend(self.block_contents(node.attrs["body"], level + 1))
        lines.append(self.indent(level) + "}")
        return lines

    def lock_lines(self, node, level: int) -> list[str]:
        modifier = node.attrs.get("modifier")
        prefix = (modifier + " ") if modifier in {"local", "global"} else ""
        text = (
            f"{prefix}lock {node.attrs['name'].text} to "
            f"{self.expr(node.attrs['value'], level)}."
        )
        return self.multiline_statement(text, level)

    # ------------------------------------------------------------------
    # Expressions / generic statements
    # ------------------------------------------------------------------

    def expr(self, node, level: int) -> str:
        atoms = list(self.atoms(node, level))
        return self.join_atoms(atoms)

    def inline_node(self, node, level: int) -> str:
        return self.join_atoms(list(self.atoms(node, level)))

    def atoms(self, obj, level: int) -> Iterator[Atom]:
        if isinstance(obj, self.kos.Token):
            yield Atom(obj.text, obj.kind)
            return
        if not isinstance(obj, self.kos.Node):
            return

        if obj.kind == "block_expr":
            yield Atom(self.block_expression(obj, level), "BLOCK", True)
            return

        if obj.kind == "number":
            # Scientific notation is one numeric literal even though the kOS
            # parse tree stores mantissa / E / sign / exponent as terminals.
            # Keep it compact and preserve the source spelling.
            text = "".join(
                child.text for child in obj.children
                if isinstance(child, self.kos.Token)
            )
            yield Atom(text, "NUMBER")
            return

        if obj.kind == "unary":
            for index, child in enumerate(obj.children):
                if isinstance(child, self.kos.Token):
                    kind = (
                        "UNARY_PLUSMINUS"
                        if index == 0 and child.kind == "PLUSMINUS"
                        else child.kind
                    )
                    yield Atom(child.text, kind)
                elif isinstance(child, self.kos.Node):
                    yield from self.atoms(child, level)
            return

        # SET/declaration nodes do not store all semantic children in .children,
        # but they are never rendered here as expressions.  Everything that can
        # legally occur within an expression retains source-order children.
        for child in obj.children:
            if isinstance(child, (self.kos.Token, self.kos.Node)):
                yield from self.atoms(child, level)
            elif isinstance(child, list):
                for item in child:
                    if isinstance(item, (self.kos.Token, self.kos.Node)):
                        yield from self.atoms(item, level)

    def block_expression(self, node, level: int) -> str:
        lines = ["{"]
        for stmt in node.attrs.get("statements", []):
            lines.extend(self.statement(stmt, level + 1))
        lines.append(self.indent(level) + "}")
        return "\n".join(lines)

    def join_atoms(self, atoms: Sequence[Atom]) -> str:
        if not atoms:
            return ""
        out = ""
        prev: Atom | None = None
        for atom in atoms:
            if prev is None:
                out = atom.text
                prev = atom
                continue
            sep = self.separator(prev, atom)
            out += sep + atom.text
            prev = atom
        return out

    def separator(self, prev: Atom, cur: Atom) -> str:
        p, c = prev.text, cur.text

        # A formatted closure/block already includes its own internal line
        # indentation.  Treat it like an ordinary expression atom at its edges.
        if c in NO_SPACE_BEFORE:
            return ""
        if p in NO_SPACE_AFTER:
            return ""
        if c == "@" or p == "@":
            return ""
        if c == "(" and (prev.kind in {"IDENTIFIER", "FILEIDENT"} or p in {")", "]"}):
            return ""
        if c == "[" and (prev.kind in {"IDENTIFIER", "FILEIDENT"} or p in {")", "]"}):
            return ""
        if p == ",":
            return " "

        pl = p.lower()
        cl = c.lower()
        if prev.kind == "UNARY_PLUSMINUS":
            return ""
        if cur.kind == "UNARY_PLUSMINUS":
            if p in OPEN_TOKENS or p in {":", "#", ","}:
                return "" if p != "," else " "
            return " "
        if pl in BINARY_OPERATORS or cl in BINARY_OPERATORS:
            return " "
        if pl in PREFIX_WORDS:
            return " "
        if pl in TERNARY_WORDS or cl in TERNARY_WORDS:
            return " "

        # Put a space between word-like tokens/literals by default.  Punctuation
        # cases not covered above remain compact.
        if self.wordlike(prev) and self.wordlike(cur):
            return " "
        if prev.block or cur.block:
            return " "
        return ""

    @staticmethod
    def wordlike(atom: Atom) -> bool:
        if atom.block:
            return False
        if atom.kind in {"IDENTIFIER", "FILEIDENT", "INTEGER", "DOUBLE", "NUMBER", "STRING", "TRUEFALSE"}:
            return True
        return bool(atom.text) and (atom.text[0].isalnum() or atom.text[0] == "_")


    def multiline_statement(self, text: str, level: int) -> list[str]:
        """Indent a possibly multiline expression statement cleanly."""
        raw = text.splitlines() or [""]
        if len(raw) == 1:
            return [self.indent(level) + raw[0]]

        lines = [self.indent(level) + raw[0]]
        # Block-expression continuation lines are already indented absolutely
        # for this statement level by block_expression().
        lines.extend(raw[1:])
        return lines


def unwrap_source(source: str, kos) -> str:
    tree = kos.parse_source(source)
    output = PrettyPrinter(kos).render(tree)
    # Syntax sanity check using exactly the same parser model as minify.py.
    kos.parse_source(output)
    return output


def parse_args(argv: Sequence[str] | None = None):
    p = argparse.ArgumentParser(
        description=(
            "Expand minified KerboScript into a deliberately formal, readable "
            "structure using the parser from adjacent minify.py."
        )
    )
    p.add_argument("input", type=Path, help="minified .ks input file")
    p.add_argument("output", type=Path, help="new readable .ks output file")
    return p.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    src_path: Path = args.input
    out_path: Path = args.output

    try:
        if src_path.resolve() == out_path.resolve():
            raise UnwrapError("input and output paths must be different")
        if not src_path.is_file():
            raise UnwrapError(f"input file does not exist: {src_path}")
        if out_path.exists():
            raise UnwrapError(f"refusing to overwrite existing output file: {out_path}")
        if not out_path.parent.exists():
            raise UnwrapError(f"output directory does not exist: {out_path.parent}")

        kos = load_minify_module()
        source = src_path.read_text(encoding="utf-8-sig")
        output = unwrap_source(source, kos)

        # Exclusive creation preserves the same no-overwrite guarantee as the
        # minifier even if another process creates the file after our check.
        with out_path.open("x", encoding="utf-8", newline="\n") as f:
            f.write(output)
        return 0
    except (UnwrapError, OSError) as exc:
        print(f"unwrap.py: error: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:
        # MinifyError intentionally comes through here without importing its
        # class name, keeping this script loosely coupled to minify.py internals.
        print(f"unwrap.py: parse/format error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
