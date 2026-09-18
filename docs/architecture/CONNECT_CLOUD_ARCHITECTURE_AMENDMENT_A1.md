# Connect Cloud, Live & Subscription Architecture — Amendment A1 (revision 3)

**Amends:** *Binnacle Connect Cloud, Live & Subscription Architecture v0.1*
(controlled Google Doc, approved 2026-09-16).
**Status:** Owner-directed change of direction, 2026-09-18. Recorded here
because the controlled document cannot be edited from the engineering tooling
(the Drive connector only renames/moves files). **Someone with edit rights
should paste sections 1-2 into the v0.1 document and mark the superseded
sections.**
**Applies to:** BIN-39, BIN-48; touches BIN-41, BIN-43, BIN-46.
**Revision history:** rev 1 chose AWS IVS for live and Cloudflare R2 for media.
Rev 2 scoped a fan-out spike. **Rev 3 drops AWS IVS entirely** after the
fan-out cost analysis and returns live to Cloudflare Stream.

---

## 1. What changes

| v0.1 says | Amendment A1 (rev 3) says |
|---|---|
| 4.4 / decision 17 / 26.13: **Cloudflare Stream** is the preferred live ingest, playback and fan-out candidate | **Cloudflare Stream is the baseline for the entire live pipeline**: SRT ingest, multi-destination fan-out (simulcast), and HLS/DASH viewer playback. This restores the v0.1 live direction. **AWS IVS is dropped**, and so is any AWS ingest layer |
| 26.1-26.13: **AWS S3**, **CloudFront**, **MediaConvert** | **Cloudflare R2** is the durable media store. CloudFront and MediaConvert are out |
| Standard transcoding (26.6) | **Cloudflare Stream's native encoding** for on-demand (VOD) playback. Custom FFmpeg only if AI highlight generation needs it before upload: **ephemeral containers** (AWS Fargate, DigitalOcean App Platform, or Cloudflare Containers) orchestrated by the backend. Not Workers (they cannot run FFmpeg) |
| 26.4-26.5: Lifecycle, Glacier / **Deep Archive**, Binnacle Archive | **Dropped from scope.** Creator+ gets 1-year retention on standard R2; permanent archival is the user downloading their MP4s |
| Identity (sections 14, 16) unspecified | **Supabase Auth** plus a small Binnacle token service (`docs/evidence/CORE_USER_ACCOUNT_API_PROPOSAL.md`) |

**Unchanged:** the product principle (Live, Cloud, Create); one boat uplink with
cloud fan-out (4.1-4.2); SRT first with RTMPS fallback (4.3); truthful state
(18); tiers and pricing targets (11); privacy modes (15); private-by-default
media and short-lived authorized delivery (26.8); media separation into
original / playback / preview / Enhance / AI Cinematic / metadata (26.2-26.3,
26.9); the Track-guided GPU processing boundary (26.7).

## 2. Owner rationale (as stated)

- **Storage, R2 instead of S3:** margin. Users repeatedly stream 1080p
  highlights to phones; S3-side egress would erode margin on the ~$5.99 Ride
  tier. R2 has no egress fee.
- **Live, Cloudflare Stream instead of IVS:** the margin math. Fan-out through
  AWS MediaLive costs $2.40+ per hour, which an 8-hour live user would turn into
  a loss on the Creator tier. Cloudflare Stream handles ingest, simulcast and
  adaptive-bitrate playback natively, removing the separate AWS ingest layer.
- **Live cost rule:** total live cost (ingest + fan-out + playback) must not
  exceed **20% of the tier's monthly revenue**: about $1.20 (Ride), $2.40
  (Creator), $4.00 (Creator+).
- **Identity, Supabase Auth:** fit with a PostgreSQL backend, edge functions,
  modern OAuth.

## 3. Verification against current provider documentation (2026-09-18)

