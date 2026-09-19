import unittest

import guard

HEAD = "abc123"
GOOD_SIGNOFF = "Sign-off ID: LEGAL-2026-001\nStatus: APPROVED\n"
ADMIN_APPROVAL = [{"user": {"login": "Privacy-Admin"}, "state": "APPROVED", "commit_id": HEAD}]


def run(files, added=None, signoff="", reviews=None, admins=("privacy-admin",), author="dev"):
    return guard.evaluate(files, added or {}, signoff, reviews or [], list(admins), author, HEAD)


class GuardTests(unittest.TestCase):
    def test_unrelated_change_passes(self):
        ok, _ = run(["flutter_app/lib/ui/screens/library_screen.dart"],
                    {"flutter_app/lib/ui/screens/library_screen.dart": ["import 'package:flutter/material.dart';"]})
        self.assertTrue(ok)

    def test_flutter_embedding_import_is_not_a_false_positive(self):
        f = "flutter_app/android/app/src/main/kotlin/MainActivity.kt"
        ok, _ = run([f], {f: ["import io.flutter.embedding.android.FlutterActivity"]})
        self.assertTrue(ok)

    def test_docs_are_free(self):
        ok, _ = run(["docs/evidence/X.md"], {"docs/evidence/X.md": ["biometric_profiles embedding_enc physique"]})
        self.assertTrue(ok)

    def test_biometric_path_blocked_without_signoff_or_approval(self):
        ok, msgs = run(["flutter_app/lib/spotter_biometrics/embed.dart"])
        self.assertFalse(ok)
        self.assertTrue(any("sign-off" in m.lower() for m in msgs))

    def test_keyword_in_code_is_blocked(self):
        f = "cloud/worker/match.py"
        ok, _ = run([f], {f: ["vec = compute_face_embedding(img)"]})
        self.assertFalse(ok)

    def test_signoff_alone_is_not_enough(self):
        ok, _ = run(["a/spotter_biometrics/x.dart"], signoff=GOOD_SIGNOFF)
        self.assertFalse(ok)

    def test_approval_alone_is_not_enough(self):
        ok, _ = run(["a/spotter_biometrics/x.dart"], reviews=ADMIN_APPROVAL)
        self.assertFalse(ok)

    def test_both_present_passes(self):
        ok, _ = run(["a/spotter_biometrics/x.dart"], signoff=GOOD_SIGNOFF, reviews=ADMIN_APPROVAL)
        self.assertTrue(ok)

    def test_author_cannot_approve_own_pr(self):
        ok, _ = run(["a/spotter_biometrics/x.dart"], signoff=GOOD_SIGNOFF, reviews=ADMIN_APPROVAL,
                    author="privacy-admin")
        self.assertFalse(ok)

    def test_stale_approval_on_older_commit_is_rejected(self):
        stale = [{"user": {"login": "privacy-admin"}, "state": "APPROVED", "commit_id": "old"}]
        ok, _ = run(["a/spotter_biometrics/x.dart"], signoff=GOOD_SIGNOFF, reviews=stale)
        self.assertFalse(ok)

    def test_later_changes_requested_overrides_earlier_approval(self):
        reviews = ADMIN_APPROVAL + [{"user": {"login": "privacy-admin"}, "state": "CHANGES_REQUESTED",
                                     "commit_id": HEAD}]
        ok, _ = run(["a/spotter_biometrics/x.dart"], signoff=GOOD_SIGNOFF, reviews=reviews)
        self.assertFalse(ok)

    def test_template_placeholder_id_does_not_count(self):
        ok, _ = run(["a/spotter_biometrics/x.dart"], signoff="Sign-off ID: <fill in>\nStatus: APPROVED\n",
                    reviews=ADMIN_APPROVAL)
        self.assertFalse(ok)

    def test_production_flag_on_is_blocked_even_with_everything_else(self):
        f = "flutter_app/build.sh"
        ok, msgs = run([f, "a/spotter_biometrics/x.dart"], {f: ["flutter build --dart-define=SPOTTER_BIOMETRICS=true"]},
                       signoff=GOOD_SIGNOFF, reviews=ADMIN_APPROVAL)
        self.assertFalse(ok)
        self.assertTrue(any("SPOTTER_BIOMETRICS" in m for m in msgs))

    def test_flag_file_naming_the_flag_is_not_biometric_code(self):
        f = "flutter_app/lib/core/feature_flags.dart"
        ok, _ = run([f], {f: ["const bool k = bool.fromEnvironment('SPOTTER_BIOMETRICS', defaultValue: false);"]})
        self.assertTrue(ok)

    def test_flipping_the_flag_default_to_true_is_blocked(self):
        f = "flutter_app/lib/core/feature_flags.dart"
        ok, msgs = run([f], {f: ["const bool k = bool.fromEnvironment('SPOTTER_BIOMETRICS', defaultValue: true);"]})
        self.assertFalse(ok)
        self.assertTrue(any("SPOTTER_BIOMETRICS" in m for m in msgs))

    def test_flag_on_in_docs_is_allowed(self):
        f = "docs/legal/README.md"
        ok, _ = run([f], {f: ["Never pass SPOTTER_BIOMETRICS=true in production."]})
        self.assertTrue(ok)


if __name__ == "__main__":
    unittest.main()
