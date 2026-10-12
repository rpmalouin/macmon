#!/usr/bin/env python3
"""Production lines of the Rust sources, tests excluded.

Usage: scripts/loc.py [REF]

Counts library (src/*.rs), app (src/app/*.rs), tui (src/app/tui/*.rs) and the C ABI
(ffi/src/*.rs) in the working tree.
With REF (e.g. origin/main), also counts each part at that git ref and prints the difference.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# part -> (folder, source suffix, recursive)
PARTS = {
  "library": ("src", ".rs", False),
  "app": ("src/app", ".rs", False),
  "tui": ("src/app/tui", ".rs", False),
  "ffi": ("ffi/src", ".rs", False),
  "macapp": ("macos/Sources", ".swift", True),
}
CFG_TEST_RE = re.compile(r"\s*#\[cfg\(test\)\]")
# String and char literals and line comments: braces in them don't change the depth.
NOISE_RE = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])\'|//.*')


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)


def prod(text: str) -> int:
    """Lines until `#[cfg(test)] mod tests`, without other `#[cfg(test)]` items."""
    n, skip, depth = 0, False, 0
    for line in text.splitlines():
        if CFG_TEST_RE.match(line):
            skip, depth = True, 0
        elif skip and line.startswith("mod tests"):
            break
        elif skip:  # the item under the attribute: one line ending in `;` or balanced braces
            code = NOISE_RE.sub("", line).rstrip()
            depth += code.count("{") - code.count("}")
            skip = depth > 0 or not code.endswith((";", "}"))
        else:
            n += 1
    return n


def count(ref: str | None, folder: str, suffix: str, recursive: bool) -> int:
    if ref is None:
        pattern = f"**/*{suffix}" if recursive else f"*{suffix}"
        return sum(prod(x.read_text()) for x in (ROOT / folder).glob(pattern))

    files = git("ls-tree", "--name-only", ref, f"{folder}/").stdout.splitlines()
    return sum(prod(git("show", f"{ref}:{x}").stdout) for x in files if x.endswith(suffix))


def main():
    ref = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None
    if ref and git("rev-parse", "--verify", "--quiet", f"{ref}^{{tree}}").returncode:
        sys.exit(f"unknown ref: {ref}")

    rows = [
        (
            name,
            count(None, folder, suffix, recursive),
            count(ref, folder, suffix, recursive) if ref else 0,
        )
        for name, (folder, suffix, recursive) in PARTS.items()
    ]
    rows.append(("total", sum(x[1] for x in rows), sum(x[2] for x in rows)))
    print(f"{'part':<8} {'now':>6}" + (f" {ref:>12} {'diff':>6}" if ref else ""))
    for name, now, base in rows:
        print(f"{name:<8} {now:>6}" + (f" {base:>12} {now - base:>+6}" if ref else ""))


if __name__ == "__main__":
    main()