| Claim | Finding | Source area |
|---|---|---|
| R2 has no egress fee | **Confirmed.** Storage $0.015/GB-month Standard; Class A $4.50 and Class B $0.36 per million operations. Presigned URLs work on the S3-compatible API; custom-domain presigning is **to verify** | Cloudflare R2 pricing/docs |
| Cloudflare Stream covers the live pipeline | **SRT and RTMPS ingest; up to 50 simulcast outputs per live input over RTMPS or SRT; HLS/DASH playback.** Live input and encoding are **free** | Cloudflare Stream docs/pricing |
| Stream billing | **$1 per 1,000 minutes delivered**, where delivery includes viewer playback (HLS/DASH, MP4) **and simulcast outputs**; storage **$5 per 1,000 minutes** of capacity per month. **WebRTC delivery starts being billed on 2026-10-15** | Cloudflare Stream pricing page |
| Stream outputs can target any RTMPS endpoint | Yes per the docs; behaviour with each platform is to be measured | Stream simulcast docs |
| *(evaluated and dropped)* IVS can fan out to external platforms | **No native restream found in IVS documentation.** IVS does accept RTMPS, RTMP and SRT | IVS docs |
| *(evaluated and dropped)* MediaLive as the fan-out engine | Accepts SRT input and has RTMP/RTMPS output groups, but **re-encodes** each output. AWS's own pricing examples: **$2.37/hour** (single pipeline) to **$3.94/hour** (standard) for 2 HD inputs and 5 outputs | AWS MediaLive pricing page |
| *(evaluated and dropped)* IVS multitrack lets the unit degrade upload | **Not as documented.** E-RTMP multitrack publishes several renditions so *viewers* adapt, and raises the uplink. Graceful uplink degradation must come from the Vision encoder's rate control over SRT, whatever the provider | IVS multitrack guide |
| Restream's SRT ingest | Business plan, **$239/month per account**; not evaluated further | Restream pricing page |
| Workers can run FFmpeg | **No.** 128 MB memory, tight CPU limits, and `ffmpeg.wasm` cannot be compiled at runtime. Native FFmpeg needs a container host | Cloudflare Workers limits; community reports |
| Supabase can issue the 14-day offline token | **No.** Documented maximum JWT lifetime is one week. The Binnacle token service is required, as approved | Supabase docs |

## 4. The 20% live-cost rule, worked through

Published Stream billing charges **$1 per 1,000 delivered minutes** = **$0.06
per stream-hour**. I assumed each simulcast output and each viewer counts as one
delivered stream (**verify with real metering in the spike**), so:

> live cost per hour = **$0.06 x (external outputs + concurrent Binnacle Live viewers)**;
> ingest is free.

Cap per tier at 20% of monthly price, and what it allows:

| Tier (price) | Cap | Stream-hours allowed | Example | Live hours per month at the cap |
|---|---|---|---|---|
| Ride ($5.99) | $1.20 | 20 | 1 output, 0 viewers | 20.0 |
| Ride | | | 1 output + 2 viewers | 6.7 |
| Ride | | | 1 output + 5 viewers | 3.3 |
| Creator ($11.99) | $2.40 | 40 | 3 outputs, 0 viewers | 13.3 |
| Creator | | | **3 outputs + 2 viewers** | **8.0** |
| Creator | | | 3 outputs + 5 viewers | 5.0 |
| Creator | | | 3 outputs + 10 viewers | 3.1 |
| Creator+ ($19.99) | $4.00 | 66.6 | 5 outputs + 5 viewers | 6.7 |

**What this means.** An 8-hour-a-month Creator user with three external
destinations passes only if the average audience on Binnacle Live is about two
concurrent viewers or fewer. Bitrate is not a cost lever, because billing is per
minute. The real levers are quotas on live hours and on viewer-minutes, a cap on
concurrent outputs, HLS versus WebRTC (whose price starts 2026-10-15), and
negotiated volume pricing. **The Free tier has no revenue, so the 20% rule does
not cover it and it needs its own hard quota.**

Storage side effects to model in BIN-43:
- Stream VOD storage is about **$0.30 per stored hour per month**; R2 is about
  **$0.04** for an hour of 6 Mbps video (roughly 7x cheaper). Live recordings kept
  in Stream cost more the longer they stay, so copy them to R2 and delete the
  Stream copy.
