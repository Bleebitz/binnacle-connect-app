# Binnacle Identity, Session & Media Architecture v3

Status: Owner-approved controlling architecture; preserved on main. Durable program-record reconciliation pending.  
**Owner decision date:** 2026-09-19  
**Applies to:** Binnacle Cloud, Connect, Vision, Track and Spotter  
**Primary implementation issues:** BIN-46, BIN-40, BIN-41, BIN-43, BIN-48, BIN-39  
**Cloud baseline:** Supabase Auth, Binnacle token service, Cloudflare R2 durable media, Cloudflare Stream live pipeline  
**Edge baseline:** Binnacle Vision on Jetson Orin Nano, with local/offline session operation

## 0. Purpose and supersession

This document defines the controlling architecture for:

- Global Binnacle human identity
- optional Rider Profiles
- registered phones and other user devices
- Vision hardware ownership and administration
- temporary Ride Session authorization
- Active Rider / Rider Run state
- offline joining and reconnect
- session continuity and recovery
- Session Master media
- personal Snapshots and Highlights
- Cloud media and Library relationships
- Vision and personal subscription entitlements
- privacy/takedown behavior
- Spotter recognition boundaries
- hardware transfer and account/device recovery

This document **supersedes the architecture decisions in**:

`docs/evidence/CORE_USER_ACCOUNT_API_PROPOSAL.md` v2.5

The v2.5 document must be retained as historical design evidence and marked superseded. It must not be deleted.

This v3 document also supersedes:

- v1 Core-side single email/password account design
- the rejected Core-issued per-boat member-account concept
- any architecture that treats permanent Crew membership as the rider's identity
- any architecture that automatically makes the Vision owner the permanent personal owner of every rider clip

Useful security, token, offline, hardware-transfer and Cloud concepts from v2.5 are carried forward where they remain consistent with the owner-approved v3 decisions.

Nothing in this document by itself claims that the described Cloud identity, session, media or biometric architecture has been deployed.

---

# 1. Core architectural principle

A human identity, a phone, a Vision unit and permission to participate in a ride are separate things.

Binnacle therefore uses four primary identity/security layers:

1. **Global Binnacle Account** — the permanent human identity.
2. **Registered User Device** — a phone/device cryptographically associated with that account.
3. **Vision Hardware Entity** — the physical Binnacle Vision system.
4. **Ride Session Access** — temporary permission to participate in a specific session.

Additional optional identity layers include:

- **Rider Profile** — portable riding/social identity belonging to a Global Binnacle Account.
- **Spotter Recognition Profile** — separately consented, legally gated recognition capability.

The governing rule is:

> **A boat hosts a session. It does not own a person's identity.**

Ownership of Vision hardware does not imply ownership of Rider identities, Rider Profiles or another person's personal Cloud Library.

---

# 2. Architecture at a glance

```text
Global Binnacle Account
│
├── Registered User Devices
│     ├── phone-bound device key
│     ├── platform/device metadata
│     └── independent revoke state
│
├── optional Rider Profile
│     ├── unique handle
│     ├── display name
│     ├── profile media/details
│     └── profile privacy
│
├── optional Spotter Recognition Profile
│     ├── separate explicit consent
│     ├── encrypted recognition material
│     └── legal/privacy gated
│
├── Personal Account Entitlement
│     └── personal Library / creator / retention benefits
│
└── Vision Hardware Relationships
      ├── Owner
      ├── Admin
      └── Operator


Vision Hardware Entity
│
├── node identity / factory identity
├── ownership epoch
├── Vision Hardware Entitlement
├── local NVMe/session state
├── Track/Vision runtime
└── hosts Ride Sessions
       │
       ├── Session Participants
       │     ├── Host
       │     ├── Crew
       │     └── Guest
       │
       ├── Rider Runs
       │     └── confirmed Active Rider
       │
       └── Session Master Media
              │
              ├── participant Snapshots
              ├── participant Highlights
              ├── Track-generated media
              └── Cloud Media Assets
                       │
                       └── independent Library Pointers
```

---

# 3. Global Binnacle Account

## 3.1 Human identity

The permanent human identity is a **Global Binnacle Account**, not a boat account and not necessarily a Rider Account.

A person may:

- own Vision hardware without riding;
- ride without owning Vision hardware;
- own multiple Vision units;
- administer someone else's Vision unit;
- ride behind many Binnacle-equipped boats;
- have several registered phones over time.

The permanent account identifier is `user_id`.

Email address, phone identity, Vision serial number and boat ownership are not permanent human identifiers.

## 3.2 Authentication

