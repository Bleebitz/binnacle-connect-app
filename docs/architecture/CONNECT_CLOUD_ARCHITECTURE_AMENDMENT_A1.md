# Connect Cloud, Live & Subscription Architecture — Amendment A1

**Amends:** *Binnacle Connect Cloud, Live & Subscription Architecture v0.1*
(controlled Google Doc, approved 2026-09-16).
**Status:** Owner-directed change of direction, 2026-09-18. Recorded here
because the controlled document cannot be edited from the engineering tooling
(the Drive connector only renames/moves files). **Someone with edit rights
should paste sections 1-3 into the v0.1 document and mark the superseded
sections.**
**Applies to:** BIN-39, BIN-48; touches BIN-41, BIN-43, BIN-46.

---

## 1. What changes

| v0.1 says | Amendment A1 says |
|---|---|
| 4.4 / decision 17 / 26.13: **Cloudflare Stream** is the preferred live ingest, playback and fan-out candidate | **AWS IVS** is the live ingest and Binnacle Live playback provider |
| 26.1-26.13: **AWS S3** (durable media), **CloudFront** (Library delivery), **MediaConvert** (standard transcoding) | **Cloudflare R2** is the durable media store. Delivery and standard transcoding are **not yet decided** (section 3, gaps 5-6) |
| 26.4-26.5: S3 Lifecycle, Intelligent-Tiering, Glacier / **Deep Archive** for Binnacle Archive | R2 lifecycle rules (Standard to Infrequent Access, expiry). **Deep-archive tier does not exist on R2** (gap 7) |
| Identity (sections 14, 16) unspecified | **Supabase Auth** (Postgres-backed) plus a small Binnacle token service (see `docs/evidence/CORE_USER_ACCOUNT_API_PROPOSAL.md`) |

**Unchanged:** the product principle (Live, Cloud, Create); one boat uplink
with cloud fan-out (4.1-4.2); SRT tested first with RTMPS fallback (4.3);
truthful state (18); tiers and pricing targets (11); privacy modes (15);
private-by-default media and short-lived authorized delivery (26.8); the
media separation into original / playback / preview / Enhance / AI Cinematic /
metadata (26.2-26.3, 26.9); the Track-guided GPU processing boundary (26.7).

## 2. Owner rationale (as stated)

- **Storage, Cloudflare R2 instead of AWS S3.** A margin decision. Users will
  repeatedly download and stream 1080p highlights to phones; S3-side egress
  fees would erode margin on the approximately $5.99/month Ride tier. R2 has no
  egress fee.
- **Live, AWS IVS instead of Cloudflare Stream.** Marine cellular bandwidth is
  volatile. IVS is chosen for low-latency ingest and multitrack capability, so
  the Vision unit can degrade upload quality without dropping the stream.
- **Identity, Supabase Auth instead of Cognito.** Clean fit with a PostgreSQL
  backend, more flexible edge functions, smooth modern OAuth.

## 3. Verification against current provider documentation (2026-09-18)

Checked, with what it means for the plan:

| Claim | Finding | Source area |
|---|---|---|
| R2 has no egress fee | **Confirmed.** Storage $0.015/GB-month Standard, $0.01 Infrequent Access (30-day minimum, retrieval fee); Class A $4.50 and Class B $0.36 per million operations | Cloudflare R2 pricing |
| R2 can do authorized short-lived access | **Yes** via presigned URLs on the S3-compatible API. Whether presigned URLs work on custom domains (needed for branded playback URLs) is **to verify**; a Cloudflare Worker that checks the Binnacle token is the fallback | R2 docs |
| IVS accepts SRT | **Yes.** Low-Latency channels accept RTMPS, RTMP and SRT (H.264). The SRT-first test in BIN-39 is still possible | IVS Low-Latency guide |
| IVS multitrack lets the unit degrade upload without dropping the stream | **Not as documented.** E-RTMP multitrack lets an encoder publish several renditions in one stream so *viewers* can adapt. It raises the uplink requirement rather than lowering it. Graceful uplink degradation has to come from the Vision encoder's own rate control over SRT, and is provider-independent. Whether the unit can shed the upper tracks under congestion while the lowest survives is **unproven**; BIN-39 must test it | IVS multitrack video guide |
| IVS can fan out to YouTube/Facebook/Twitch | **No native restream/simulcast found in IVS documentation.** Cloudflare Stream does have it (up to 50 outputs per live input). This breaks a v0.1 acceptance principle unless a fan-out component is added (gap 1) | IVS docs; Cloudflare Stream docs |
| IVS ingest credentials are scoped and expiring (BIN-46) | **Not natively.** A Low-Latency channel has one long-lived stream key (bearer secret). Mitigation: rotate the key per session (delete + create, documented rate limit 5 per second) and remove it at session end. IVS Real-Time stages use expiring participant tokens and are a candidate to evaluate | IVS API/quotas |
| IVS quotas | 1 stream key per channel; default 5,000 channels per region (adjustable) | IVS service quotas |
| Supabase can issue the 14-day offline token | **No.** The documented maximum JWT lifetime is one week. A Binnacle token service is required, as already approved | Supabase docs |

