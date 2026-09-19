> **SUPERSEDED ARCHITECTURE — RETAINED FOR DESIGN HISTORY**
>
> This document, **`CORE_USER_ACCOUNT_API_PROPOSAL.md` v2.5**, is retained as historical architecture evidence and must not be deleted or rewritten to reflect later decisions.
>
> As of **2026-09-19**, its controlling architecture has been superseded by:
>
> `docs/architecture/BINNACLE_IDENTITY_SESSION_MEDIA_ARCHITECTURE_v3.md`
>
> The v3 architecture incorporates and replaces the controlling identity, device, Vision ownership, Ride Session, Crew, Active Rider, media, entitlement, privacy/takedown, Spotter recognition, recovery, and provider decisions previously contained here.
>
> Important superseded v2.5 assumptions include, but are not limited to:
>
> - “Rider Account” as the universal human-account model; v3 uses a **Global Binnacle Account** with an optional Rider Profile.
> - permanent/per-boat Crew identity concepts; v3 uses **temporary Ride Session authorization**.
> - lack of a distinct Active Rider / Rider Run model; v3 separates Crew membership from who is currently riding.
> - automatic `unit_owner_master` personal Library pointers to every clip.
> - ordinary Vision-owner `delete-for-all` authority over already-distributed rider media.
> - narrower Rider Identity Assertion terminology; v3 defines a broader **Binnacle Identity Assertion (BIA)**.
> - incomplete session-recovery behavior; v3 defines reconnection and a **60-minute Vision session-recovery window**.
> - optional wording around Guest Claim Codes; v3 requires the approved **two-form local/remote Claim Code architecture with a 30-day expiration**.
> - older AWS live-stack references; **AWS IVS and AWS MediaLive are deprecated** and Cloudflare Stream is the controlling live pipeline.
>
> Security, token, offline-operation, hardware-transfer, Cloudflare R2/Stream, Supabase Auth, and other technical material in this document may still provide useful historical context where it does not conflict with v3.
>
> **Do not implement from this file where v3 differs.**
>
> Historical revision notes and prior owner decisions below remain intentionally unchanged.

# Core-side User Account API — Proposal (not yet implemented)

**Status: proposal only.** Nothing in this document is built, deployed, or
wired into the Flutter client. It exists so the Core team has a concrete
contract to review/build against, and so the Flutter client work has
something real to implement against once that contract exists — rather
than the client fabricating request/response shapes for a server that
doesn't exist.

## Why this document exists

A splash-screen refinement request asked for the login system described
in a follow-up ("full login system", with biometric as an alternative to
it, and outcomes like "Valid Session Found → main app" / "Expired →
Login/Connect Gateway"). Today, `binnacle-connect-app` (the Flutter
client) has **no user-account concept at all** — only device pairing:

- `PairingService` generates an EC keypair + CSR on-device, pairs to a
  specific boat's Core unit via a QR-code-scanned pairing code, and
  persists the resulting device credential in Keychain/Keystore
  (`flutter_secure_storage`).
- `ControlChannelService` opens an authenticated WSS control channel to
  that same Core using the paired device credential — there is no
  separate login step, and no notion of a user identity distinct from
  "this device is paired to this boat."

A real login system (user accounts, sessions, biometric-gated unlock)
requires a **new API on Core** that doesn't exist yet. This document
proposes that API's shape. It does not modify the existing pairing flow,
which continues to answer "is this device authorized to talk to this
boat's Core" — a real login system would answer a different, additive
question: "which human, with which account, is currently using this
already-paired device."

## Proposed scope

1. Core gains real account storage (signup, credential verification,
   session-token issuance) — out of scope for the Flutter repo; owned by
   whoever builds Core.
2. The Flutter client gets a login screen that calls this API, stores the
   resulting session token in the same secure-storage mechanism already
   used for pairing credentials, and gates biometric re-entry
   (`local_auth`) on top of an already-valid stored session — never as a
   replacement for server-side verification.

## Proposed endpoints (Core, over the existing authenticated transport)