Binnacle uses:

**Supabase Auth**

Initial supported sign-in methods:

- Sign in with Apple
- Sign in with Google
- passwordless email one-time code

Binnacle does not maintain a custom password database.

Authentication-provider identities are separate from the Binnacle application profile.

Provider linking requires authenticated account control and must not silently merge accounts solely because two providers report the same email address.

## 3.3 Private account data

Private account data may include:

- `user_id`
- account status
- compliance/age information
- verified contact/authentication references
- billing/customer reference
- account creation/deletion state
- consent records

Sensitive values such as date of birth, email address, billing identifiers and authentication identities must not become public Rider Profile data.

A Vision unit must receive only the minimum derived eligibility facts it requires, not unnecessary personal information such as a rider's birth date.

---

# 4. Rider Profile

A **Rider Profile** is optional and belongs to a Global Binnacle Account.

Suggested logical fields:

```text
rider_profiles
---------------
user_id
handle
display_name
profile_photo_ref
bio
optional_home_region
privacy_level
created_at
updated_at
```

Rules:

- `handle` is globally unique.
- `display_name` need not be unique.
- profile privacy is independent from media privacy.
- a Rider Profile follows the rider across boats and phones.
- selling Vision hardware does not transfer a Rider Profile.
- replacing a phone does not recreate the Rider Profile.

A person who owns Vision hardware but does not ride is not required to create a Rider Profile.

---

# 5. Registered User Devices

Every registered phone/device has its own cryptographic identity.

Suggested logical model:

```text
user_devices
------------
device_id
user_id
public_jwk
jwk_thumbprint
platform
device_name
registered_at
last_seen_at
revoked_at
```

The device private key is non-exportable where supported.

A copied identity token without possession of the registered device key must not be sufficient to authenticate to Vision.

Revoking a phone:

- invalidates that device's future authorization;
- does not delete the Global Binnacle Account;
- does not delete Rider history;
- does not delete personal Library relationships;
- does not transfer or erase Vision ownership.

---

# 6. Vision Hardware Entity

Each Vision system is an independent Hardware Entity.

Suggested persistent attributes include:

```text
hardware_nodes
--------------
node_id
owner_user_id
serial
model
display_name
factory_attestation_identity
node_public_key
node_key_id
ownership_epoch
status
join_policy
claimed_at
last_seen_at
software_version
```

The Vision unit has:

- a permanent Binnacle node identifier;
- physical serial/factory identity;
- current cryptographic device identity;
- ownership epoch;
- operational configuration;
- local media/session registry.

The friendly boat/unit name is only a label and is not the hardware identity.

## 6.1 Hardware administration

The primary hardware owner may delegate persistent administration.

A separate relationship should represent roles such as:

```text
node_admins
-----------
node_id
user_id
role = owner | admin | operator
granted_at
revoked_at
```

Only the primary Owner, or a controlled Support recovery process, may permanently transfer hardware ownership.

Persistent Owner/Admin/Operator roles are different from temporary Host/Crew/Guest Ride Session roles.

---

# 7. Vision local data boundary

Vision may retain local operational information required to function offline, including:

- local video files;
- Track events;
- session metadata;
- media hashes and registry;
- current configuration;
- temporary session credentials;
- revocation/trust bundles;
- recording state;
- Active Rider / Rider Run state;
- synchronization state.

Vision must not become the permanent system of record for:

- Rider social profiles;
- another person's personal Cloud Library;
- user passwords;
- authentication-provider credentials;
- billing identity;
- permanent Spotter recognition profiles.

---

# 8. Ride Sessions

A Vision unit hosts **Ride Sessions**.

A Ride Session belongs operationally to:

> Vision Hardware Entity + session

not to an individual Rider Account.

Suggested model:

```text
node_sessions
-------------
node_session_id
node_id
ownership_epoch
started_by
started_at
ended_at
session_state
recovery_deadline
synced_at
```

A Ride Session can include many participants and many Rider Runs.

---

# 9. Session Participants

Participation is modeled independently of security-token storage.

Suggested model:

```text
session_participants
--------------------
participant_id
node_session_id
subject_type = account | guest
user_id?
guest_session_id?
role = host | crew | guest
joined_at
left_at
revoked_at
```

Roles:

- **Host** — session operator.
- **Crew** — authenticated temporary participant.
- **Guest** — participant without usable authenticated account identity.

Session participation does not permanently attach a person to the boat.

---

# 10. Active Rider and Rider Runs

Being Crew does not mean being the person currently riding.

Binnacle therefore maintains explicit **Rider Runs**.

