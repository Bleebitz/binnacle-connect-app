# BIN-39 Spike — Live Fan-Out Engine

**Status:** spike defined and desk-researched 2026-09-18. **No stream has been
run yet.** Running it needs accounts, a spend cap and test destinations that only
the owner can create or approve (section 7). Nothing here is a measured result.

**Owner-set constraint (strict):** the Vision unit pushes **one SRT uplink**,
nothing more, to conserve volatile cellular bandwidth. Any design that makes the
unit send a second copy anywhere is out.

**Owner-set evaluation order:**
1. Compare **AWS Elemental MediaLive** (stays inside AWS) with a **managed
   third-party API** (Restream.io named as the example).
2. If both introduce unacceptable margin bloat or latency, evaluate
   **Cloudflare Stream strictly as the external simulcast engine**.

## 1. Why this spike exists

Amendment A1 moved live to AWS IVS. IVS has no documented native restream to
YouTube, Facebook or Twitch, so a component is needed that takes the single
SRT uplink and fans it out to (a) IVS for Binnacle Live and (b) each external
destination.

## 2. Candidate architectures

```
A. MediaLive      Vision --SRT--> MediaLive (SRT input) --RTMPS--> IVS
                                                          --RTMPS--> YouTube / Facebook / Twitch / custom

B. Managed 3rd    Vision --SRT--> vendor ingest ----------RTMPS--> IVS + externals
   party API

C. Cloudflare     Vision --SRT--> Cloudflare Stream live input
   Stream                         --live outputs (RTMPS/SRT)--> IVS + externals
   (fallback,     (Stream can also play back to viewers itself, which raises the
   simulcast      question of whether IVS is still needed in this variant: item 8)
   only)
```

