# Connect Community readability acceptance

Date: 2026-09-17. Work: BIN-49, child of BIN-32. Branch: connect-splash-v2-resilience. Review: https://github.com/Bleebitz/binnacle-connect-app/pull/9

## Scope and provenance

Continues Claude's uncommitted Community work over ecf2241 (the brighter logo). Retains the existing wave, responsive logo and startup behavior. No live Core integration or production release claim is made.

Community headers and tabs now have solid navy backing. Sessions/People use inset navy panels, leaving the wave visible around them. Primary labels are 16 px off-white; secondary content is 14 px light slate. People has a filled navy input, cyan focus border and teal Add button. Compete retains its four routes with larger titles/descriptions on opaque navy cards. Core mode retains its explanatory message on a panel.

Codex completion caught the remaining empty-Sessions text at 12.5 px in the shared empty-state widget. Community now opts into 16/14 px text and light-slate descriptions, with a scrollable empty state for constrained screens. Other consumers keep their existing defaults. New const suggestions were resolved; the audit script's unrelated local executable-bit difference was not included.

Palette calculation: slateLight (#9CACB9) on navyRaised (#12314A) is 5.76:1; offWhite (#EDF1F2) is 11.81:1. These are specific palette ratios, not a blanket accessibility certification.

## Automated verification

- Full demo suite after final code changes: 65 passed, 2 mode-specific tests skipped.
- Core-mode Community + live boundary checks before the final empty-state/const refinement: 2 passed, 7 demo-only tests skipped. Final rerun recorded below.
- dart analyze after final changes: 0 errors, 0 warnings, 53 info-level style findings.
- python -X utf8 tools/connect_audit/connect_audit.py flutter_app/lib: no findings. Windows default cp1252 fails reading existing Unicode source; explicit UTF-8 fixes the invocation without changing the audit.
- git diff --check: passed.
- Tests cover empty/populated Sessions, People addition through CrewRepository, typography/input treatment, Compete navigation, Core message, and 320x568 layout at 1.6 text scaling including the empty state.

## Phone evidence

Device: Samsung Galaxy S25 Ultra, SM-S938U / Android 16. Build 2006 was already installed when Codex resumed; package manager confirmed version 0.1.0 / code 2006. No uninstall, app-data clear, or signing change was performed.

Claude's preserved build-2006 screenshots:
- s25_community_crew_sessions.png (before final empty-state text refinement)
- s25_community_people.png
- s25_community_people_keyboard.png
- s25_community_compete.png

Codex independently opened Community > Crew > People on build 2006, entered Levi, tapped Add, dismissed the keyboard, and verified the resulting rider tile both in Android's UI hierarchy and visually in s25_community_people_added.png. This closes the missing screenshot from Claude's handoff. No FATAL EXCEPTION, AndroidRuntime, ANR in, or Unhandled Exception matches appeared in the running app's available process log. This is a bounded smoke check, not a long soak test.

CrewRepository is in-memory demo state; adding a rider proves the interaction, not persistence across process restarts or cloud synchronization.

## Release and remaining boundaries

Build 2006 release-mode APK SHA256: 25c0b3c338113e80f37bb8053ccdb6cabf584ce4476a114192f0e817c8d5c4d5. This was the earlier APK sent to Seth. The final build 2007 receipt is added below.

Release-mode APKs use the established debug signing configuration and are not production-signed. Previously documented native ML Kit 16KB alignment and real QR/Core pairing validation remain open; Community UI verification does not close them. See CONNECT_SPLASH_BRAND_ASSET_ACCEPTANCE.md for prior splash and logo evidence.

Master Work Register: new BIN-49 entry at 'Work Register'!A65:N65, created after confirming the row was blank and preserving neighboring row formatting. Record remains in progress until PR review/merge; no hardware or independent on-water gate is closed.

## Final build 2007 receipt

- flutter build apk --release --build-number=2007: passed, 111.3 MB.
- SHA256: 51e1e6aff709220108a0c8b5b5b2d2b607e00481f5f177852ce102e7780e3a17.
- adb install -r: Success. Package manager confirms version 0.1.0 / code 2007. Upgrade preserved application data; no uninstall or clear was used.
- Launched successfully, passed through the splash, navigated to Community. Final screenshot s25_community_sessions_final_2007.png visually confirms brighter 16/14 px empty-state text, with the wave visible around the panel. No matching fatal/ANR/unhandled-exception entries in the available current-process log.
- Final Core-mode Community + live boundary rerun: 2 passed, 8 demo-only tests skipped.
- CI is verified on the PR's final commit after push; its live status is authoritative. See PR #9 for the run link and result.
