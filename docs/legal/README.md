# Biometric (Spotter AI) legal gate

**Owner decision, 2026-09-18 (hard block):** no biometric embedding code for
Spotter AI may be merged to the production branch without documented legal
sign-off. Engineering may build the logic and run test environments with
**synthetic data**. Live facial/physique embedding of consumer data requires a
formal privacy review first.

This is a requirements and process note, not legal advice.

## What is enforced today

| Control | Where | Effect |
|---|---|---|
| Feature default OFF | `flutter_app/lib/core/feature_flags.dart`, `flutter_app/test/feature_flags_test.dart` | `kSpotterBiometricsEnabled` is false unless compiled in; a test fails if the default changes |
| `biometric-guard` check | `.github/workflows/biometric-guard.yml`, `tools/biometric_guard/` | On every PR into `main` or `production`: passes if no biometric code is touched; otherwise requires the sign-off record below **and** an approving review from a privacy admin (not the PR author) on the latest commit. Also blocks setting `SPOTTER_BIOMETRICS=true` or changing its default to true |
| Required check and code-owner review | Repository ruleset "biometric-hard-block" on `main` and `production` | The guard must pass before merging; changes under CODEOWNERS paths need the owner's review |
| Code owners | `.github/CODEOWNERS`, `.github/privacy-admins.txt` | Names the privacy admin |

Work on biometric code happens on **non-protected branches** (for example
`spotter-dev`) with synthetic data only. The guard and ruleset apply when that
work is proposed for `main` or `production`.

## The sign-off record

Merging requires `docs/legal/BIOMETRIC_SIGNOFF.md` with a real `Sign-off ID:`
and `Status: APPROVED` (see `BIOMETRIC_SIGNOFF.template.md`). **No such record
exists. Nothing here is a sign-off.** The template's placeholder values do not
satisfy the guard.

## Synthetic test data

Test environments use only generated or synthetic imagery, listed in
`docs/legal/synthetic-data-manifest.md` (source, generator, licence). No real
consumer or staff images without documented consent.

## Known limits (be honest about them)

- This repository is a **single-maintainer** repo on a personal account, so a
  team handle (for example `@Binnacle-Privacy`) is not possible, and the PR
  author cannot approve their own PR. Add a second person with write access to
  `.github/privacy-admins.txt` before biometric code can merge.
- The guard and workflow files are not code-owned, so the sole maintainer could
  edit the guard in the same PR. Put them under CODEOWNERS once a second
  privacy admin exists.
- Detection is by file name and specific keywords in added code lines, not by
  understanding the code. It is a guardrail, not a proof.
- The check reads reviews when it runs; after an approval, re-run it.