Suggested model:

```text
rider_runs
----------
rider_run_id
node_session_id
participant_id
user_id?
guest_session_id?
started_at
ended_at
assignment_method
confirmed_by
state
```

Only one Rider Run is normally Active for Track-follow purposes at a time.

Example:

```text
10:15–10:28  Levi
10:34–10:49  Seth
11:03–11:17  Jane
```

A rider change does not end the overall Ride Session.

Confirmed Active Rider context informs:

- Track
- Rider Lock
- Track Follow
- run history
- automatic highlights
- media attribution

Visual recognition may later suggest identity, but must not silently establish it.

---

# 11. Identity tokens

## 11.1 Cloud access token

Purpose: Binnacle Cloud APIs.

Typical lifetime: short-lived, refreshable.

## 11.2 Binnacle Identity Assertion (BIA)

This replaces the narrower v2.5 term **Rider Identity Assertion (RIA)**.

Purpose:

> Prove that a specific registered device represents a specific Global Binnacle Account when Vision has no internet access.

Properties:

- issued by Binnacle Cloud/token service;
- ES256 or equivalent approved signing mechanism;
- bound to registered device key;
- verifiable by Vision offline;
- no email, billing data or biometric material;
- approved lifetime: **14 days**.

A copied BIA without possession of the registered device key must be useless.

## 11.3 Crew Session Token (CST)

Issued by Vision.

Purpose:

> Authorize one participant for one Ride Session.

Properties:

- bound to `node_session_id`;
- bound to Vision ownership epoch;
- bound to participant's registered device where applicable;
- locally revocable;
- renewable while session remains valid;
- hard maximum: **12 hours**;
- invalid across factory reset or ownership-epoch change.

---

# 12. Joining a Ride Session

## 12.1 Default policy

Default:

> **Host approval required**

Optional future policies may include:

- known Crew auto-join;
- open to authenticated riders.

## 12.2 Dynamic QR

The Connect app is the preferred operator surface for displaying a Join QR.

Flow:

```text
Vision
  ↓ generates
node/session identity
node-key fingerprint
one-time join nonce
expiry
  ↓
Host Connect app
  ↓ renders
dynamic QR
  ↓
Joining Connect app
  ↓ proves
Binnacle Account + device key
  ↓
Vision
  ↓
Host approval
  ↓
Crew Session Token
```

Important:

- Vision generates the actual join challenge.
- Connect renders it.
- Connect must not create a fake usable Join QR if Vision is offline.
- Spotter may display the same join QR but is optional.
- A Vision-attached display is not required.
- QR material should rotate, initially targeted at approximately 60 seconds.

## 12.3 mDNS/local discovery

mDNS may be used for convenient discovery, particularly for returning Crew.

mDNS provides:

> discovery only.

It does not establish identity or authorization.

Actual trust comes from:

- Vision cryptographic identity;
- Global Binnacle Account assertion;
- device-key proof;
- session state;
- Host/join policy.

---

# 13. Offline operation

Identity is established while internet access is available and cached securely for on-water use.

With no cellular connection, a valid BIA permits:

- identity proof;
- session join;
- Host approval;
- CST issuance;
- Crew authorization;
- Active Rider selection;
- recording;
- Track;
- Highlights;
- local NVMe operation.

Cloud upload waits until connectivity returns.

A new account cannot be created entirely offline.

A participant without a usable BIA may join as Guest.

---

# 14. Session continuity and recovery

A transport disconnect is not the same thing as a session ending.

## 14.1 Phone/Wi-Fi disconnect

Connect retains sufficient local session state to rediscover and reconnect to the same Vision session.

A valid participant should not require:

- another QR scan;
- another Host approval;

solely because Wi-Fi temporarily disconnected.

## 14.2 App restart

If Connect restarts while a valid Ride Session remains open, it attempts to restore the same session using valid existing credentials.

## 14.3 Host phone disconnect

Vision is authoritative for Ride Session state.

Loss of the Host phone must not automatically stop:

- recording;
- Track;
- Crew connections;
- Active Rider state;
- session media capture.

## 14.4 Vision reboot

Vision durably persists enough active-session state to recover:

- session ID;
- ownership epoch;
- approved participants;
- CST/revocation state;
- roles/scopes;
- Active Rider / Rider Run;
- local media/session registry.

An unexpected reboot may enter:

```text
ACTIVE
  ↓
INTERRUPTED
  ↓
RECOVERING
  ↓
ACTIVE
```

or:

```text
INTERRUPTED
  ↓
CLOSED
```

Initial automatic recovery window:

