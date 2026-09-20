#!/usr/bin/env python3
"""Check that every UI string the app asks for can actually be translated.

Three things have to hold, and none of them are visible at a call site:

1.  No view calls `LocalizationSupport.localized` itself — copy comes from a
    view model (see teacher-minute/CLAUDE.md).
2.  Every source string resolves to a key that exists in the Remote Config
    template. A key that is missing falls back to the English source, so the
    string silently stays English in Hebrew.
3.  Every key is one Firebase will accept. `generatedKey` drops words of two
    characters or fewer, so a string like "%@ %d" reduces to an empty key and
    "e.g. 123" to one starting with a digit. Remote Config rejects the whole
    template on either, and neither could resolve at runtime anyway.
4.  No two distinct source strings resolve to the same key. `generatedKey`
    reduces a string to three words, so collisions are easy to create by
    accident, and one published value then serves two unrelated strings.

Run from anywhere:

    python3 backend/Firebase/check-localization.py
"""

import collections
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "teacher-minute", "Sources", "TeacherMinute")
RC = os.path.join(ROOT, "backend", "Firebase", "remote_config_tim.json")
SERVICE = os.path.join(SRC, "Services", "Localization", "RemoteConfigLocalizationService.swift")

# `AppDialogAction.dismissFallback` is the only string in Views/ that is not
# screen copy: it is the guard that keeps a dialog dismissable when a caller
# passes no actions, and it lives on a value type rather than on a View.
VIEW_EXEMPTIONS = {"Views/AppDialog.swift"}

# Remote Config rejects the deploy if any parameter key falls outside this.
VALID_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,255}$")

ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\", "0": "\0"}


def read_literal(text, i):
    """Read the Swift string literal starting at text[i]. -> (value, next index).

    Returns (None, None) for anything that is not a plain literal, such as one
    carrying string interpolation.
    """
    if i >= len(text) or text[i] != '"':
        return None, None
    i += 1
    out = []
    while i < len(text):
        c = text[i]
        if c == "\\":
            if i + 1 >= len(text):
                return None, None
            nxt = text[i + 1]
            if nxt == "u" and text[i + 2:i + 3] == "{":
                end = text.index("}", i + 3)
                out.append(chr(int(text[i + 3:end], 16)))
                i = end + 1
                continue
            if nxt == "(":            # interpolation
                return None, None
            out.append(ESCAPES.get(nxt, nxt))
            i += 2
            continue
        if c == '"':
            return "".join(out), i + 1
        if c == "\n":
            return None, None
        out.append(c)
        i += 1
    return None, None


def strip_comments(text):
    """Blank out comments while preserving every offset and newline."""
    out = list(text)
    i, n, in_block = 0, len(text), 0
    while i < n:
        if in_block:
            if text.startswith("*/", i):
                out[i] = out[i + 1] = " "
                i += 2
                in_block -= 1
                continue
            if text[i] != "\n":
                out[i] = " "
            i += 1
            continue
        if text[i] == '"':
            _, nxt = read_literal(text, i)
            if nxt is None:
                j = i + 1
                while j < n and text[j] != "\n":
                    if text[j] == "\\":
                        j += 2
                        continue
                    if text[j] == '"':
                        j += 1
                        break
                    j += 1
                i = j
                continue
            i = nxt
            continue
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
            for k in range(i, end):
                out[k] = " "
            i = end
            continue
        if text.startswith("/*", i):
            out[i] = out[i + 1] = " "
            i += 2
            in_block = 1
            continue
        i += 1
    return "".join(out)


def parse_dict(text, marker):
    """Parse a Swift `[String: String]` literal declared after `marker`."""
    start = text.index(marker)
    i = text.index("[", text.index("= [", start))
    depth, body_start = 0, i + 1
    while True:
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
            if depth == 0:
                break
        elif text[i] == '"':
            _, nxt = read_literal(text, i)
            if nxt:
                i = nxt - 1
        i += 1
    body, pairs, j = text[body_start:i], {}, 0
    while j < len(body):
        if body[j] != '"':
            j += 1
            continue
        key, after_key = read_literal(body, j)
        if key is None:
            j += 1
            continue
        sep = re.match(r"\s*:\s*", body[after_key:])
        if not sep:
            j = after_key
            continue
        v = after_key + sep.end()
        while v < len(body) and body[v] in " \n\t":
            v += 1
        value, after_value = read_literal(body, v)
        if value is not None:
            pairs[key] = value
            j = after_value
            continue
        j = after_key
    return pairs


