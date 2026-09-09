#!/usr/bin/env python3
"""Query a uiautomator dump for the Android UI test.

Three modes:
    contains    <dump.xml> <needle>...   exit 0 if any needle is on screen
    center      <dump.xml> <needle>...   print "x y" for the first match
    center_last <dump.xml> <needle>...   print "x y" for the last match

`center_last` exists because a label is not always unique: "Algebra" is both a
topic chip near the top of the ask-a-teacher sheet and the keyboard switch below
it, and matching the first one silently changes the topic instead of switching
keyboards.

Node text arrives XML-escaped — the tab bar's gear is `&#9881;`, not `⚙` — so
everything is unescaped before matching. A test that skips that silently stops
finding every icon in the app.
"""
import html
import re
import sys


def nodes(xml):
    for match in re.finditer(r"<node[^>]*>", xml):
        tag = match.group(0)
        text = html.unescape((re.search(r'text="([^"]*)"', tag) or [None, ""])[1])
        desc = html.unescape((re.search(r'content-desc="([^"]*)"', tag) or [None, ""])[1])
        bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
        yield text, desc, tuple(map(int, bounds.groups())) if bounds else None


def main():
    if len(sys.argv) < 4:
        print("usage: ui_query.py contains|center <dump.xml> <needle>...", file=sys.stderr)
        return 2
    mode, path, *needles = sys.argv[1:]
    needles = [n for n in needles if n]
    with open(path, encoding="utf-8", errors="replace") as handle:
        xml = handle.read()

    found = None
    for text, desc, bounds in nodes(xml):
        haystack = f"{text}\n{desc}"
        if not any(needle in haystack for needle in needles):
            continue
        if mode == "contains":
            return 0
        if not bounds:
            continue
        found = bounds
        if mode == "center":
            break

    if found:
        x1, y1, x2, y2 = found
        print((x1 + x2) // 2, (y1 + y2) // 2)
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