**60 minutes**

Recovery is permitted only when:

- same Vision hardware;
- same ownership epoch;
- session was not explicitly ended;
- security state remains valid.

## 14.5 Track recovery

Active Rider identity may survive session recovery.

Computer-vision tracking state must not be falsely represented as continuous.

After recovery:

```text
Active Rider = preserved
Track = ACQUIRING / REACQUIRING
```

Only after real visual reacquisition may Track return to TRACKING.

## 14.6 Hard boundaries

No Ride Session recovery crosses:

- factory reset;
- ownership transfer;
- ownership-epoch change;
- security wipe.

---

# 15. Guest-to-Global participation

A Guest may participate without a usable Binnacle account credential.

The Vision unit issues:

- Guest Session ID;
- temporary Guest access;
- Claim Code.

Guest media is not attributed through biometric recognition.

A Guest may later authenticate/create a Global Binnacle Account and claim eligible media/history.

## 15.1 Mandatory two-form Claim Code architecture

The system **must** implement the approved two-form Claim Code architecture.

### Short local code

Purpose:

> Claim Guest media while physically connected to the originating boat's local network.

Requirements:

- usable only through the originating Vision unit / boat Wi-Fi;
- scoped to the specific Guest Session;
- protected by local rate limiting;
- not accepted as an internet-wide Cloud redemption credential.

Example form may resemble:

`WAKE-842`

The exact human-readable characters remain an implementation detail, but the short code must not be usable as the sole credential for remote Cloud redemption.

### Long remote code

Purpose:

> Claim Guest media later through Binnacle Cloud.

Requirements:

- significantly higher entropy than the local short code;
- stored only as a secure hash/HMAC representation at rest;
- plaintext must not be persistently stored by Cloud;
- rate limited and single-use;
- usable only by an authenticated Global Binnacle Account;
- associated with the originating Guest Session.

Example form may resemble:

`WAKE-842-K7Q2M9`

Exact formatting remains an implementation detail.

### Expiration

Both forms represent the same underlying Guest claim relationship and have a hard expiration of:

**30 days**

After 30 days, the Claim Code may not be redeemed.

Local and remote redemption must converge on the same Guest-to-Global claim record so that media is linked rather than unnecessarily duplicated.

---

# 16. Media model

Binnacle separates:

1. **Session Master**
2. **Cloud Media Asset**
3. **Personal Library Pointer**

## 16.1 Session Master

The Session Master is the operational footage captured by Vision.

It may include:

- full raw session footage;
- audio;
- Track metadata;
- Rider Runs;
- local originals.

Vision/Host controls recording and operational session-media management.

Session Master access does not automatically create permanent personal Library ownership of every clip.

## 16.2 Cloud Media Asset

A Cloud Media Asset is the stored object.

It is not inherently “owned” by one human.

It records provenance such as:

- source Vision node;
- Ride Session;
- source media;
- checksum;
- creation time.

Cloud durable store:

**Cloudflare R2**

## 16.3 Library Pointer

A Library Pointer means:

> This Global Binnacle Account has a legitimate personal relationship to this Cloud Media Asset.

Suggested logical model:

```text
media_pointers
--------------
pointer_id
media_asset_id
user_id
relationship_type
created_via
retention_expires_at
created_at
deleted_at
```

Multi-person media may have several Library Pointers without duplicating the stored video.

---

# 17. Rider media attribution

A confirmed Rider Run makes its eligible rider media assignable to the corresponding account/profile according to session sharing policy.

This is preferred over attempting to infer personal ownership solely from computer vision.

Possible creation causes include:

```text
rider_run
participant_trigger
track_auto
host_share
guest_claim
```

---

# 18. Personal Snapshots

Any admitted participant may take a Snapshot from the current live Vision view, subject to an explicit session-level privacy setting.

A Snapshot saved directly on the participant's phone:

- belongs locally to that phone/user;
- does not alter Session Master;
- does not grant access to raw session footage;
- is outside Binnacle Cloud deletion control unless uploaded to Binnacle.

Connect should clearly distinguish:

> Saved to this phone

from:

> Saved to Binnacle Library

---

# 19. Personal Highlights

Any admitted participant may request a personal Highlight, subject to session privacy settings.

The participant's phone sends a time-scoped Highlight request to Vision.

Vision creates or references the best-quality highlight using Session Master media.

The requesting authenticated account receives a personal Library relationship.

For Guests:

- Highlight remains associated with the Guest Session;
- it may later be claimed into a Global Binnacle Account.

The Active Rider and Highlight requester may be different people.

Example:

```text
Active Rider = Jane
Highlight requested by = Levi
```

Jane may receive Rider Run attribution.

Levi may receive the personal Highlight he intentionally requested.

The underlying media need not be duplicated.

---

# 20. Media deletion

Three actions are separate.

## 20.1 Delete from My Library

Removes only that user's Library Pointer.

Other valid pointers remain.

## 20.2 Delete from Vision / Session Master

Removes Vision-local or Host-controlled session media according to session rules.

It does not automatically remove another person's independently valid Cloud Library pointer.

## 20.3 Global privacy takedown

Global removal uses a separate privacy/takedown process.

Ordinary ownership of the Vision hardware does not grant unrestricted authority to delete already-distributed personal Cloud media from another Global Binnacle Account.

The v2.5 automatic `unit_owner_master` pointer and ordinary unit-owner `delete-for-all` authority are superseded.

---

# 21. Privacy/takedown process

Eligible requesters may include:

- affected Binnacle account holder;
- affected rider/person;
- appropriate guardian path;
- non-account bystander through Support;
- Binnacle Support where required.

A credible request places Binnacle-controlled media into a restricted pending state.

Suggested lifecycle:

```text
AVAILABLE
  ↓
TAKEDOWN_PENDING
  ├── RESTORED
  └── REMOVED
```

Initial review target:

**48 hours**

Missing the target does not automatically restore the media.

The item remains restricted until resolved.

## 21.1 Open-request anti-spam limit

An authenticated user may have a maximum of:

**5 open/pending takedown requests at one time.**

A sixth user-initiated request must not enter the ordinary pending queue until one of the existing requests is resolved, withdrawn or otherwise closed.

Support-entered cases for non-account bystanders or other controlled Support/legal workflows are handled separately from this per-user in-app limit.

The Vision owner may provide context but does not hold unilateral veto power over another person's privacy request.

---

# 22. Approved global-removal behavior

When global removal is approved:

1. applicable Cloud Library Pointers are invalidated;
2. Binnacle-controlled Cloud media and derivatives are deleted according to policy;
3. the source hash is added to a signed/versioned Takedown Hash List;
4. affected Vision units receive the deletion on reconnect;
5. Vision applies the current verified Takedown Hash List **before uploads**;
6. matching local NVMe media is deleted;
7. re-upload is blocked;
8. Vision returns a signed erase receipt where supported.

Previously exported personal-device copies are outside Binnacle's technical control.

Notifications to other affected accounts are neutral and do not disclose:

- requester identity;
- thumbnail;
- sensitive title;
- reason.

---

# 23. Derived media

Binnacle-managed derivatives must retain source provenance.

Examples:

- Track Follow version;
- Highlight;
- preview;
- AI Cinematic derivative;
- future enhanced media.

A derived asset should inherit source access relationships unless explicitly shared differently.

Source/derivative relationships must permit approved takedown propagation.

---

# 24. Entitlements

Binnacle separates:

1. **Vision Hardware Entitlement**
2. **Global Binnacle Account Entitlement**

## 24.1 Vision Hardware Entitlement

Attaches to:

`node_id`

May govern:

- capture/processing features;
- Vision/Track feature set;
- live streaming;
- external destination count;
- Binnacle Live features;
- session-level Cloud processing;
- full-session Cloud backup.

The payer is a Global Binnacle Account but may differ from the hardware owner.

Changing payer does not transfer ownership.

## 24.2 Global Binnacle Account Entitlement

Attaches to:

`user_id`

May govern:

- personal Library retention;
- creator tools;
- personal AI/create benefits;
- Rider-level Cloud features;
- future community/creator benefits.

These benefits follow the person across boats.

They do not upgrade another person's Vision hardware.

---

# 25. Trials and live entitlement

Approved commercial rules:

### New Vision hardware

First legitimate activation receives:

**one month of the highest ordinary consumer Vision tier**

### Used/transferred Vision hardware

Does not receive another new-unit trial.

Initial approved resale onboarding trial:

**14 days Ride**

### Free/base Vision experience

Supports:

**one live destination**

Higher paid Vision tiers may support:

- multiple destinations;
- additional live capabilities;
- additional Cloud/AI capabilities.

Pricing is represented through commercial product/price identifiers rather than hard-coded into identity architecture.

Highest ordinary consumer subscription target remains approximately:

**$20/month or less**

as a commercial target, not a schema invariant.

---

# 26. Retention

Vision/session retention and personal account retention are separate.

Example:

- Vision Session Master expires after 30 days;
- rider's personal Creator+ pointer remains valid for one year.

