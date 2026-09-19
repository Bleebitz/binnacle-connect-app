# Binnacle Identity Architecture v3 — Decision Record

**Decision date:** 2026-09-19  
**Status:** Owner approved  
**Controlling architecture:** `docs/architecture/BINNACLE_IDENTITY_SESSION_MEDIA_ARCHITECTURE_v3.md`  
**Superseded architecture:** `docs/evidence/CORE_USER_ACCOUNT_API_PROPOSAL.md` v2.5  
**Applies to:** Binnacle Cloud, Connect, Vision, Track, Spotter

## 1. Purpose

This record documents the owner-approved decisions that changed the Binnacle identity, session, media, entitlement and recognition architecture from v2.5 to v3.

It exists so future engineering, legal, product and program-management work can distinguish:

- current controlling decisions;
- superseded assumptions;
- historical design evidence;
- implementation work that still remains open.

The v2.5 proposal remains preserved for history and must not be rewritten to make it appear that v3 decisions existed earlier.

---

# 2. Decision 1 — Four identity/security layers

**Approved**

Binnacle separates:

1. Global Binnacle Account
2. Registered User Device
3. Vision Hardware Entity
4. temporary Ride Session Access

Vision ownership does not imply ownership of Rider identities.

A person's identity survives:

- phone replacement;
- Vision replacement;
- boat sale;
- riding behind another Binnacle-equipped boat.

**Reason**

The earlier per-boat identity approach would create siloed rider identities and prevent account/media portability.

---

# 3. Decision 2 — Global Binnacle Account replaces universal “Rider Account”

**Approved**

The permanent human login identity is a **Global Binnacle Account**.

A **Rider Profile** is optional and portable.

Vision ownership is a separate relationship to the Global Binnacle Account.

A person may:

- own Vision without riding;
- ride without owning Vision;
- own/administer several Vision units;
- participate in other boats' sessions.

**Authentication**

- Supabase Auth
- Apple
- Google
- passwordless email one-time code
- no Binnacle password database

Sensitive authentication, billing and age/compliance data remains private and separate from Rider Profile data.

---

# 4. Decision 3 — Registered devices are independent identities

**Approved**

Phones/devices are registered separately from the human account.

Each registered device receives its own cryptographic identity.

A device can be revoked without deleting:

- the Global Binnacle Account;
- Rider Profile;
- Library;
- riding history;
- Vision ownership.

Friendly device metadata such as device name and last-seen time should be supported.

---

# 5. Decision 4 — Vision Hardware Entity

**Approved**

Every Vision system has an independent Hardware Entity with:

- permanent node ID;
- serial/factory identity;
- cryptographic identity;
- ownership epoch;
- operational configuration;
- local NVMe/session registry.

The primary owner may delegate persistent Admin/Operator authority.

Persistent hardware administration is distinct from temporary Host/Crew/Guest session participation.

Hardware transfer does not transfer Rider identities or private Cloud Libraries.

---

# 6. Decision 5 — Ride Session and Active Rider are separate concepts

**Approved**

A Vision unit hosts Ride Sessions.

Authenticated participants join temporarily as:

- Host
- Crew
- Guest

Being Crew does not mean being the active rider.

Binnacle adds explicit **Rider Runs** identifying who is actually riding during each portion of the session.

Track, Rider Lock, run history, automatic media attribution and Track Follow use confirmed Active Rider / Rider Run context.

Recognition may suggest identity but may not silently establish it.

---

# 7. Decision 6 — Dynamic QR may be displayed through Connect

**Approved**

The Vision unit generates the secure join challenge.

The Connect app may render the dynamic QR code on the Host's phone.

Spotter may also display the QR but is optional.

No dedicated Vision display is required.

Connect must not fabricate a usable Join QR when Vision is offline.

mDNS remains discovery only and does not establish identity or authorization.

---

# 8. Decision 7 — Offline identity and temporary Crew authorization

**Approved**

The v2.5 Rider Identity Assertion concept is generalized to:

**Binnacle Identity Assertion (BIA)**

Approved BIA lifetime:

**14 days**

BIA proves the Global Binnacle Account offline and is cryptographically bound to the registered user device.

Vision issues temporary Crew Session Tokens.

Approved CST maximum:

**12 hours**

CSTs are:

- session-scoped;
- locally revocable;
- renewable while session is valid;
- invalid across factory reset or ownership-epoch change.

---

# 9. Decision 8 — Session continuity and recovery

**Approved**

Ordinary transport failure is not session termination.

The following do not automatically end Crew membership or the Ride Session:

- temporary Wi-Fi loss;
- phone disconnect;
- Connect restart;
- Host-phone disconnect;
- bounded Vision reboot.

Vision remains authoritative for Ride Session state.

Vision persists enough session state to recover:

