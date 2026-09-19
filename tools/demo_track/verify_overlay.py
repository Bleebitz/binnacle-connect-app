#!/usr/bin/env python3
"""Draws the shipped rider track over exact frames of the Demo footage (dev evidence).

DEV TOOLING ONLY. The interpolation here mirrors DemoRiderTrack in
flutter_app/lib/core/models/rider_track.dart; test/rider_track_test.dart pins a
few interpolated values so the two cannot drift apart silently.

    python tools/demo_track/verify_overlay.py OUT.png 5,15,25 [cols]
"""
import io, json, os, subprocess, sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
VIDEO = os.path.join(ROOT, 'flutter_app', 'assets', 'demo', 'gopro_dev_footage.mp4')
TRACK = os.path.join(ROOT, 'flutter_app', 'assets', 'demo', 'gopro_dev_rider_track_v1.json')
TENSION = 0.75


def load():
    d = json.load(open(TRACK))
    return d['targets'][0]['keyframes'], d['maxInterpolationGapS'], d['source']['width'], d['source']['height']


def box_at(kfs, max_gap, t):
    """Returns (state, (cx, cy, w, h)) or (None, None)."""
    i = -1
    for j, k in enumerate(kfs):
        if k['t'] <= t:
            i = j
        else:
            break
    if i < 0:
        return None, None
    a = kfs[i]
    if a['state'] == 'unknown':
        return None, None
    ab = (a['cx'], a['cy'], a['w'], a['h'])
    if a['state'] == 'occluded':
        return 'occluded', ab
    b = kfs[i + 1] if i + 1 < len(kfs) else None
    if b is None or b['state'] != 'visible':
        return 'visible', ab
    if b['t'] - a['t'] > max_gap:
        return (None, None) if t > a['t'] else ('visible', ab)
    bb = (b['cx'], b['cy'], b['w'], b['h'])
    p = kfs[i - 1] if i > 0 and kfs[i - 1]['state'] == 'visible' and a['t'] - kfs[i - 1]['t'] <= max_gap else None
    n = kfs[i + 2] if i + 2 < len(kfs) and kfs[i + 2]['state'] == 'visible' and kfs[i + 2]['t'] - b['t'] <= max_gap else None
    dt = b['t'] - a['t']
    u = (t - a['t']) / dt
    u2, u3 = u * u, u * u * u
    h00, h10, h01, h11 = 2 * u3 - 3 * u2 + 1, u3 - 2 * u2 + u, -2 * u3 + 3 * u2, u3 - u2
    out = []
    for c in range(4):
        pa, pb = ab[c], bb[c]
        ma = ((pb - [p['cx'], p['cy'], p['w'], p['h']][c]) / (b['t'] - p['t'])) if p else (pb - pa) / dt
        mb = (([n['cx'], n['cy'], n['w'], n['h']][c] - pa) / (n['t'] - a['t'])) if n else (pb - pa) / dt
        ma *= TENSION; mb *= TENSION
        out.append(h00 * pa + h10 * dt * ma + h01 * pb + h11 * dt * mb)
    return 'visible', tuple(out)


def frame(t):
    r = subprocess.run(['ffmpeg', '-v', 'error', '-ss', '%.3f' % t, '-i', VIDEO, '-frames:v', '1',
                        '-f', 'image2pipe', '-vcodec', 'png', '-'], capture_output=True)
    return Image.open(io.BytesIO(r.stdout)).convert('RGB')


def sheet(times, out, cols=3, tile=(640, 360)):
    kfs, gap, W, H = load()
    tw, th = tile
    rows = (len(times) + cols - 1) // cols
    sh = Image.new('RGB', (cols * tw, rows * th), 'black')
    for i, t in enumerate(times):
        im = frame(t).resize((tw, th))
        d = ImageDraw.Draw(im)
        state, b = box_at(kfs, gap, t)
        if b:
            cx, cy, w, h = b
            x0, y0, x1, y1 = (cx - w / 2) * tw, (cy - h / 2) * th, (cx + w / 2) * tw, (cy + h / 2) * th
            col = (255, 40, 40) if state == 'visible' else (255, 200, 0)
            d.rectangle([(x0, y0), (x1, y1)], outline=col, width=2)
        d.rectangle([(0, th - 20), (150, th)], fill=(0, 0, 0))
        d.text((4, th - 16), 't=%.1f %s' % (t, state or 'none'), fill=(0, 255, 0))
        sh.paste(im, ((i % cols) * tw, (i // cols) * th))
    sh.save(out)


if __name__ == '__main__':
    sheet([float(x) for x in sys.argv[2].split(',')], sys.argv[1], int(sys.argv[3]) if len(sys.argv) > 3 else 3)