The underlying Cloud object may remain while at least one legitimate retention relationship requires it.

A subscription lapse or payment failure must not cause immediate surprise deletion.

The product must provide clear grace/retention warnings before media becomes deletion-eligible.

---

# 27. Spotter Recognition Profile

Spotter Recognition is separate from both:

- Global Binnacle Account;
- Rider Profile.

A person may fully use Binnacle without a Spotter Recognition Profile.

Baseline Track/Rider Lock uses:

- confirmed Active Rider;
- Rider Run state;
- role logic;
- spatial tracking;
- tracking continuity.

Biometric recognition is an optional assistance mechanism for reacquisition/identity continuity.

It is not required for Track.

---

# 28. Spotter consent and session use

Spotter Recognition requires:

- separate explicit enrollment;
- separate explicit biometric consent;
- eligibility checks;
- per-Ride opt-in.

Default each Ride Session:

**OFF**

Only the rider may enable:

> Allow Spotter AI to recognize me this session.

The Host/owner cannot enable recognition for another person.

Current approved policy:

- Guests: not eligible.
- Under 18: not eligible.
- US MVP account/age compliance remains subject to legal review.

When enabled, Vision receives only the minimum session-scoped recognition material required.

Vision must not retain a permanent database of everyone who has ever ridden behind the boat.

Session recognition material is purged when:

- rider opts out;
- rider leaves;
- Ride Session ends;
- applicable security/session state is destroyed.

Track continues without biometric recognition after opt-out.

---

# 29. Biometric legal/privacy hard block

Consumer biometric enrollment, storage, transmission or matching must not enter production without documented legal/privacy sign-off.

Synthetic-data engineering/testing may proceed under controlled conditions.

The biometric enforcement implementation currently exists on PR #10, including:

- feature default OFF;
- biometric guard;
- privacy-admin approval requirement;
- legal sign-off record requirement;
- CODEOWNERS/privacy-admin controls.

However:

> **PR #10 is not `main`.**

The enforcement must be safely preserved and verified on `main` before this architecture may claim that production enforcement is active.

A second independent privacy admin with repository write access is required before production biometric changes can satisfy the intended independent-approval rule.

---

# 30. Vision ownership transfer

Hardware ownership transfer does not transfer a Rider identity or personal Library.

Approved transfer principles:

- seller initiates transfer;
- Cloud stops issuing old-node credentials;
- local private data is wiped;
- old node signing identity is revoked;
- ownership epoch increments;
- buyer claims a clean Vision Hardware Entity;
- previous Rider Profiles and personal Libraries remain with their original accounts.

Local reset protects local privacy.

Physical possession/reset alone does not transfer Cloud ownership.

---

# 31. Hardware recovery and stolen units

Global Account recovery, User Device recovery, Vision Hardware recovery and Ride Session recovery are separate processes.

## Lost/replaced phone

The user reauthenticates to the same Global Binnacle Account and registers a new device key.

Personal identity/history remains unchanged.

## Stolen Vision unit

Owner of record may place Vision into a blocked state.

The block survives physical reset.

A thief must not gain Cloud ownership by wiping the Jetson.

## Ownership dispute

Handled through controlled Binnacle Support verification.

Approved recovery still requires:

- verified ownership evidence;
- clean cryptographic reset;
- new ownership/security epoch.

Previous sessions, CSTs, Wi-Fi credentials, streaming credentials and local private state are not restored across this boundary.

---

# 32. Incapacity/inheritance boundary

Future ownership-recovery procedures may support incapacity, estate or inheritance cases.

They must distinguish:

**physical Vision hardware ownership**

from:

**the person's private Global Binnacle Account and Rider media**

Inheriting Vision hardware must not automatically expose the prior owner's private personal Library.

---

# 33. Cloud/live boundary

Current approved provider architecture:

- **Cloudflare R2** — durable media.
- **Cloudflare Stream** — live SRT ingest, fan-out/simulcast and viewer delivery.
- **Supabase Auth** — human authentication.
- **Binnacle token service** — BIA/device-bound offline authorization.

Vision sends one primary live uplink.

Provider secrets and stream credentials remain outside app-visible storage and are not exposed to Crew.

Broadcast control remains separate from any vessel-control plane.

## 33.1 AWS live-stack deprecation

**AWS IVS and AWS MediaLive are formally deprecated from the Binnacle streaming architecture.**

They must not be reintroduced as the default live ingest or fan-out architecture from older documentation or tickets.

The controlling live architecture is:

> **Cloudflare Stream for live ingest, simulcast/fan-out and viewer delivery.**

