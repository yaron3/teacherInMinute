#!/usr/bin/env python3
"""Check that the RTDB rules still let the apps do what they do — and nothing more.

Write permission in Realtime Database *cascades*: a `.write` that grants access
at `questions/$qid` grants it everywhere beneath, and no rule further down can
take it back. That is why "only the teacher may clear the board" could not be
added as a rule on `board/strokes` alone — the grant had to move off the
question node and onto its children, which risks silently denying a write the
app depends on.

This walks the rules the way the database does — a write at P is allowed if a
`.write` at P or any ancestor is true — over every path the iOS and Android
clients write, and fails if any of them stops working or if a student regains
the ability to wipe the board.

Rule paths can match a segment by name and by `$wildcard` at the same time, and
the two are not equally specific. Rather than depend on which one the database
prefers, every path is resolved under both readings and the answers have to
agree.

It is a reading of the rules file, not the database: it does not replace the
emulator, and a new client write path has to be added to CASES by hand.

Run from anywhere:

    python3 backend/Firebase/check-database-rules.py
"""

import json
import os
import re
import sys

RULES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "database.rules.json")

TEACHER, STUDENT, STRANGER = "teacher-uid", "student-uid", "stranger-uid"

# A question names its two people under either spelling depending on who wrote
# the node, so both have to behave the same.
QUESTION_SHAPES = [
    {"teacherId": TEACHER, "studentId": STUDENT},
    {"teacherUid": TEACHER, "studentUid": STUDENT},
]

# Every path the clients write under a question, from ChatSessionService.swift,
# AndroidChatManager.kt and AndroidBoardImageSaver.kt.
#
#   (path, is_delete, teacher may, student may)
CASES = [
    ("questions/q1/messages/m1",              False, True, True),   # chat, board images
    ("questions/q1/board/strokes/s1",         False, True, True),   # drawing
    ("questions/q1/board/strokes",            True,  True, False),  # clearing the board
    ("questions/q1/board/strokes/s1",         True,  True, False),  # clearing it one stroke at a time
    ("questions/q1/board/viewports/teacher",  False, True, True),   # what each side is looking at
    ("questions/q1/chatPaused/teacher",       False, True, True),
    ("questions/q1/mediaPending/student",     False, True, True),
    ("questions/q1/conversationType",         False, True, True),   # text / audio / video
    ("questions/q1/status",                   False, True, True),   # accepting
    ("questions/q1/acceptedAt",               False, True, True),
    ("questions/q1/teacherId",                False, True, True),
    ("questions/q1/text",                     False, True, True),   # appending a formula
    ("questions/q1/questionText",             False, True, True),
]


def evaluate(expression, question, uid, bindings, is_delete):
    """Evaluate one `.write` expression. Only the forms this file uses."""
    expr = expression
    expr = re.sub(
        r"root\.child\('questions'\)\.child\(\$qid\)\.child\('(\w+)'\)\.val\(\)",
        lambda m: repr(question.get(m.group(1))),
        expr,
    )
    expr = re.sub(
        r"data\.child\('(\w+)'\)\.val\(\)",
        lambda m: repr(question.get(m.group(1))),
        expr,
    )
    expr = expr.replace("newData.exists()", repr(not is_delete))
    expr = expr.replace("auth != null", "True").replace("auth.uid", repr(uid))
    for name, value in bindings.items():
        expr = expr.replace(name, repr(value))
    expr = expr.replace("&&", " and ").replace("||", " or ").replace("!=", " != ")
    expr = re.sub(r"\bnull\b", "None", expr)
    return bool(eval(expr, {"__builtins__": {}}, {}))  # noqa: S307 — our own rules file


def allowed(rules, path, question, uid, is_delete, named_wins):
    """Does any `.write` on this path or an ancestor grant the write?"""
    frontier = [(rules, {})]
    for segment in path.split("/"):
        following = []
        for node, bindings in frontier:
            named = node.get(segment)
            if isinstance(named, dict):
                following.append((named, bindings))
                if named_wins:
                    continue
            for key, child in node.items():
                if key.startswith("$") and key != segment and isinstance(child, dict):
                    following.append((child, dict(bindings, **{key: segment})))
        frontier = following
        for node, bindings in frontier:
            rule = node.get(".write")
            if isinstance(rule, str) and evaluate(rule, question, uid, bindings, is_delete):
                return True
    return False


def main():
    rules = json.load(open(RULES_PATH, encoding="utf-8"))["rules"]
    failures = []

    for shape in QUESTION_SHAPES:
        for named_wins in (True, False):
            for path, is_delete, teacher_may, student_may in CASES:
                want = {TEACHER: teacher_may, STUDENT: student_may, STRANGER: False}
                for uid, expected in want.items():
                    got = allowed(rules, path, shape, uid, is_delete, named_wins)
                    if got != expected:
                        failures.append(
                            "%s %s by %s: expected %s, rules say %s (%s, %s)"
                            % (
                                "delete" if is_delete else "write",
                                path,
                                uid,
                                expected,
                                got,
                                "+".join(shape),
                                "named wins" if named_wins else "wildcards also apply",
                            )
                        )

    if failures:
        print("%d rule check(s) failed:" % len(failures))
        for failure in failures:
            print("    " + failure)
        return 1

    print("%d write path(s) behave as expected, under both rule-matching readings."
          % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
