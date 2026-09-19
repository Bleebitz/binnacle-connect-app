# Rider track evidence

- `dev-overlays/` — the shipped `gopro_dev_rider_track_v1.json` drawn (via
  `tools/demo_track/verify_overlay.py`) over exact frames of the controlled Demo
  footage, every 2 s from 1 s to 123 s (red = visible, amber = coasting).
- `s25/` — screenshots from the Samsung Galaxy S25 Ultra running the Demo build.

Demo annotation only: a hand-read spatial track for one controlled recording. Not
live detection, AI inference, Jetson tracking, or Core Rider Lock.
