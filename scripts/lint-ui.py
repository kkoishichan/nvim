#!/usr/bin/env python3
"""Static UI rules for the configuration.

1. Colours come from user.core.palette: no 0xRRGGBB or "#RRGGBB" literal
   anywhere else under lua/.
2. Every vim.notify call names its source with a `title`.

Usage: lint-ui.py <config root>   (exit 1 with one line per violation)
"""
import re
import sys
from pathlib import Path

HEX = re.compile(r'0x[0-9a-fA-F]{6}\b|"#[0-9a-fA-F]{6}"')
HEX_ALLOWED = {"lua/user/core/palette.lua"}
NOTIFY = "vim.notify("


def strip_comments(text: str) -> str:
    """Blank out Lua line comments without changing offsets."""
    out = []
    for line in text.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("--"):
            out.append(" " * len(line))
        else:
            out.append(line)
    return "\n".join(out)


def call_span(text: str, start: int) -> int:
    """Index just past the closing paren of the call opened at text[start]."""
    depth = 0
    i = start
    quote = None
    while i < len(text):
        ch = text[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(text)


def split_args(body: str) -> list[str]:
    parts, depth, quote, current = [], 0, None, []
    for ch in body:
        if quote:
            current.append(ch)
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    if "".join(current).strip():
        parts.append("".join(current))
    return parts


def notify_violations(path: Path, text: str) -> list[str]:
    violations = []
    source = strip_comments(text)
    index = 0
    while True:
        index = source.find(NOTIFY, index)
        if index == -1:
            break
        open_paren = index + len(NOTIFY) - 1
        end = call_span(source, open_paren)
        args = split_args(source[open_paren + 1 : end - 1])
        line = source.count("\n", 0, index) + 1
        if len(args) < 3 or not re.search(r"\btitle\s*=", args[2]):
            violations.append(f"{path}:{line}: vim.notify without a title")
        index = end
    return violations


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    problems = []
    for path in sorted((root / "lua").rglob("*.lua")):
        relative = path.relative_to(root).as_posix()
        text = path.read_text(encoding="utf-8")
        if relative not in HEX_ALLOWED:
            for number, line in enumerate(strip_comments(text).split("\n"), 1):
                if HEX.search(line):
                    problems.append(f"{relative}:{number}: colour literal outside user.core.palette")
        problems.extend(notify_violations(Path(relative), text))
    for problem in problems:
        print(problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