- R2's zero-egress advantage applies only when playback is served **from R2**.
  Playback served through Stream is billed at $0.06 per viewing hour: 5 hours of
  highlights a month is about 5% of the Ride price, 20 hours is about 20%.

## 5. Open engineering items (each has a spike or a verification)

| # | Item | Plan | Proving test |
|---|---|---|---|
| 1 | **Fan-out is native to Stream** | BIN-39 spike (`BIN-39_FANOUT_SPIKE.md`): SRT in, private test destinations, independent per-output state | One SRT uplink reaches 2+ private destinations and Stream playback; a failed output does not disturb the others; billing matches the section 4 model |
| 2 | **Uplink degradation** | Vision-side adaptive bitrate over SRT (provider-independent) | Throttle 5 Mbps to 500 kbps to 5 Mbps: the stream never drops, recovery time recorded |
| 3 | **Ingest authorization** | Create a live input per session via the API and delete it at shutdown (owner-approved key rotation/destruction, applied to Stream); verify quotas and rate limits | A credential from an ended session is rejected; none reaches a phone |
| 4 | **Private / shared / public playback** (BIN-40) | Stream signed URLs (verify) | A viewer without a valid token cannot play; an expired token stops playback |
| 5 | **Live recording to R2** | Stream records a live input to VOD (verify); download the MP4, copy to R2, delete the Stream copy | The R2 object's checksum matches; Stream storage is released |
| 6 | **VOD playback** | Stream's native encoding for on-demand playback; compare with R2-served HLS produced by an ephemeral container (spike, BIN-48) | Playback works from each path; cost per hour of source, cold start and per-viewing-hour cost recorded |
| 7 | **Custom FFmpeg for AI highlights** | Only if needed: ephemeral containers orchestrated by the backend (Fargate, DigitalOcean App Platform, Cloudflare Containers) | A highlight is produced, uploaded, and its provenance recorded |
| 8 | **Vendor footprint** | Cloudflare (Stream, R2) and Supabase; a container host only if item 7 is needed (Fargate would bring AWS back in) | Runbook and access review |

## 6. Effects on other issues

- **BIN-39:** validation target is Cloudflare Stream only; the IVS and MediaLive
  comparison is closed by decision. Spike approved: **$50 cap**, private/unlisted
  test destinations, credentials supplied through the owner's secrets manager.
- **BIN-48:** validate R2; VOD via Stream or an R2-served pipeline (item 6); live
  recording to R2 (item 5); Archive out of scope; no CloudFront or MediaConvert.
- **BIN-41:** unchanged behavior; media is stored once and shared through
  per-rider pointers; object keys are per asset, not per user.
- **BIN-43:** model the section 4 formula, Stream storage and delivery, R2
  operations, the unit-owner pointer on every clip, Creator+ one-year retention
  on standard R2, and the Free-tier live quota.
- **BIN-46:** provider authorization and destination keys stay in the cloud secret
  store; per-session live inputs (item 3).

## 7. Decision record

| Date | Decision | By |
|---|---|---|
| 2026-09-18 | Durable media on Cloudflare R2 (replaces S3) | Owner |
| 2026-09-18 | Identity: Supabase Auth plus a Binnacle token service | Owner |
| 2026-09-18 | Fan-out spike authorised under a single-SRT-uplink constraint | Owner |
| 2026-09-18 | Transcoding: not Workers; ephemeral containers if custom FFmpeg is needed | Owner |
| 2026-09-18 | Binnacle Archive / Deep Archive dropped; Creator+ 1 year on standard R2 | Owner |
| 2026-09-18 | **Drop AWS IVS entirely; Cloudflare Stream for the whole live pipeline (SRT ingest, fan-out, HLS/DASH playback)** | Owner |
| 2026-09-18 | **Live cost (ingest + fan-out + playback) must not exceed 20% of the tier's monthly revenue** | Owner |
| 2026-09-18 | VOD via Stream's native encoding; ephemeral containers only for custom FFmpeg | Owner |
| 2026-09-18 | Spike spend cap $50; private test destinations approved; credentials via the owner's secrets manager, never in the repo | Owner |
