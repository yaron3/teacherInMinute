#!/usr/bin/env python3
"""Audits app localization against the Remote Config template.

Replicates LocalizationKey.key(for:) from RemoteConfigLocalizationService.swift
(exactKeys overrides plus the generated three-word key) so it reports exactly
what the app will look up at runtime.

Run from the repo root:
  python3 backend/Firebase/localization-keys.py summary   # counts + key collisions
  python3 backend/Firebase/localization-keys.py missing   # one JSON line per gap

A collision means two different English strings resolve to one key, so one
translation serves both — fix by adding an exactKeys override.
"""
import io, re, json, sys, collections, pathlib

SRC = pathlib.Path("teacher-minute/Sources/TeacherMinute")
RC = pathlib.Path("backend/Firebase/remote_config_tim.json")

# --- replicate LocalizationKey ------------------------------------------------
swift = io.open(SRC / "Services/Localization/RemoteConfigLocalizationService.swift", encoding="utf-8").read()
block = swift.split("private static let exactKeys: [String: String] = [", 1)[1].split("\n    ]", 1)[0]
EXACT_RAW = []
for m in re.finditer(r'^\s*"((?:[^"\\]|\\.)*)"\s*:\s*"([^"]+)"\s*,?\s*$', block, re.M):
    EXACT_RAW.append((m.group(1), m.group(2)))

def unescape(raw):
    # Only the escapes Swift sources here actually use; leave everything else
    # (Hebrew, "\u05d0"-style text, stray backslashes) untouched.
    out, i = [], 0
    while i < len(raw):
        if raw[i] == "\\" and i + 1 < len(raw):
            nxt = raw[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt, "\\" + nxt))
            i += 2
        else:
            out.append(raw[i]); i += 1
    return "".join(out)

EXACT = {unescape(a): b for a, b in EXACT_RAW}

def generated(english):
    normalized = "".join(c if c.isalnum() else " " for c in english.lower())
    words = [w for w in normalized.split() if len(w) > 2][:3]
    return "_".join(words)

def key_for(english):
    return EXACT.get(english) or generated(english)

# --- collect every localized string in the app --------------------------------
LIT = re.compile(r'LocalizationSupport\.localized\(\s*"((?:[^"\\]|\\.)*)"\s*\)')
strings = collections.defaultdict(set)   # english -> files
for path in SRC.rglob("*.swift"):
    text = io.open(path, encoding="utf-8").read()
    for m in LIT.finditer(text):
        raw = m.group(1)
        if "\\(" in raw:
            continue  # interpolated; not a stable key
        english = unescape(raw)
        strings[english].add(str(path.relative_to(SRC)))

params = json.load(open(RC))["parameters"]

# --- report -------------------------------------------------------------------
by_key = collections.defaultdict(list)
for english in strings:
    by_key[key_for(english)].append(english)

mode = sys.argv[1] if len(sys.argv) > 1 else "summary"
if mode == "summary":
    missing = {e: k for e, k in ((e, key_for(e)) for e in strings) if k not in params}
    collisions = {k: v for k, v in by_key.items() if len(v) > 1}
    print(f"localized strings: {len(strings)}   missing from Remote Config: {len(missing)}")
    print(f"key collisions (two strings sharing one key): {len(collisions)}")
    for k, v in sorted(collisions.items()):
        print("  COLLISION", k, "->", v)
elif mode == "missing":
    for english in sorted(strings):
        k = key_for(english)
        if k not in params:
            print(json.dumps({"key": k, "en": english, "files": sorted(strings[english])}, ensure_ascii=False))