- session ID;
- participants;
- roles/scopes;
- CST/revocation state;
- ownership epoch;
- Active Rider/Rider Run;
- local media registry.

Approved automatic Vision recovery window:

**60 minutes**

After Vision recovery:

- Active Rider identity may remain known;
- visual tracking does not falsely remain TRACKING;
- Track returns through ACQUIRING/REACQUIRING.

Factory reset, ownership transfer or ownership-epoch change is a hard boundary.

---

# 10. Decision 9 — Guest-to-Global architecture

**Approved**

Guests may participate without a usable authenticated Binnacle identity.

The system must support:

- Guest Session ID;
- short local Claim Code;
- long remote Claim Code;
- later claim into a Global Binnacle Account.

The two-form Claim Code architecture is mandatory.

## Short local code

- boat-Wi-Fi/local Vision redemption only;
- physical-presence scoped;
- rate limited.

## Long remote code

- Cloud redemption;
- higher entropy;
- securely hashed/HMACed at rest;
- authenticated account required;
- single use.

Approved hard expiration:

**30 days**

Guest media must be linked rather than unnecessarily duplicated during claim.

---

# 11. Decision 10 — Media model changes

**Approved**

Binnacle separates:

1. Session Master
2. Cloud Media Asset
3. Personal Library Pointer

Owning Vision hardware does not automatically make the owner the permanent personal owner of every rider clip.

The v2.5 automatic `unit_owner_master` Library pointer is superseded.

A confirmed Rider Run may establish eligibility for Rider media.

Multi-person media may have multiple pointers to one stored Cloud asset.

---

# 12. Decision 11 — Participant Snapshots and Highlights

**Approved**

Any admitted participant may independently use permitted personal capture controls.

## Snapshot

A participant may take a Snapshot from their own phone.

A local-only Snapshot:

- is saved to that phone;
- does not grant access to the Session Master;
- does not affect another person's Library.

## Highlight

A participant may request a Highlight from Vision.

Vision creates/references the best-quality Session Master media.

The requesting authenticated account receives a personal Library relationship.

Guest Highlights remain associated with the Guest Session until claimed.

The person requesting the Highlight may differ from the Active Rider.

Personal capture is enabled by default for admitted participants unless an explicit session privacy mode disables it.

---

# 13. Decision 12 — Ordinary Vision ownership does not grant delete-for-all

**Approved**

The v2.5 ordinary unit-owner `delete-for-all` authority is superseded.

Three separate actions exist:

1. Delete from My Library
2. Delete from Vision / Session Master
3. Global privacy takedown

Deleting from a personal Library removes only that account's pointer.

Deleting local Vision/session media does not automatically delete another person's valid Cloud pointer.

Global deletion uses the separate privacy/takedown process.

---

# 14. Decision 13 — Privacy/takedown process

**Approved**

Eligible requesters may include:

- affected Binnacle account holder;
- affected rider/person;
- appropriate guardian;
- non-account bystander through Support;
- Binnacle Support.

Credible requests move the media into a restricted pending state.

Approved initial review target:

**48 hours**

If the review exceeds 48 hours, the media remains restricted until resolved.

The Vision owner may provide context but does not have unilateral veto authority over another person's privacy request.

## Anti-spam guardrail

A user may have no more than:

**5 open/pending user-initiated takedown requests**

at one time.

Support-entered legal/bystander cases are separate from this per-user limit.

---

# 15. Decision 14 — Takedown Hash List

**Approved**

Approved global removal propagates through a signed/versioned Takedown Hash List.

On reconnect Vision must:

1. fetch the latest verified takedown data;
2. apply it before media uploads;
3. delete matching local media;
4. block re-upload;
5. return an erase receipt where supported.

Binnacle cannot guarantee deletion of media already exported to unmanaged personal devices.

---

# 16. Decision 15 — Separate entitlement models

**Approved**

Binnacle uses two independent entitlement types.

## Vision Hardware Entitlement

Attaches to:

`node_id`

May govern:

- capture/processing;
- live streaming;
- live destinations;
- session-level Cloud features;
- Vision/Track capabilities.

## Global Binnacle Account Entitlement

Attaches to:

`user_id`

May govern:

- personal Library retention;
- creator tools;
- personal Cloud features;
- future personal AI/create benefits.

Payer and Vision owner may be different accounts.

Changing payer does not transfer hardware ownership.

---

# 17. Decision 16 — Trials and live entitlement

**Approved**

New Vision hardware receives:

**one month of the highest ordinary consumer Vision tier**

upon first legitimate activation.

Transferred used Vision hardware receives:

**14 days Ride**

and does not receive another new-hardware top-tier trial.

Free/base Vision supports:

**one live destination**

Higher tiers may support multi-destination streaming and additional Cloud/AI capabilities.