The AWS IVS/MediaLive path was rejected in favor of Cloudflare Stream to protect the approved Creator-tier margin model and the requirement that total live cost remain within the established live-cost ceiling.

Older references to AWS IVS or AWS MediaLive are historical/superseded unless a future controlled architecture decision explicitly reopens that evaluation.

---

# 34. Security invariants

The following are architectural invariants:

1. No user passwords stored by Binnacle.
2. No stream/provider secrets in source code, logs, screenshots or evidence.
3. Vision does not hold standing R2 list/read credentials.
4. User identity tokens are device-bound where applicable.
5. Crew access is session-scoped.
6. Ownership-epoch change invalidates prior ownership-scoped credentials.
7. Physical reset alone cannot transfer Cloud ownership.
8. mDNS is discovery only.
9. A WebSocket disconnect does not equal session termination.
10. Spotter recognition is never authentication.
11. Spotter is opt-in per ride and OFF by default.
12. Rider identity is never inferred solely because the person is Crew.
13. Vision ownership does not grant unrestricted control over another user's distributed personal Cloud Library.
14. Approved takedown hashes are applied before Vision uploads after reconnect.
15. Guest remote claim requires the long-form Claim Code; the short local code is boat-network-only.
16. Guest Claim Codes expire after 30 days.
17. AWS IVS and AWS MediaLive are deprecated from the controlling live-stream architecture.

---

# 35. API direction

The following endpoints are architectural guidance, not a frozen wire contract.

### Identity

```text
POST   /v1/identity/token
POST   /v1/auth/refresh
POST   /v1/auth/logout
POST   /v1/devices
DELETE /v1/devices/{id}
DELETE /v1/users/me
GET    /.well-known/jwks.json
```

### Vision ownership/admin

```text
POST   /v1/nodes/claim
GET    /v1/nodes
PATCH  /v1/nodes/{id}
POST   /v1/nodes/{id}/admins
DELETE /v1/nodes/{id}/admins/{user}
POST   /v1/nodes/{id}/transfer
POST   /v1/nodes/{id}/deauthorize
```

### Session

```text
POST   /v1/session/start
GET    /v1/session/join-challenge
POST   /v1/join/hello
POST   /v1/join/prove
POST   /v1/session/refresh
POST   /v1/session/revoke
POST   /v1/session/end
POST   /v1/session/recover
```

### Rider Runs

```text
POST   /v1/session/rider-runs
PATCH  /v1/session/rider-runs/{id}
POST   /v1/session/rider-runs/{id}/end
```

### Personal capture

```text
POST   /v1/session/highlights
```

Local Snapshot capture may remain primarily a Connect/device operation.

### Guest Claim

```text
POST   /v1/guest/claim-code
POST   /v1/claims/redeem
```

The local endpoint accepts only the short boat-local claim form.

Cloud redemption accepts only the long remote claim form.

Both forms expire after 30 days.

### Media/privacy

```text
DELETE /v1/media/{id}/pointer
POST   /v1/media/{id}/takedown
GET    /v1/nodes/{id}/takedown-hashes
```

User-initiated takedown creation must enforce the maximum of 5 simultaneous open/pending requests.

---

# 36. Migration from existing Connect pairing

Current Connect pairing permanently binds a phone to a boat/Core credential.

Under v3:

- first-owner provisioning becomes Vision claim;
- persistent device ownership/admin becomes explicit node relationship;
- Crew participation becomes ephemeral Ride Session authorization;
- existing pairing credentials may remain temporarily during migration;
- permanent per-boat Crew identity is retired.

Because this affects a security-sensitive existing protocol, implementation requires explicit migration testing.

---

# 37. Delivery phases

## Phase 0 — controlled architecture preservation

- preserve this v3 document;
- mark v2.5 superseded, not deleted;
- preserve biometric guard separately from PR #10 runtime work;
- update durable program records;
- reconcile Linear scope.

## Phase 1 — Global Binnacle identity

- Supabase Auth;
- users;
- Rider Profiles;
- registered device keys;
- BIA token exchange;
- account/device revoke/delete.

## Phase 2 — Vision registry and ownership

- hardware_nodes;
- claim;
- admin/operator relationships;
- ownership epoch;
- Vision entitlement.

## Phase 3 — Ride Sessions

- session participants;
- dynamic Connect-displayed QR;
- mDNS discovery;
- CSTs;
- Active Rider / Rider Runs;
- 60-minute session recovery;
- honest Track reacquisition.

## Phase 4 — Guest-to-Global