SERVICE_TEXT = strip_comments(open(SERVICE, encoding="utf-8").read())
EXACT_KEYS = parse_dict(SERVICE_TEXT, "private static let exactKeys")


def generated_key(english):
    """Mirror of `LocalizationKey.generatedKey`."""
    normalized = "_" if english[:1].isdigit() else ""
    for ch in english.lower():
        normalized += ch if ch.isalnum() else " "
    words = []
    for part in normalized.split(" "):
        if len(part) <= 2:
            continue
        words.append(part)
        if len(words) == 3:
            break
    return "_".join(words)


def key_for(english):
    return EXACT_KEYS.get(english) or generated_key(english)


CALL = re.compile(r"LocalizationSupport\.localized\(\s*")


def scan():
    """-> [(relative path, line number, source string)] for every literal call."""
    found = []
    for dirpath, _, filenames in os.walk(SRC):
        for name in sorted(filenames):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, SRC)
            text = strip_comments(open(path, encoding="utf-8").read())
            for match in CALL.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                value, _ = read_literal(text, match.end())
                found.append((rel, line, value))
    return found


def main():
    calls = scan()
    params = json.load(open(RC, encoding="utf-8"))["parameters"]
    failures = []

    in_views = [(rel, line) for rel, line, _ in calls
                if rel.startswith("Views" + os.sep) and rel.replace(os.sep, "/") not in VIEW_EXEMPTIONS]
    if in_views:
        failures.append("Views must ask their view model for copy, not LocalizationSupport:")
        failures += [f"    {rel}:{line}" for rel, line in in_views]

    strings = sorted({s for _, _, s in calls if s is not None})

    missing = [s for s in strings if key_for(s) not in params]
    if missing:
        failures.append(f"{len(missing)} string(s) have no Remote Config parameter:")
        failures += [f"    {key_for(s)}\t{s!r}" for s in missing]

    invalid = sorted({key_for(s) for s in strings if not VALID_KEY.match(key_for(s))}
                     | {k for k in params if not VALID_KEY.match(k)})
    if invalid:
        failures.append(f"{len(invalid)} key(s) Remote Config will reject "
                        f"(need /[A-Za-z_][A-Za-z0-9_]*/) — add an entry to LocalizationKey.exactKeys:")
        for k in invalid:
            sources = [s for s in strings if key_for(s) == k]
            failures.append(f"    {k!r}\t{sources!r}")

    by_key = collections.defaultdict(list)
    for s in strings:
        by_key[key_for(s)].append(s)
    collisions = {k: v for k, v in by_key.items() if len(v) > 1}
    if collisions:
        failures.append(f"{len(collisions)} key collision(s) — add an entry to LocalizationKey.exactKeys:")
        for k, v in sorted(collisions.items()):
            failures.append(f"    {k}: " + " | ".join(repr(x) for x in v))

    duplicates = []

    def note_duplicates(pairs):
        counts = collections.Counter(k for k, _ in pairs)
        duplicates.extend(k for k, n in counts.items() if n > 1)
        return dict(pairs)

    json.load(open(RC, encoding="utf-8"), object_pairs_hook=note_duplicates)
    if duplicates:
        failures.append(f"{len(duplicates)} duplicate JSON key(s) in the template:")
        failures += [f"    {k}" for k in sorted(set(duplicates))]

    if failures:
        print("\n".join(failures))
        return 1

    dynamic = sum(1 for _, _, s in calls if s is None)
    print(f"OK — {len(strings)} distinct strings, all present in Remote Config, "
          f"no key collisions, no view-layer lookups.")
    print(f"     ({dynamic} calls translate a runtime value and cannot be checked statically.)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