Reference baseline only (not proposed, not in the owner's scope): a
Binnacle-run passthrough restreamer that copies compressed video without
re-encoding. It is included in the measurements as a floor for cost and latency,
so "unacceptable" has something to be measured against.

## 3. What the documentation says today (2026-09-18)

| Candidate | Confirmed facts | Not yet known |
|---|---|---|
| **A. MediaLive** | Accepts SRT input (caller mode since 2024; listener mode added 2026). Has RTMP, RTMPS and SRT output groups. Pay-as-you-go hourly: input rate by codec/bitrate plus one rate per output. AWS's own pricing example is **$2.3652/hour** for a single-pipeline channel (2 HD HEVC inputs, 5 outputs) and **$3.942/hour** as a standard (two-pipeline) channel. MediaLive **re-encodes** each output | Exact hourly rate for one SRT AVC 1080p input and 4 outputs (use the AWS calculator). Channel cold-start time. Quotas. Whether a channel can be created and started per session fast enough |
| **B. Managed third party (Restream)** | Business plan **$239/month** with 8 multistream channels and SRT ingest; SRT is **not** available on Free ($0), Standard ($19), or Professional ($49). Plans are per account | Whether the API can create/start a multistream server-side; whether reselling to Binnacle's own customers is allowed (each customer would otherwise need their own account); per-tenant pricing; the Restream API docs consulted describe integrations and were not conclusive |
| **B'. Comparable API-first vendor (Mux)** | SRT and RTMP ingest; simulcast targets added through the API; **$0.02 per minute per simulcast target** (about $1.20 per target-hour), from Mux's documentation summary | Terms, latency, per-tenant limits; checked only as a comparison |
| **C. Cloudflare Stream** | SRT and RTMPS ingest; up to **50 simulcast outputs** per live input over RTMPS or SRT; **live input and encoding are free**; simulcast outputs are billed as delivery at **$1 per 1,000 minutes**, which is about $0.06 per output-hour (official pricing page) | Latency added; behaviour under uplink loss; whether an output to IVS's RTMPS endpoint behaves well; independence of per-output state |
| **IVS (all variants)** | RTMPS, RTMP and SRT ingest; one stream key per channel; 5,000 channels per region by default. Input rates from third-party summaries: about $0.20/hour Basic to $2.00/hour Standard; output about $0.07-$0.14 per delivered viewer-hour | Verify against the AWS calculator; effect of channel type on multitrack |

### Order-of-magnitude margin check (illustrative, not a measurement)

Assume a Creator-tier rider (price about $11.99/month) goes live 8 hours a
month to IVS plus 3 external destinations (4 outputs). Fan-out engine only:

| Engine | Rough cost per live hour | Rough monthly cost at 8 h | vs $11.99 |
|---|---|---|---|
| Cloudflare Stream (4 outputs at $0.06/h) | about $0.24 | about $1.92 | about 16% |
| MediaLive (AWS's example range $2.37 - $3.94/h) | about $2.4 - $3.9 | about $19 - $32 | **exceeds the plan price** |
| Mux-style per-target pricing (4 targets at $1.20/h) | about $4.80 | about $38 | **exceeds the plan price** |
| Restream Business | flat $239/month per account | not comparable per rider | needs a per-tenant model |

**Note on my own threshold:** with this usage assumption even Cloudflare comes
to about 16%, which would fail the 15% figure proposed in section 4. The
assumption (8 live hours a month, 4 outputs) is mine, not the owner's, so set
the threshold and the usage profile knowing that.

These use published example rates, not the real configuration. **Hypothesis for
the spike to confirm or kill:** MediaLive and per-target managed APIs both fail
the margin test at Creator-tier usage, which would move the decision to
candidate C. The spike must price the real configuration with the AWS calculator
before that is treated as fact.

## 4. Proposed pass/fail criteria (owner to approve or change the numbers)

| # | Criterion | Proposed threshold |
|---|---|---|
| 1 | Uplink | Exactly one SRT connection from the unit; measured boat upload equals one stream |
| 2 | Added latency | Median added delay to Binnacle Live at most 3 s versus sending straight to IVS; external destinations dominated by the platform |
| 3 | Fan-out cost | At most 15% of the tier's monthly price at the stated usage profile (Ride: 1 output; Creator: 4; Creator+: to be set) |
| 4 | Start-up | GO LIVE to first frame at every selected destination within 30 s (records MediaLive channel cold start) |
| 5 | Recovery | After a 60-second uplink outage all outputs resume without operator action; the state shown is truthful throughout |
| 6 | Isolation | One destination failing (bad key, platform outage) does not disturb the others; each destination reports its own state |
| 7 | Quality | No visible degradation versus source at the target bitrate; note whether the engine re-encodes |
| 8 | Credentials | Destination keys stay server-side (BIN-46); never on a phone or in logs |
| 9 | Terms | Commercial multi-tenant use is permitted by the vendor |
| 10 | Scale | Supports at least 1,000 concurrent sessions within default or adjustable quotas |
| 11 | Ingest security | IVS stream key rotated per session and destroyed at shutdown (owner-approved 2026-09-18) |

**Decision rule (from the owner's instruction):** if A or B passes criteria 2
and 3, choose the better of them. If both fail criterion 2 or 3, evaluate C
strictly as the external simulcast engine. If C passes, adopt it for fan-out.
If C is adopted, decide the role of IVS in that design (item 8 below).

## 5. Test plan

Uses **project-owned synthetic test video only** (a generated test pattern with
a tone). No personal footage and no Vision hardware needed for the first pass.

Source, sent as one SRT stream (placeholders only, no real credentials):
```
ffmpeg -re -f lavfi -i testsrc2=size=1920x1080:rate=30 -f lavfi -i sine=frequency=440 \
  -c:v libx264 -b:v 6M -g 60 -c:a aac -f mpegts "srt://<ingest-host>:<port>?streamid=<id>&latency=1500"
```

| Step | What | Measures |
|---|---|---|
| 1 | Send one SRT stream to each candidate | Startup time, first-frame time at each output |
| 2 | Fan out to 4 **private/unlisted** test destinations owned by the owner | Per-destination state, isolation (kill one) |
| 3 | Timestamped test pattern, compare source clock with each output | Added latency (median, p95) |
| 4 | Throttle the uplink 5 Mbps to 500 kbps to 5 Mbps; then a 60 s cut | Recovery time and truthfulness of state |
| 5 | Run one hour at the target bitrate | Data use, dropped frames, cost from the vendor's billing |
| 6 | Price the real configuration | AWS calculator, Cloudflare, Restream/Mux quotes |
| 7 | Read terms for reselling / multi-tenant use | Criterion 9 |
| 8 | If C is adopted: compare IVS as an output against Stream's own playback for Binnacle Live | Role of IVS: cost, latency, private playback, whether it stays |
| 9 | Repeat step 4 with the real Vision unit and a phone hotspot | Real cellular behaviour (BIN-39 exit) |

## 6. Deliverable

A results table per candidate against section 4, the measured cost per live
hour, a recommendation, and an updated cost input for BIN-43. Exit criterion is
unchanged from BIN-39.

## 7. What I need before I can run it

I cannot create accounts or enter credentials, so these are yours:

1. AWS, Cloudflare and (if B is tested) Restream or Mux accounts, with API
   credentials supplied through a secrets store, never in code, logs or chat.
2. A **spend cap** for the spike. Suggested: $50 total, with billing alarms.
3. Your approval of the **test destinations** (private/unlisted channels you
   own) and of using the synthetic test content. No public broadcast will be
   started without explicit approval for the destination and content.
4. Numbers for section 4 (latency, cost share, start-up) if you want values
   other than the proposals.

## 8. Open design question this raises

If candidate C wins, Cloudflare Stream can also deliver HLS/WebRTC playback to
viewers, which overlaps with IVS's role in Binnacle Live. The owner chose IVS for
low-latency ingest and multitrack; the spike should record what IVS still
provides beyond Stream in that variant so the decision is made with evidence.