- Guest Session ID;
- mandatory two-form Claim Code architecture;
- short boat-local Claim Code;
- long hashed remote Cloud Claim Code;
- hard 30-day Claim Code expiration;
- Guest Highlights;
- later claim into Global Binnacle Account.

## Phase 5 — Media and Library

- Session Master;
- Cloud Media Assets;
- personal Library Pointers;
- participant Highlights;
- Snapshot/Highlight semantics;
- independent retention;
- deduplication.

## Phase 6 — Privacy/takedown

- takedown workflow;
- restricted pending state;
- 48-hour target;
- maximum 5 user-initiated open/pending requests;
- signed Takedown Hash List;
- Vision local purge/erase receipts;
- derived-media propagation.

## Phase 7 — Entitlements

- Vision Hardware Entitlements;
- Global Account Entitlements;
- trials;
- downgrade/grace behavior;
- cost model validation.

## Phase 8 — Spotter Recognition

Synthetic/test environments only until all production legal/privacy gates are satisfied.

---

# 38. Open items before implementation freeze

1. Bootstrap and verify biometric guard on `main`.
2. Add second independent privacy admin before production biometric work.
3. Obtain formal legal/privacy review for Spotter Recognition.
4. Define exact session privacy modes for participant Snapshots/Highlights.
5. Define exact personal and Vision retention durations by tier.
6. Define payment-failure/grace periods.
7. Complete Cloudflare Stream/R2 cost and operational spikes.
8. Define Support SOP for ownership disputes, stolen units and takedowns.
9. Decide repository/document visibility for sensitive security and commercial architecture.
10. Define exact Rider Run UI and who may change the Active Rider.
11. Define exact session-recovery persistence format and crash-safety requirements.
12. Define precise Cloud/Connect behavior when a recovered session exceeds the 60-minute window.
13. Reconcile older Device Pairing and Authorization design with v3.
14. Reconcile older approved Cloud architecture documents containing superseded provider/account wording.
15. Ensure older AWS IVS/MediaLive references are clearly marked historical/superseded where they could mislead implementation work.

---

# 39. Controlled-document migration notes

When this v3 architecture is preserved:

### Preserve as historical

`docs/evidence/CORE_USER_ACCOUNT_API_PROPOSAL.md`

Add a clear header indicating:

> **SUPERSEDED — See `docs/architecture/BINNACLE_IDENTITY_SESSION_MEDIA_ARCHITECTURE_v3.md`. Retained for design-history evidence.**

Do not rewrite history inside the old v2.5 document.

### Do not import blindly from PR #10

PR #10 contains runtime Library/Community/Live implementation that conflicts with newer Connect work.

Preserving this architecture does **not** authorize importing that runtime code.

Architecture/security documentation and runtime feature reconciliation remain separate work.

### Durable records

After v3 is accepted, update:

- Master Work Register v3.0 — Decision Register
- Master Work Register v3.0 — Evidence Index
- Master Work Register v3.0 — Linear Map
- Master Work Register v3.0 — Change Log
- approved Connect/Cloud architecture document
- applicable Linear issues

---

# 40. Final controlling principles

1. One human has one portable Global Binnacle Account.
2. A Rider Profile is optional and follows the person, not a boat.
3. Phones are individually registered/revocable devices.
4. Vision hardware has its own permanent identity and ownership lifecycle.
5. Hardware administration is different from Crew participation.
6. Ride Session access is temporary.
7. Active Rider is explicit and separate from Crew membership.
8. Connect can display Vision-generated dynamic Join QR codes.
9. Sessions survive ordinary disconnects and bounded Vision interruptions.
10. Track recovery is truthful: identity may persist while visual tracking reacquires.
11. Every admitted participant may independently capture permitted Snapshots and Highlights.
12. Session Master, Cloud Media Asset and Library Pointer are different concepts.
13. Vision ownership does not automatically confer permanent personal ownership of every rider clip.
14. Ordinary personal deletion does not destroy someone else's valid copy.
15. Global removal uses privacy/takedown controls.
16. A user may have no more than 5 simultaneous open/pending user-initiated takedown requests.
17. Vision and personal entitlements are separate.
18. Spotter Recognition is optional, consent-controlled, session-scoped and legally gated.
19. Hardware sale does not transfer Rider identities or personal Libraries.
20. Losing a phone does not mean losing the Binnacle identity.
21. A factory reset cannot be used to steal ownership.
22. Guest-to-Global claims use mandatory short-local and long-remote Claim Codes with a 30-day expiration.
23. AWS IVS and AWS MediaLive are deprecated; Cloudflare Stream is the controlling live pipeline.
