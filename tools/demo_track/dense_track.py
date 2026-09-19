#!/usr/bin/env python3
"""Turns the sparse hand-read keyframes into a dense (0.25 s) rider track.

DEV TOOLING ONLY (needs `pip install opencv-contrib-python-headless`). The app
never runs this; it ships only the JSON that build_track.py writes.

Why: the wakesurfer weaves sideways by ~100 px within a second, so boxes read every
2-3 s cannot follow the motion between them. Method, per segment between two hand-read
keyframes A and B:
  1. start an OpenCV CSRT tracker on the hand-read box at A and run it to B;
  2. measure how far its centre is from the hand-read centre at B and spread that
     error linearly back across the segment (so the track is exactly the hand-read
     box at every keyframe and cannot drift);
  3. take the box SIZE from the hand-read sizes (linear between keyframes), because a
     tracker's box shrinks and grows arbitrarily.
Occluded/unknown keyframes are copied through unchanged.

    python tools/demo_track/dense_track.py
"""
import json, os
import cv2

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
VIDEO = os.path.join(ROOT, 'flutter_app', 'assets', 'demo', 'gopro_dev_footage.mp4')
FPS = 30
STEP_S = 0.25
S = 0.5  # the tracker runs on half-resolution frames


def centre(b):
    return ((b[0] + b[2]) / 2, (b[1] + b[3]) / 2)


def main():
    kfs = json.load(open(os.path.join(HERE, 'keyframes_manual_px.json')))['keyframes']
    vis = [k for k in kfs if k['state'] == 'visible']
    start_frames = {round(k['t'] * FPS): k for k in vis}
    end_frame = round(vis[-1]['t'] * FPS)
    per_frame = {}  # frame -> [cx, cy] raw tracker centre
    errs = {}       # keyframe frame -> (ex, ey) measured just before re-seeding
    cap = cv2.VideoCapture(VIDEO)
    tracker = None
    i = 0
    last = None
    while i <= end_frame:
        ok, fr = cap.read()
        if not ok:
            break
        small = cv2.resize(fr, None, fx=S, fy=S, interpolation=cv2.INTER_AREA)
        k = start_frames.get(i)
        if tracker is not None and last is not None:
            ok2, bb = tracker.update(small)
            if ok2:
                x, y, w, h = bb
                last = ((x + w / 2) / S, (y + h / 2) / S)
            per_frame[i] = last  # lost frames hold the previous centre
        if k is not None:
            if i in per_frame:
                mc = centre(k['box'])
                errs[i] = (mc[0] - per_frame[i][0], mc[1] - per_frame[i][1])
            b = k['box']
            tracker = cv2.TrackerCSRT_create()
            tracker.init(small, tuple(int(round(v)) for v in (b[0] * S, b[1] * S, (b[2] - b[0]) * S, (b[3] - b[1]) * S)))
            last = centre(b)
            per_frame[i] = last
        i += 1
    cap.release()

    # Segment-wise linear error correction.
    kf_frames = sorted(start_frames)
    corrected = {}
    for a, b in zip(kf_frames, kf_frames[1:]):
        ex, ey = errs.get(b, (0, 0))
        for f in range(a, b):
            u = (f - a) / (b - a)
            cx, cy = per_frame[f]
            corrected[f] = (cx + ex * u, cy + ey * u)
    last_f = kf_frames[-1]
    corrected[last_f] = centre(start_frames[last_f]['box'])

    def size_at(t):
        for a, b in zip(vis, vis[1:]):
            if a['t'] <= t <= b['t']:
                u = (t - a['t']) / (b['t'] - a['t'])
                wa, ha = a['box'][2] - a['box'][0], a['box'][3] - a['box'][1]
                wb, hb = b['box'][2] - b['box'][0], b['box'][3] - b['box'][1]
                return wa + (wb - wa) * u, ha + (hb - ha) * u
        k = vis[-1]
        return k['box'][2] - k['box'][0], k['box'][3] - k['box'][1]

    out = []
    n = int(vis[-1]['t'] / STEP_S) + 1
    hand = {round(k['t'] * FPS) for k in vis}
    times = sorted({round(j * STEP_S, 3) for j in range(n + 1) if j * STEP_S <= vis[-1]['t']} | {k['t'] for k in vis})
    for t in times:
        f = round(t * FPS)
        cx, cy = corrected[f]
        w, h = size_at(t)
        out.append({'t': t, 'state': 'visible', 'box': [round(cx - w / 2, 1), round(cy - h / 2, 1),
                                                          round(cx + w / 2, 1), round(cy + h / 2, 1)]})
    out += [k for k in kfs if k['state'] != 'visible']
    json.dump({'keyframes': out}, open(os.path.join(HERE, 'keyframes_px.json'), 'w'), separators=(',', ':'))
    print('dense visible keyframes:', sum(1 for k in out if k['state'] == 'visible'), 'total', len(out))


if __name__ == '__main__':
    main()
