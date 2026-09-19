# Biometric (Spotter AI) legal gate

**Owner decision, 2026-09-18 (hard block):** no biometric embedding code for
Spotter AI may be merged to the production branch without documented legal
sign-off. Engineering may build the logic and run test environments with
**synthetic data**. Live facial/physique embedding of consumer data requires a
formal privacy review first.

This is a requirements and process note, not legal advice.

## What is enforced today

These are four different mechanisms. Do not read one as implying another.

| Control | Where | Effect |
|---|---|---|
| **Required status check (ruleset)** | Repository ruleset "biometric-hard-block", active, on the default branch and `production` | A pull request is required (0 approving reviews are required; code-owner review is **not** required, `require_code_owner_review` is false) and the status check **`biometric-guard`** must pass before merging. Deletion and non-fast-forward pushes are blocked. There are no bypass actors. |
| **The guard itself** | `.github/workflows/biometric-guard.yml`, `tools/biometric_guard/` | Runs on every PR into `main` or `production` and reports the `biometric-guard` check. It passes if no biometric code is touched. If biometric code is touched it additionally requires the sign-off record below **and** an approving review, on the latest commit, from a privacy admin who is not the PR author. It also blocks setting `SPOTTER_BIOMETRICS=true` or changing its default to true. This approval requirement is enforced by `guard.py`, not by GitHub's review rules. |
| **Privacy admins (guard input)** | `.github/privacy-admins.txt` | The list `guard.py` reads, from the **base** branch, so a PR cannot appoint its own approver. Currently exactly one admin (`Bleebitz`). |
| **Code owners (informational)** | `.github/CODEOWNERS` | Names `@Bleebitz` for biometric paths, `docs/legal/` and `.github/privacy-admins.txt`. GitHub requests their review, but the ruleset does **not** enforce it. |

**Feature flag.** The default-OFF flag `SPOTTER_BIOMETRICS`
(`flutter_app/lib/core/feature_flags.dart` and its test) is **not on `main` yet**;
it currently exists only on the still-open PR #10 branch. Until it lands, the
guard's check that nothing sets the flag to true is the only related control.

**Bootstrap.** The `biometric-guard` workflow first landed on `main` in a
dedicated bootstrap change. Before that it existed only on PR #10's branch, so no
other pull request could report the check the ruleset requires. Nothing in the
ruleset was changed to make that work.

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
  author cannot approve their own PR. There is currently **one** privacy admin,
  so there is no independent approver. Add a second person with write access to
  `.github/privacy-admins.txt` before biometric code can merge (a future
  requirement, not something that exists today).
- The guard and workflow files are not code-owned, so the sole maintainer could
  edit the guard in the same PR. Put them under CODEOWNERS (and turn on
  code-owner review in the ruleset, which is a separate decision) once a second
  privacy admin exists.
- Detection is by file name and specific keywords in added code lines, not by
  understanding the code. It is a guardrail, not a proof.
- The check reads reviews when it runs; after an approval, re-run it.