Highest ordinary consumer subscription target remains approximately:

**$20/month or less**

as a commercial target rather than a schema invariant.

---

# 18. Decision 17 — Spotter Recognition is optional

**Approved**

Spotter Recognition is distinct from:

- Global Binnacle Account;
- Rider Profile.

Binnacle, Track, Rider Runs, Snapshots and Highlights must work without Spotter biometrics.

Spotter recognition is optional assistance for identity continuity/reacquisition.

It is not required for baseline Track.

---

# 19. Decision 18 — Per-session Spotter opt-in

**Approved**

Spotter Recognition is:

**OFF by default**

for every Ride Session.

Only the rider may enable:

> Allow Spotter AI to recognize me this session.

Host/owner cannot enable recognition for someone else.

Current eligibility policy:

- Guests: no biometric recognition.
- Under 18: no biometric recognition.

Vision receives only minimum session-scoped recognition material.

It must not accumulate a permanent database of everyone who rides behind a boat.

Recognition data is purged at opt-out/session end.

---

# 20. Decision 19 — Biometric production hard block

**Approved**

Consumer biometric enrollment, storage, transmission or matching may not enter production without documented legal/privacy sign-off.

Synthetic-data engineering may proceed under controlled conditions.

The biometric enforcement implementation currently exists on PR #10 but has not yet been safely preserved and verified on `main`.

Required before production biometric work:

- biometric guard preserved on `main`;
- feature default OFF;
- legal sign-off mechanism;
- independent privacy review;
- second privacy admin with write access.

---

# 21. Decision 20 — Account/device/hardware/session recovery are separate

**Approved**

Recovery domains are independent:

- Global Binnacle Account
- User Device
- Vision Hardware
- Ride Session

Losing a phone does not delete the person's account/history.

Physical Vision reset does not transfer Cloud ownership.

Stolen Vision hardware can remain blocked across reset.

Disputed ownership requires controlled Support verification and cryptographic reset.

Ownership recovery does not restore previous sessions, CSTs, Wi-Fi secrets, streaming credentials or other private state.

---

# 22. Decision 21 — Cloud provider baseline

**Approved controlling provider architecture**

- Supabase Auth — human authentication
- Binnacle token service — offline/device-bound BIA issuance
- Cloudflare R2 — durable media
- Cloudflare Stream — live ingest, fan-out/simulcast and viewer delivery

**AWS IVS and AWS MediaLive are formally deprecated from the controlling live-stream architecture.**

Older tickets/documents mentioning them are historical unless a future controlled decision explicitly reopens that evaluation.

---

# 23. Superseded v2.5 assumptions

The following v2.5 concepts are explicitly superseded:

- universal “Rider Account” terminology for the permanent human account;
- boat-scoped/permanent rider membership;
- treating Crew and Active Rider as equivalent;
- no explicit Rider Run model;
- automatic unit-owner personal pointer to every clip;
- ordinary unit-owner delete-for-all authority;
- narrower RIA terminology;
- incomplete reconnect/session-recovery model;
- permissive language around two-form Guest Claim Codes;
- AWS IVS / MediaLive live-stack references;
- any implication that Spotter biometric identity is automatically part of every Rider Account.

---

# 24. Preserved v2.5 concepts

The following remain useful where consistent with v3:

- Supabase Auth;
- Binnacle token service;
- phone-bound offline identity;
- CST/session-scoped authorization;
- QR + local discovery;
- Guest-to-Global concept;
- ownership epoch;
- cryptographic hardware transfer/reset;
- stolen-unit protection;
- Cloudflare R2;
- Cloudflare Stream;
- signed/versioned takedown hashes;
- media deduplication;
- biometric consent separation;
- biometric production hard block.

---

# 25. Program-record actions required

After the v3 architecture is preserved in GitHub:

1. Update Master Work Register v3.0 — Decision Register.
2. Update Master Work Register v3.0 — Evidence Index.
3. Update Master Work Register v3.0 — Linear Map.
4. Update Master Work Register v3.0 — Change Log.
5. Reconcile the approved Cloud architecture document.
6. Reconcile older Device Pairing and Authorization documentation.
7. Reconcile Linear issues BIN-40, BIN-41, BIN-43, BIN-46, BIN-48, BIN-39.
8. Create a dedicated Binnacle Identity implementation issue under BIN-37 if not already present.
9. Preserve the biometric guard separately from PR #10's conflicting runtime code.

---

# 26. Implementation warning

This Decision Record and the v3 architecture authorize architectural preservation and future implementation planning.

They do **not** authorize blindly merging PR #10 runtime code.

PR #10 contains Library, Community and Live implementation that must be separately reconciled against newer Connect work.

Architecture preservation and runtime-code reconciliation are different workstreams.