## 4. Gaps this amendment creates (each needs an owner and a BIN-39 / BIN-48 task)

| # | Gap | Why it matters | Options to evaluate | Proving test |
|---|---|---|---|---|
| 1 | **External fan-out.** IVS has no documented native restream | v0.1 acceptance: one boat uplink reaches Binnacle Live *and* external destinations; free/paid destination counts | (a) Binnacle-run restreamer (SRT in from Vision, RTMPS out to IVS and to external platforms); (b) a managed component such as AWS Elemental MediaLive fed from IVS; (c) keep Cloudflare Stream only for external simulcast; (d) third-party multistream service. Sending N uplinks from the boat is excluded by principle 4.1 | One real Vision stream reaches IVS and one external destination with a single boat uplink; per-destination state stays independent |
| 2 | **Uplink degradation.** Multitrack does not do what the rationale assumes | The stated reason for choosing IVS | Vision encoder adaptive bitrate over SRT (provider-independent); multitrack with a low-rate lowest track as a bonus; measure both | Throttle the uplink 5 Mbps to 500 kbps to 5 Mbps: the stream never drops, the viewer sees lower quality, recovery time recorded |
| 3 | **Ingest authorization** | BIN-46 requires scoped/expiring ingest | Per-session channel or key rotation with deletion at session end; evaluate IVS Real-Time expiring tokens | A leaked stream key from an ended session is rejected; a key is never present on the phone |
| 4 | **Private/shared/public playback** on IVS | BIN-40 privacy modes | Evaluate IVS private channels with playback authorization tokens (verify current capabilities) | A viewer without a valid token cannot play; an expired token stops playing |
| 5 | **Live archive location.** IVS recording is written to AWS S3 as far as I know (verify) | Recordings would land on S3, not R2, reintroducing an AWS bucket | A staging S3 bucket, then a one-time copy to R2 (S3 egress charged once per recording, not per view); cost it in BIN-43 | A recorded session appears in R2 with a matching checksum; staging object expires |
| 6 | **Standard transcoding and delivery.** MediaConvert works on S3 (verify inputs/outputs); CloudFront was the delivery layer | Proxy/compatibility derivatives and authorized playback need a new path | Delivery: R2 presigned URLs or a Worker that verifies the Binnacle token and the rider's pointer. Transcoding: MediaConvert with S3 staging (costed), or Binnacle compute workers running FFmpeg, or another managed transcoder | A 4K source yields a playable 1080p proxy in R2; an unauthorized request is refused |
| 7 | **Binnacle Archive.** R2 has Standard and Infrequent Access only | v0.1 26.4-26.5 assumed Glacier/Deep Archive at about $1/TB-month | Re-scope Archive to R2 Infrequent Access ($0.01/GB-month), or copy cold media to an AWS Glacier class with retrieval costs | Cost per archived TB-year modelled for both; restore time/cost measured before any commercial Archive offer |
| 8 | **Three vendors** (Cloudflare, AWS, Supabase) | Operations, security review, billing, incident response | Document ownership, credentials and on-call for each; single secrets policy | Runbook and access review |

## 5. Effects on other issues

- **BIN-39** (live uplink): validation target becomes IVS; add a fan-out spike
  (gap 1) and an uplink-degradation test (gap 2). Exit criterion unchanged.
- **BIN-48** (storage): validation target becomes Cloudflare R2. Rewrite exit
  criteria 1-9 for R2 (private bucket, checksum, presigned access,
  unauthorized access blocked, lifecycle rules, asset-class separation,
  Infrequent Access restore behavior, costs including operation fees) and add
  the delivery/transcoding decision (gap 6) and the archive re-scope (gap 7).
- **BIN-41:** unchanged behavior; storage and lifecycle references move to R2.
  Media is stored once and shared through per-rider pointers, so object keys
  are per asset, not per user.
- **BIN-43** (unit economics): replace the S3, CloudFront and MediaConvert
  lines with R2 storage and operations, IVS hourly input/output, fan-out
  component, staging-bucket transfer, and presigned-URL/Worker requests. Model
  the egress savings against a stated playback volume per subscriber, since the
  margin rationale depends on that number.
- **BIN-46:** provider authorization and stream keys stay in a cloud secret
  store; IVS keys are rotated per session (gap 3).

## 6. Decision record

| Date | Decision | By |
|---|---|---|
| 2026-09-18 | Durable media on Cloudflare R2 (replaces S3 direction) | Owner |
| 2026-09-18 | Live ingest and Binnacle Live playback on AWS IVS (replaces Cloudflare Stream direction) | Owner |
| 2026-09-18 | Identity provider: Supabase Auth, plus a Binnacle token service for the 14-day offline token | Owner |

v0.1's own rule for this kind of change (section 23) applied: provider
selection was an open implementation parameter. Because this reverses the
named preferred providers in decision 17 and section 26, it is recorded as an
amendment rather than a silent edit.
