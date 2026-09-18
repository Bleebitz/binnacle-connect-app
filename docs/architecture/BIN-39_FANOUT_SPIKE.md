# BIN-39 Spike — Cloudflare Stream Live Pipeline

**Status:** approved and ready to run; **blocked on credentials.** No stream has
been run yet, and nothing in this document is a measured result. The owner will
provision Cloudflare API tokens through the team's secrets manager (GitHub
Secrets, Doppler or Vault). Until they exist I cannot start.

**Supersedes** the earlier fan-out comparison. On 2026-09-18 the owner dropped
AWS IVS and chose Cloudflare Stream for the whole live pipeline, so MediaLive
and Restream are no longer being evaluated. Why (from the cost work in
`CONNECT_CLOUD_ARCHITECTURE_AMENDMENT_A1.md`): AWS's own MediaLive examples run
$2.37-$3.94 per hour, and Cloudflare bills simulcast about $0.06 per output-hour.

## 1. Approved parameters

| Item | Decision (owner, 2026-09-18) |
|---|---|
| Constraint | The Vision unit pushes **one SRT uplink** only |
| Pipeline | Cloudflare Stream for **SRT ingest, multi-destination fan-out, and HLS/DASH viewer playback** |
| Cost pass/fail | Total live cost (ingest + fan-out + playback) **<= 20% of the tier's monthly revenue**: about $1.20 Ride, $2.40 Creator, $4.00 Creator+ |
| Spend cap | **$50** for the spike |
| Test destinations | Project-owned **private/unlisted** test channels (for example an unlisted YouTube test channel and a private Twitch test account). **No public-facing Binnacle marketing channels** |
| Credentials | Owner provisions Cloudflare API tokens in the secrets manager. **Nothing hard-coded in the repo, logs or chat** |
| Test media | Project-owned **synthetic** video only for the first pass |
| Broadcast approval | No public broadcast without explicit approval of destination and content |

## 2. Cost model under test

Published pricing: live input and encoding are **free**; delivery is **$1 per
1,000 minutes**, and it covers viewer playback **and simulcast outputs**;
storage is **$5 per 1,000 minutes** per month. WebRTC delivery starts being
billed **2026-10-15**.

> live cost per hour = **$0.06 x (external outputs + concurrent Binnacle Live viewers)**

| Tier (cap at 20%) | Live hours per month the cap allows |
|---|---|
| Ride, 1 output | 20.0 with no viewers; 6.7 with 2 viewers; 3.3 with 5 |
| Creator, 3 outputs | 13.3 with no viewers; **8.0 with 2 viewers**; 5.0 with 5; 3.1 with 10 |
| Creator+, 5 outputs + 5 viewers | 6.7 |

So an 8-hour Creator user passes only at about two concurrent Binnacle Live
viewers or fewer. **The spike must confirm the metering assumption** (each
output and each viewer billed as one delivered stream) with the vendor's real
billing, because everything above rests on it. The Free tier has no revenue and
needs its own quota.

## 3. What the spike must prove

| # | Test | Method | Pass |
|---|---|---|---|
| 1 | One uplink | One SRT stream from a synthetic source to a Stream live input | Measured upload equals a single stream |
| 2 | Fan-out | Simulcast outputs to 2+ private test destinations, plus Stream playback | Each output reaches its destination |
| 3 | Isolation and truthful state | Break one output (wrong key) while others run | The others are undisturbed; each output reports its own state |
| 4 | Metering | Compare Stream billing/analytics with the section 2 formula after a known run | Within a stated tolerance; formula corrected if not |
| 5 | Latency | Timestamped test pattern, source clock vs each output and vs Stream HLS/DASH playback (and WebRTC if enabled) | Report median and p95 for each; owner sets thresholds after seeing them |
| 6 | Uplink loss | Throttle 5 Mbps to 500 kbps to 5 Mbps, then a 60 s cut | Stream does not drop; recovery time recorded; state stays truthful |
| 7 | Start-up | GO LIVE to first frame at each destination | Recorded (proposed target 30 s) |
| 8 | Per-session live inputs | Create a live input per session through the API and delete it at shutdown | Rate limits and quotas recorded; a deleted input's credentials are refused |
| 9 | Private playback | Stream signed URLs for private/shared playback | Without a valid token playback fails; an expired token stops it |
| 10 | Recording to R2 | Confirm Stream records the live input; download the MP4; copy to R2; delete the Stream copy | R2 checksum matches; Stream storage released |
| 11 | Terms and scale | Read Cloudflare's terms for multi-tenant/customer use; note live-input and concurrency quotas | Permitted; quota supports at least 1,000 concurrent sessions or a path to it |
| 12 | Real Vision unit | Repeat 1, 2, 6 with the Vision unit on a phone hotspot | BIN-39 exit criterion |

Source, sent as one SRT stream (placeholders only):
```
ffmpeg -re -f lavfi -i testsrc2=size=1920x1080:rate=30 -f lavfi -i sine=frequency=440 \
  -c:v libx264 -b:v 6M -g 60 -c:a aac -f mpegts "srt://<ingest-host>:<port>?streamid=<id>&passphrase=<from-secrets>&latency=1500"
```

## 4. Running it safely

- **Where it runs.** This repository is **public**. Do not run the spike from
  public-repo GitHub Actions with the Cloudflare token. Run it from a private
  location (a private repo, a local machine, or a container) with the token
  injected at runtime by Doppler/Vault, and scope the token to the minimum
  permissions (Stream and R2 only, one account).
- **Spend.** Set a billing alert well below $50 and stop the spike at $50. The
  metering test (4) is small by design.
- **Credentials.** Tokens and stream keys never appear in code, logs,
  screenshots or evidence; redact before saving output.
- **Destinations.** Private/unlisted only. If a destination cannot be private,
  ask before using it.

## 5. Deliverable

A results table for section 3, the measured cost per live hour and the
corrected formula, the latency figures for owner-set thresholds, and an updated
cost input for BIN-43 (including the Free-tier quota). Exit criterion is
unchanged from BIN-39.

## 6. Still needed from the owner

1. The Cloudflare API tokens in the secrets manager, plus the account and
   zone identifiers the spike should use. Tell me where they are and how they
   are injected.
2. The names of the private test destinations (for example the unlisted YouTube
   channel and the private Twitch account) and confirmation they are ready.
3. Latency thresholds once the first measurements exist.

## 7. Transcoding follow-on (BIN-48)

Separate from live: VOD playback uses Stream's native encoding. If AI highlight
generation needs custom FFmpeg before upload, evaluate ephemeral containers
orchestrated by the backend (AWS Fargate, DigitalOcean App Platform, or
Cloudflare Containers). Workers cannot run FFmpeg. Compare per-source-hour cost
and per-viewing-hour cost of Stream VOD (about $0.06 per viewing hour, about
$0.30 per stored hour per month) with an R2-served HLS pipeline (R2 has no egress
fee, about $0.04 per stored hour per month at 6 Mbps).