All requests below travel over the same transport class already used for
pairing (`HttpPairingTransport`-style HTTPS, or a new `webrtc_offer`-style
control-channel frame — Core's team should pick whichever fits its
existing infra) — never a new unauthenticated channel.

### `POST /accounts` — create account
Request:
```json
{ "email": "rider@example.com", "password": "…", "display_name": "…" }
```
Response `201`:
```json
{ "account_id": "acct_…", "created_at": "2026-…Z" }
```
Response `409` if email already registered.

### `POST /sessions` — login
Request:
```json
{ "email": "rider@example.com", "password": "…" }
```
Response `200`:
```json
{
  "session_token": "opaque, high-entropy, server-generated",
  "expires_at": "2026-…Z",
  "account_id": "acct_…"
}
```
Response `401` on bad credentials — **generic message only** ("invalid
email or password"), never revealing which field was wrong.

### `POST /sessions/refresh`
Request: `{ "session_token": "…" }`
Response `200`: new `session_token` + `expires_at`, or `401` if the
token is expired/revoked — client treats `401` here identically to a
never-logged-in state (falls back to the login screen), never as a
crash.

### `DELETE /sessions` — logout
Invalidates `session_token` server-side. Client clears its local copy
regardless of response status (a network failure on logout must not
leave the user stuck unable to log out locally).

### `GET /accounts/me`
Returns the current account's profile for the given `session_token` —
used by the client to confirm the stored token is still valid before
resuming into the main nav shell, and to know which account's data to
show under "My Boat"/profile.

## Client-side session model (Flutter, once the above exists)

```dart
class AuthSession {
  final String accountId;
  final String sessionToken;
  final DateTime expiresAt;
}

/// Restores a persisted session (if any) — this is the future the splash
/// awaits, exactly like PairingService.restore() is awaited today. A
/// missing/expired/malformed stored session returns null; it never
/// throws for "no session" — only for a genuine local storage failure,
/// exactly matching how PairingService.restore() already behaves.
Future<AuthSession?> restoreAuthSession();
```

Splash outcome mapping (this is the part the earlier splash-refinement
request assumed already existed):

| Outcome | Real condition | Destination |
|---|---|---|
| Valid session found | `restoreAuthSession()` returns non-null and `GET /accounts/me` confirms it | Main nav shell (existing bottom-nav `BinnacleConnectApp` shell) |
| Expired / unauthenticated | `restoreAuthSession()` returns null, or `/accounts/me` returns 401 | New login screen (does not exist yet) |
| Offline | Network unreachable during restore | Login screen, with a locally-cached "you were last signed in as X" hint if a prior session exists — never a fabricated "still logged in" state while unverified |
| Storage read failure | `flutter_secure_storage` read throws | Same visible-retry pattern `ConnectStartup` already uses for `PairingService.restore()` failures — caught, never crashes, no raw exception text shown to the user |

## Biometric unlock (additive, not a replacement for the above)

`local_auth` gates re-entry to an **already-valid, already-persisted**
session — it never itself authenticates against Core. Concretely: if a
non-expired `AuthSession` is found in secure storage, prompt Face
ID/fingerprint before proceeding to `/accounts/me` verification; a failed
or unavailable biometric prompt falls back to the existing login screen,
it does not silently proceed. This mirrors why pairing credentials
already live in Keychain/Keystore rather than plaintext — biometric adds
a local un-lock step in front of a credential that was already verified
server-side, not a new trust root of its own.

## What happens once Core actually builds this

The Flutter-side pieces below become buildable for real, with the same
verification bar as the rest of this app (real widget tests, real device
verification, no fabricated "logged in" state):

- `AuthSession` model + `restoreAuthSession()` (real HTTPS/control-channel
  calls to the endpoints above).
- A login screen (email/password form → `POST /sessions`).
- `ConnectStartup`'s `initialize` callback extended to `Future.wait` both
  `PairingService.restore()` and `restoreAuthSession()`, exactly as it
  already parallelizes work today — not a new gating mechanism.
- Biometric re-entry via `local_auth`, gated as described above.
- A signup screen (`POST /accounts`).

None of this is implemented in this change. This document is the
contract to build against once Core's side exists.
