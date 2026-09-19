#!/usr/bin/env python3
"""Biometric hard-block guard (owner-approved 2026-09-18).

Rule: no biometric embedding code for Spotter AI may be merged into `main` or
`production` without (a) a documented legal sign-off record and (b) an approving
review from a designated privacy admin who is not the PR author, on the PR's
latest commit. The feature must also stay OFF by default in production builds.

Engineering can build and test on non-protected branches with synthetic data.
This guard only runs on pull requests into the protected branches.

This is a guardrail against accidents and other contributors. In a repository
with a single maintainer it cannot stop that maintainer from editing the guard;
adding a second privacy admin and putting these files under CODEOWNERS closes
that gap (see docs/legal/README.md).
"""

import json
import os
import re
import subprocess
import sys
import urllib.request

# Paths whose NAME marks them as biometric code. docs/, .github/ and this
# directory are excluded so that documentation and the guard itself are free.
PATH_HINTS = ("spotter_biometrics", "biometric")
EXCLUDED_PREFIXES = ("docs/", ".github/", "tools/biometric_guard/")

# Code files whose ADDED lines are scanned. Specific on purpose: a bare
# "embedding" would flag every Flutter file (io.flutter.embedding.*).
CODE_EXTENSIONS = (
    ".dart", ".kt", ".java", ".swift", ".py", ".ts", ".tsx", ".js", ".jsx",
    ".c", ".cc", ".cpp", ".h", ".rs", ".go", ".sql", ".sh",
)
KEYWORDS = re.compile(
    r"face_?embedding|body_?embedding|rider_?embedding|embedding_enc|faceprint|"
    r"face_?recogni|physique|biometric_profile|spotter_?biometric",
    re.IGNORECASE,
)

# The OFF switch itself may name the flag without counting as biometric code,
# but nothing may turn it on.
FLAG_FILES = ("flutter_app/lib/core/feature_flags.dart", "flutter_app/test/feature_flags_test.dart")
FLAG_ON = re.compile(
    r"SPOTTER_BIOMETRICS\s*=\s*true|SPOTTER_BIOMETRICS'[^)]*defaultValue:\s*true",
    re.IGNORECASE,
)
FLAG_OK_PREFIXES = ("docs/", "tools/biometric_guard/", "flutter_app/test/")


SIGNOFF_PATH = "docs/legal/BIOMETRIC_SIGNOFF.md"
SIGNOFF_ID = re.compile(r"^Sign-off ID:\s*(?!<)(\S+)", re.MULTILINE)
SIGNOFF_STATUS = re.compile(r"^Status:\s*APPROVED\s*$", re.MULTILINE)


def is_excluded(path):
    return path.startswith(EXCLUDED_PREFIXES) or path in FLAG_FILES


def touches_biometrics(changed_files, added_lines_by_file):
    """Returns a list of human-readable reasons; empty means not touched."""
    reasons = []
    for path in changed_files:
        if is_excluded(path):
            continue
        lowered = path.lower()
        if any(h in lowered for h in PATH_HINTS):
            reasons.append("path: " + path)
            continue
        if path.lower().endswith(CODE_EXTENSIONS):
            for line in added_lines_by_file.get(path, []):
                if KEYWORDS.search(line):
                    reasons.append("keyword in " + path + ": " + line.strip()[:80])
                    break
    return reasons


def flag_enabled_files(added_lines_by_file):
    bad = []
    for path, lines in added_lines_by_file.items():
        # Docs and the guard describe the flag; a test may exercise it, except that
        # the flag's own definition must never default to true.
        if path.startswith(FLAG_OK_PREFIXES) and path != FLAG_FILES[1]:
            continue
        if any(FLAG_ON.search(l) for l in lines):
            bad.append(path)
    return bad


def signoff_ok(text):
    if not text:
        return False
    return bool(SIGNOFF_ID.search(text)) and bool(SIGNOFF_STATUS.search(text))


def approved_by_admin(reviews, admins, author, head_sha):
    """Latest review per user; needs an APPROVED review, on the head commit,
    by a listed admin who is not the PR author."""
    latest = {}
    for r in reviews:
        user = (r.get("user") or {}).get("login", "").lower()
        if r.get("state") in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED"):
            latest[user] = r
    for admin in admins:
        a = admin.lower()
        if a == author.lower():
            continue
        r = latest.get(a)
        if r and r.get("state") == "APPROVED" and r.get("commit_id") == head_sha:
            return True
    return False


def evaluate(changed_files, added_lines_by_file, signoff_text, reviews, admins, author, head_sha):
    """Returns (ok, messages)."""
    msgs = []
    bad_flag = flag_enabled_files(added_lines_by_file)
    if bad_flag:
        msgs.append("SPOTTER_BIOMETRICS=true must not be set in tracked files: " + ", ".join(bad_flag))
    reasons = touches_biometrics(changed_files, added_lines_by_file)
    if not reasons:
        if bad_flag:
            return False, msgs
        return True, ["No biometric code touched."]
    msgs.append("Biometric code detected (%d hit(s)): %s" % (len(reasons), "; ".join(reasons[:5])))
    ok = not bad_flag
    if not signoff_ok(signoff_text):
        ok = False
        msgs.append("Missing documented legal sign-off: %s must exist with a real "
                    "'Sign-off ID:' and 'Status: APPROVED'." % SIGNOFF_PATH)
    if not approved_by_admin(reviews, admins, author, head_sha):
        ok = False
        msgs.append("Needs an approving review on the latest commit from a privacy admin "
                    "(%s) who is not the PR author (%s)." % (", ".join(admins) or "none listed", author))
    return ok, msgs


# ---------------------------------------------------------------- CI plumbing
def _git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def _added_lines(base, head, files):
    out = {}
    for f in files:
        diff = _git("diff", "--unified=0", base, head, "--", f)
        out[f] = [l[1:] for l in diff.splitlines() if l.startswith("+") and not l.startswith("+++")]
    return out


def _api(path):
    req = urllib.request.Request(
        "https://api.github.com" + path,
        headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"],
                 "Accept": "application/vnd.github+json"},
    )
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def main():
    base = os.environ["BASE_SHA"]
    head = os.environ["HEAD_SHA"]
    base_ref = os.environ.get("BASE_REF", "main")
    pr = os.environ["PR_NUMBER"]
    author = os.environ["PR_AUTHOR"]
    repo = os.environ["GITHUB_REPOSITORY"]

    changed = [f for f in _git("diff", "--name-only", base, head).splitlines() if f]
    added = _added_lines(base, head, changed)

    # Admin list comes from the BASE branch so a PR cannot add itself.
    try:
        admins_text = _git("show", "%s:.github/privacy-admins.txt" % base)
    except subprocess.CalledProcessError:
        admins_text = ""
    admins = [l.strip().lstrip("@") for l in admins_text.splitlines()
              if l.strip() and not l.strip().startswith("#")]

    try:
        signoff = _git("show", "%s:%s" % (head, SIGNOFF_PATH))
    except subprocess.CalledProcessError:
        signoff = ""

    reviews = _api("/repos/%s/pulls/%s/reviews?per_page=100" % (repo, pr))
    ok, msgs = evaluate(changed, added, signoff, reviews, admins, author, head)
    print("Target branch:", base_ref)
    for m in msgs:
        print(("OK: " if ok else "BLOCKED: ") + m)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
