#!/usr/bin/env python3
"""Builds flutter_app/assets/demo/gopro_dev_rider_track_v1.json from keyframes_px.json.

DEV TOOLING ONLY. The app ships the resulting JSON and nothing from this
directory. keyframes_px.json is a hand-read annotation of the controlled Demo
footage: for each keyframe the rider's whole-body box (head to board) was read
off full-resolution frames with a pixel grid (OpenCV CSRT was used only to centre
the review crops, never as the source of the boxes). Boxes are in SOURCE-frame
pixels here and are normalised on output, so the track is independent of any
screen, orientation or BoxFit.

    python tools/demo_track/build_track.py
"""
import hashlib, json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
ASSET = 'assets/demo/gopro_dev_footage.mp4'
ASSET_PATH = os.path.join(ROOT, 'flutter_app', ASSET)
OUT = os.path.join(ROOT, 'flutter_app', 'assets', 'demo', 'gopro_dev_rider_track_v1.json')


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def probe():
    r = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                        'stream=width,height', '-show_entries', 'format=duration', '-of', 'json', ASSET_PATH],
                       capture_output=True, text=True, check=True)
    j = json.loads(r.stdout)
    return j['streams'][0]['width'], j['streams'][0]['height'], float(j['format']['duration'])


def main():
    w, h, dur = probe()
    src = json.load(open(os.path.join(HERE, 'keyframes_px.json')))['keyframes']
    kfs = []
    for k in src:
        e = {'t': k['t'], 'state': k['state']}
        if k['box'] is not None:
            x0, y0, x1, y1 = k['box']
            assert 0 <= x0 < x1 <= w and 0 <= y0 < y1 <= h, k
            e.update({'cx': round((x0 + x1) / 2 / w, 4), 'cy': round((y0 + y1) / 2 / h, 4),
                      'w': round((x1 - x0) / w, 4), 'h': round((y1 - y0) / h, 4)})
        kfs.append(e)
    doc = {
        'schema': 'binnacle.demo_rider_track',
        'version': 1,
        'provenance': ('Pre-authored spatial rider track for the controlled recorded Demo footage. '
                       'Hand-read annotation, not detector output: it is not live detection, AI inference, '
                       'Jetson tracking, or Core Rider Lock.'),
        'source': {'asset': ASSET, 'sha256': sha256(ASSET_PATH), 'width': w, 'height': h,
                   'durationS': dur},
        'coordinateSystem': ('normalized SOURCE-frame coordinates, origin top-left; cx, cy = box centre, '
                             'w, h = box size, all 0..1'),
        'maxInterpolationGapS': 5.0,
        'keyframeSemantics': {
            'visible': 'rider seen; interpolated to the next visible keyframe',
            'occluded': 'rider not seen; the box is the last-known position and is held until the next keyframe',
            'unknown': 'no rider position known; no box'},
        'targets': [{'id': 'rider', 'label': 'RIDER', 'keyframes': kfs}],
    }
    with open(OUT, 'w') as f:
        json.dump(doc, f, indent=1)
        f.write('\n')
    print('wrote', OUT, len(kfs), 'keyframes; source', doc['source']['sha256'][:12])


if __name__ == '__main__':
    main()
