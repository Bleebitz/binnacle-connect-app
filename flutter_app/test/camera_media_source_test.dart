import 'package:binnacle_connect/core/services/camera_media_source.dart';
import 'package:binnacle_connect/core/services/webrtc_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('camera media source selection', () {
    late WebRtcService webRtc;

    setUp(() {
      webRtc = WebRtcService(renderer: SimulatedVideoRenderer());
    });

    tearDown(() => webRtc.dispose());

    test('Demo selects the bundled recorded asset', () {
      final source = CameraMediaSource.forMode(demo: true, webRtc: webRtc);
      addTearDown(source.dispose);

      expect(source.kind, CameraMediaKind.demoRecordedAsset);
      expect(source.isRecordedDemo, isTrue);
      expect(
        (source as DemoRecordedCameraSource).assetPath,
        DemoRecordedCameraSource.defaultAssetPath,
      );
    });

    test('Core selects the live WebRTC transport', () {
      final source = CameraMediaSource.forMode(demo: false, webRtc: webRtc);
      addTearDown(source.dispose);

      expect(source.kind, CameraMediaKind.liveWebRtc);
      expect(source.isRecordedDemo, isFalse);
      expect((source as LiveWebRtcCameraSource).webRtc, same(webRtc));
      expect(source.trackState.value.phase, VisionTrackPhase.unavailable);
    });
  });

  group('recorded demo Track reducer', () {
    const reducer = DemoVisionTrackReducer();

    test('moves through the deterministic acquisition timeline', () {
      expect(reducer.reduce(Duration.zero).phase, VisionTrackPhase.acquiring);
      expect(reducer.reduce(const Duration(milliseconds: 1999)).phase,
          VisionTrackPhase.acquiring);
      expect(reducer.reduce(const Duration(seconds: 2)).phase,
          VisionTrackPhase.riderLocked);
      expect(reducer.reduce(const Duration(seconds: 7)).phase,
          VisionTrackPhase.occluded);
      expect(reducer.reduce(const Duration(seconds: 9)).phase,
          VisionTrackPhase.tracking);
    });

    test('source publishes reducer state from video position', () {
      final source = DemoRecordedCameraSource();
      addTearDown(source.dispose);

      source.updatePlaybackPosition(const Duration(seconds: 8));
      expect(source.trackState.value, same(VisionTrackState.occluded));

      source.updatePlaybackPosition(const Duration(seconds: 10));
      expect(source.trackState.value, same(VisionTrackState.tracking));
    });
  });
}
