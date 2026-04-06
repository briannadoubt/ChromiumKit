#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()

    contents = args.file.read_text()
    updated_contents, replacements = re.subn(
        r'^readonly CEF_VERSION="[^"]+"$',
        f'readonly CEF_VERSION="{args.version}"',
        contents,
        count=1,
        flags=re.MULTILINE,
    )

    if replacements != 1:
        print(f"error: Could not update CEF_VERSION in {args.file}", file=sys.stderr)
        return 1

    args.file.write_text(updated_contents)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
