// Core Mode must never receive Demo spatial data: the live camera source has no
// Demo capabilities, no targets until the Core supplies real ones, and nothing
// local can stand in for a Core rider lock.

import 'package:binnacle_connect/core/models/rider_track.dart';
import 'package:binnacle_connect/core/services/camera_media_source.dart';
import 'package:binnacle_connect/core/services/webrtc_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LiveWebRtcCameraSource live() => LiveWebRtcCameraSource(
      webRtc: WebRtcService(renderer: SimulatedVideoRenderer()));

  test('the live source has no Demo capabilities to call by mistake', () {
    final s = live();
    addTearDown(s.dispose);
    expect(s, isNot(isA<DemoMediaControls>()));
    expect(s, isNot(isA<DemoRecordedCameraSource>()));
    expect(s.isRecordedDemo, isFalse);
  });

  test('Core Mode builds the live source, never the recorded one', () {
    final s = CameraMediaSource.forMode(
        demo: false, webRtc: WebRtcService(renderer: SimulatedVideoRenderer()));
    addTearDown(s.dispose);
    expect(s, isA<LiveWebRtcCameraSource>());
    expect(s.targets.value, isEmpty,
        reason: 'no rider box is fabricated without real Track data');
  });

  test('the live source stays empty until real targets are supplied', () {
    final s = live();
    addTearDown(s.dispose);
    expect(s.targets.value, isEmpty);
    // Only the Core adapter may fill this; it is the same contract as the Demo's.
    s.acceptTargets(const [
      TrackTargetState(
        id: 't1',
        label: 'RIDER',
        box: NormBox(cx: 0.5, cy: 0.5, w: 0.1, h: 0.3),
        visibility: TargetVisibility.visible,
        provenance: TargetProvenance.core,
      ),
    ]);
    expect(s.targets.value.single.provenance, TargetProvenance.core);
    expect(s.targets.value.single.isDemo, isFalse);
  });

  test('the Demo source labels its targets as Demo annotation', () {
    final s = DemoRecordedCameraSource();
    addTearDown(s.dispose);
    expect(s.targets.value, isEmpty,
        reason: 'nothing until a track is attached');
    expect(s.isRecordedDemo, isTrue);
  });

  test('a rider track for a different video is refused, not drawn', () {
    final s = DemoRecordedCameraSource(assetPath: 'assets/demo/other.mp4');
    addTearDown(s.dispose);
    final track = DemoRiderTrack.parse(_sampleJson);
    s.attachRiderTrack(track);
    expect(s.framing.hasTrack, isFalse);
  });
}

const _sampleJson = '''
{"schema":"binnacle.demo_rider_track","version":1,"provenance":"test",
 "source":{"asset":"assets/demo/gopro_dev_footage.mp4",
  "sha256":"6815ded40dd19e8e4a0cf1db2c30b7eb9e04585029bc64d935c5c76ffdf33f8f",
  "width":1920,"height":1080,"durationS":130.0},
 "coordinateSystem":"normalized","maxInterpolationGapS":5.0,
 "targets":[{"id":"rider","label":"RIDER","keyframes":[
  {"t":0,"state":"visible","cx":0.5,"cy":0.5,"w":0.1,"h":0.3},
  {"t":1,"state":"visible","cx":0.5,"cy":0.5,"w":0.1,"h":0.3}]}]}
''';
