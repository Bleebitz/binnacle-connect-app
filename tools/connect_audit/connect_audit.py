#!/usr/bin/env python3
"""
Connect (Flutter/Dart) static policy audit.

The Dart equivalent of notebook_audit.py, scoped to the failure classes that
have actually occurred in this codebase:

  1. Role gate declared but not wired into sendCommand()      (v0.1.1 near-miss)
  2. A safety-disable command becomes reachable                (design invariant)
  3. A credential secret (bearer token) leaks into a log/print  (never happened,
     checked because the cost of it happening once is high)
  4. ListTile-in-colored-Container without a Material ancestor (v0.1.2, REAL —
     dart analyze was clean while this crashed at runtime)

SCOPE. This is regex/heuristic, not a real Dart AST parser — no such parser
is readily available in Python. It catches the specific shapes above. It does
NOT replace dart analyze, flutter test, or a human looking at a screen. It is
one more gate, run before those, not instead of them.

Usage:
    python3 connect_audit.py path/to/lib [--json]
Exit 1 if any CRITICAL or HIGH finding.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SEV = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "INFO": 3}


class Audit:
    def __init__(self, root: Path):
        self.root = root
        self.files = {p: p.read_text() for p in root.rglob("*.dart")}
        self.all_text = "\n".join(self.files.values())
        self.findings = []

    def add(self, sev, where, check, msg):
        self.findings.append({"severity": sev, "where": where, "check": check, "message": msg})

    # -- 1. role gate must be wired into sendCommand, not just declared -----
    def check_role_gate_wired(self):
        cc = next((p for p in self.files if p.name == "control_channel_service.dart"), None)
        if cc is None:
            self.add("HIGH", "search", "missing_file",
                     "control_channel_service.dart not found — cannot verify the "
                     "role gate exists at all")
            return
        src = self.files[cc]
        m = re.search(r"String sendCommand\([^)]*\)\s*\{(.*?)\n  \}", src, re.S)
        if not m:
            self.add("CRITICAL", cc.name, "sendcommand_not_found",
                     "could not locate the sendCommand() method body — "
                     "cannot verify anything inside it")
            return
        body = m.group(1)
        if "RolePolicy.can(" not in body:
            self.add("CRITICAL", cc.name, "role_gate_not_wired",
                     "sendCommand() exists but its body never calls "
                     "RolePolicy.can(). RolePolicy may be defined and referenced "
                     "elsewhere in the file without ever gating the one place "
                     "that actually sends a command — this is exactly the v0.1.1 "
                     "defect. A declared policy that isn't called enforces nothing.")
            return
        if "CommandRejected" not in body.split("RolePolicy.can(", 1)[1][:200]:
            self.add("HIGH", cc.name, "role_gate_no_rejection",
                     "RolePolicy.can() is called inside sendCommand() but no "
                     "CommandRejected is thrown near it — the check result may "
                     "be computed and discarded")

    # -- 2. safety-disable commands must stay unreachable --------------------
    def check_safety_omission(self):
        found_set = False
        for p, src in self.files.items():
            if re.search(r"kNoDisableCommands\s*=\s*\{", src):
                found_set = True
                block = re.search(r"kNoDisableCommands\s*=\s*\{([^}]*)\}", src, re.S)
                names = block.group(1) if block else ""
                for required in ("set_fall_detection", "set_mob_alert", "disable_safety"):
                    if required not in names:
                        self.add("CRITICAL", p.name, "safety_command_removed",
                                 f"'{required}' is missing from kNoDisableCommands — "
                                 f"a command that should not exist may now be sendable")
        if not found_set:
            self.add("CRITICAL", "search", "no_safety_set",
                     "kNoDisableCommands not found anywhere — the entire "
                     "safety-omission mechanism may have been deleted")
            return
        # A role gate must never be the ONLY thing standing between a caller
        # and a safety command — the omission check must run first and
        # unconditionally, independent of role.
        for p, src in self.files.items():
            m = re.search(r"String sendCommand\([^)]*\)\s*\{(.*?)\n  \}", src, re.S)
            if not m:
                continue
            body = m.group(1)
            if "kNoDisableCommands" not in body:
                continue
            order = body.find("kNoDisableCommands")
            role_pos = body.find("RolePolicy.can(")
            if role_pos != -1 and role_pos < order:
                self.add("HIGH", p.name, "safety_check_order",
                         "the role check runs BEFORE the safety-omission check "
                         "in sendCommand(). If these were ever merged into one "
                         "system, an owner role could end up bypassing the "
                         "omission check. Keep the safety check first and "
                         "unconditional.")

    # -- 3. bearer secret must never reach a log/print -----------------------
    def check_secret_not_logged(self):
        for p, src in self.files.items():
            for m in re.finditer(r"\b(print|debugPrint|log)\s*\(([^;]*)\)", src):
                arg = m.group(2)
                if "bearerToken" in arg or ".token" in arg:
                    self.add("CRITICAL", p.name, "secret_logged",
                             f"a log call appears to include a token/secret: "
                             f"{m.group(0)[:100]}")
        # toJsonSafe's actual returned map must not include the field.
        # Anchored on a real method DECLARATION (return type + name + '('),
        # not any text mention of "toJsonSafe" — a doc comment referencing
        # the method name by itself must not be mistaken for the method.
        # The body is extracted by brace-depth counting, not by searching
        # for a literal "};" substring — a Dart constructor immediately
        # above can close with "});" and derail a substring search into
        # completely unrelated code, which is what happened on first pass.
        decl_re = re.compile(r"\n\s*[\w<>,\s?]+\btoJsonSafe\(\)\s*(?:=>|\{)")
        for p, src in self.files.items():
            dm = decl_re.search(src)
            if not dm:
                continue
            brace_start = src.find("{", dm.end() - 1)
            if brace_start == -1:
                continue
            depth, i = 1, brace_start + 1
            while i < len(src) and depth > 0:
                if src[i] == "{":
                    depth += 1
                elif src[i] == "}":
                    depth -= 1
                i += 1
            body = src[brace_start:i]
            # Strip // line comments before checking — otherwise a comment
            # like "// bearerToken intentionally absent", which EXPLAINS the
            # exclusion, gets misread as the field being present. A bare
            # substring check can't tell "mentioned in a comment" apart from
            # "used as a real map key" — this is exactly what happened
            # against the real credential.dart on first pass.
            body_no_comments = re.sub(r"//[^\n]*", "", body)
            if "bearerToken" in body_no_comments:
                self.add("CRITICAL", p.name, "secret_in_safe_json",
                         "toJsonSafe() includes bearerToken — the method name "
                         "promises safety it doesn't provide")

    # -- 4. ListTile inside a colored Container needs a Material ancestor ---
    def check_listtile_material(self):
        """
        For every `Container(` whose decoration sets a `color:`, scan its
        OWN balanced argument span (up to its matching closing paren) — not
        a fixed-width lookahead — and check whether a ListTile appears
        inside that span with no Material between them. A fixed-width
        lookahead is wrong: it can pick up a sibling widget that comes after
        the Container closes, which is source-text proximity, not
        widget-tree nesting, and produced a real false positive on first
        pass (capture_screen.dart, where the ListTile in question is a
        sibling of an unrelated colored Container earlier in the file, not
        its child).
        """
        for p, src in self.files.items():
            for cm in re.finditer(r"\bContainer\(", src):
                start = cm.end()
                depth, i = 1, start
                while i < len(src) and depth > 0:
                    if src[i] == "(":
                        depth += 1
                    elif src[i] == ")":
                        depth -= 1
                    i += 1
                span = src[start:i - 1]  # exactly this Container's own arguments
                if "color:" not in span and "color :" not in span:
                    continue
                lt = span.find("ListTile(")
                if lt == -1:
                    continue
                if "Material(" not in span[:lt]:
                    line_no = src[:cm.start()].count("\n") + 1
                    self.add("HIGH", f"{p.name}:{line_no}", "listtile_no_material",
                             "a ListTile appears inside a colored Container's own "
                             "argument span with no Material widget between them. "
                             "This renders without a static-analysis error but "
                             "Flutter raises a hard assertion at runtime ('ListTile "
                             "background color or ink splashes may be invisible') — "
                             "this exact shape crashed device_list_screen.dart and "
                             "settings_screen.dart on 2026-09-14. Wrap the ListTile "
                             "in Material(type: MaterialType.transparency, ...).")

    # -- 5. TextPainter.paint() must receive a canvas argument ---------------
    def check_textpainter_paint(self):
        """The other real bug from the same compile pass: .paint(Offset) with
        no canvas argument. TextPainter.paint requires (Canvas, Offset).
        Uses a balanced-paren scan, not a naive regex — a naive [^)]* regex
        stops at the first ')' it sees, which is wrong the moment the single
        argument is itself a call like Offset(x, y) with its own parens."""
        for p, src in self.files.items():
            for m in re.finditer(r"(\w+)\.paint\(", src):
                start = m.end()  # just after the opening (
                depth = 1
                i = start
                while i < len(src) and depth > 0:
                    if src[i] == "(":
                        depth += 1
                    elif src[i] == ")":
                        depth -= 1
                    i += 1
                args = src[start:i - 1]
                # top-level comma count: depth-aware, so Offset(a, b)'s inner
                # comma doesn't get mistaken for a second top-level argument
                depth2, top_commas = 0, 0
                for ch in args:
                    if ch == "(":
                        depth2 += 1
                    elif ch == ")":
                        depth2 -= 1
                    elif ch == "," and depth2 == 0:
                        top_commas += 1
                if top_commas == 0 and args.strip() and \
                        ("Offset(" in args or " - Offset" in args or "offset" in args.lower()):
                    line_no = src[:m.start()].count("\n") + 1
                    self.add("CRITICAL", f"{p.name}:{line_no}", "textpainter_missing_canvas",
                             f".paint({args.strip()[:60]}...) has only one top-level "
                             f"argument and it looks like an Offset — TextPainter.paint "
                             f"requires (Canvas canvas, Offset offset). This exact bug "
                             f"shipped in gauge_painter.dart and would only be caught by "
                             f"dart analyze, not by eye.")

    def run(self):
        self.check_role_gate_wired()
        self.check_safety_omission()
        self.check_secret_not_logged()
        self.check_listtile_material()
        self.check_textpainter_paint()
        return self.findings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("lib_dir")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    root = Path(args.lib_dir)
    a = Audit(root)
    findings = sorted(a.run(), key=lambda f: SEV[f["severity"]])
    blocking = [f for f in findings if f["severity"] in ("CRITICAL", "HIGH")]
    status = "STATIC_AUDIT_BLOCKED" if blocking else "STATIC_AUDIT_PASSED_UNEXECUTED"

    if args.json:
        print(json.dumps({"root": str(root), "status": status, "findings": findings}, indent=1))
        return 1 if blocking else 0

    print(f"\n{'='*70}\nCONNECT STATIC POLICY AUDIT — {root}\n{'='*70}")
    if not findings:
        print("\nNo findings.")
    for sev in ("CRITICAL", "HIGH", "MEDIUM", "INFO"):
        rows = [f for f in findings if f["severity"] == sev]
        if rows:
            print(f"\n{sev} ({len(rows)})")
            for f in rows:
                print(f"  [{f['check']}] {f['where']}")
                print(f"      {f['message']}")
    print(f"\n{'='*70}\n{status}")
    if not blocking:
        print("Static heuristics only. Does not replace dart analyze, flutter "
              "test, or a human looking at a rendered screen.")
    return 1 if blocking else 0


if __name__ == "__main__":
    sys.exit(main())
