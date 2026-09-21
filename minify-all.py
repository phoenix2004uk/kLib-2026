#!/usr/bin/env python3

import argparse
import subprocess
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(
        description="Recursively minify all .ks files in a directory."
    )
    parser.add_argument(
        "--accept-safe-lexicon-keys",
        action="store_true",
        help="Pass --accept-safe-lexicon-keys to minify.py.",
    )
    parser.add_argument("input", type=Path, help="Input directory.")
    parser.add_argument("output", type=Path, help="Output directory.")
    args = parser.parse_args()

    input_dir = args.input.resolve()
    output_dir = args.output.resolve()
    minifier = Path(__file__).resolve().with_name("minify.py")

    if not input_dir.is_dir():
        parser.error(f"Input directory does not exist: {input_dir}")

    if not minifier.is_file():
        parser.error(f"minify.py not found beside this script: {minifier}")

    if input_dir == output_dir:
        parser.error("Input and output directories must be different.")

    # Find files before creating anything. If output is nested inside input,
    # exclude that subtree from the input scan.
    source_files = sorted(
        path
        for path in input_dir.rglob("*.ks")
        if output_dir not in path.resolve().parents
    )

    targets = [
        (source, output_dir / source.relative_to(input_dir))
        for source in source_files
    ]

    # Fail before doing any work if any destination file already exists.
    existing = [target for _, target in targets if target.exists()]
    if existing:
        print("Error: output file(s) already exist; nothing was written:", file=sys.stderr)
        for path in existing:
            print(f"  {path}", file=sys.stderr)
        return 1

    output_dir.mkdir(parents=True, exist_ok=True)

    for source, target in targets:
        target.parent.mkdir(parents=True, exist_ok=True)

        command = [sys.executable, str(minifier)]
        if args.accept_safe_lexicon_keys:
            command.append("--accept-safe-lexicon-keys")
        command.extend((str(source), str(target)))

        print(f"{source.relative_to(input_dir)} -> {target.relative_to(output_dir)}")
        subprocess.run(command, check=True)

    print(f"Minified {len(targets)} file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())