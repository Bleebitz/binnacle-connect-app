import 'package:flutter/foundation.dart';

import 'webrtc_service.dart';

enum CameraMediaKind { demoRecordedAsset, liveWebRtc }

enum VisionTrackPhase {
  unavailable,
  acquiring,
  riderLocked,
  occluded,
  tracking
}

@immutable
class VisionTrackState {
  final VisionTrackPhase phase;
  final String label;
  final bool riderVisible;

  const VisionTrackState({
    required this.phase,
    required this.label,
    required this.riderVisible,
  });

  static const acquiring = VisionTrackState(
    phase: VisionTrackPhase.acquiring,
    label: 'ACQUIRING RIDER',
    riderVisible: false,
  );
  static const unavailable = VisionTrackState(
    phase: VisionTrackPhase.unavailable,
    label: 'TRACK STATE UNAVAILABLE',
    riderVisible: false,
  );
  static const riderLocked = VisionTrackState(
    phase: VisionTrackPhase.riderLocked,
    label: 'RIDER LOCKED',
    riderVisible: true,
  );
  static const occluded = VisionTrackState(
    phase: VisionTrackPhase.occluded,
    label: 'OCCLUDED · COASTING',
    riderVisible: false,
  );
  static const tracking = VisionTrackState(
    phase: VisionTrackPhase.tracking,
    label: 'TRACKING',
    riderVisible: true,
  );
}

/// Pure reducer shared by the recorded demo feed and its HUD. Keeping the
/// timeline out of the widget means video position is the single clock and
/// replay/seek/loop all deterministically produce the same Track state.
class DemoVisionTrackReducer {
  const DemoVisionTrackReducer();

  VisionTrackState reduce(Duration position) {
    final seconds = position.inMilliseconds / 1000;
    // The controlled 130-second stern-camera pass keeps the rider visible
    // until the real fall near the end. The final loss/coast window then
    // returns to acquisition before video_player loops back to zero.
    if (seconds < 3) return VisionTrackState.acquiring;
    if (seconds < 15) return VisionTrackState.riderLocked;
    if (seconds < 121) return VisionTrackState.tracking;
    if (seconds < 129) return VisionTrackState.occluded;
    return VisionTrackState.acquiring;
  }
}

/// Media boundary for the Live screen. Both recorded demo playback and the
/// real WebRTC transport feed the same viewport/HUD; the screen never needs
/// to know how pixels arrive.
abstract class CameraMediaSource {
  CameraMediaKind get kind;
  ValueListenable<VisionTrackState> get trackState;
  bool get isRecordedDemo => kind == CameraMediaKind.demoRecordedAsset;
  void dispose();

  factory CameraMediaSource.forMode({
    required bool demo,
    required WebRtcService webRtc,
    String demoAssetPath = DemoRecordedCameraSource.defaultAssetPath,
  }) =>
      demo
          ? DemoRecordedCameraSource(assetPath: demoAssetPath)
          : LiveWebRtcCameraSource(webRtc: webRtc);
}

class DemoRecordedCameraSource implements CameraMediaSource {
  static const defaultAssetPath = 'assets/demo/gopro_dev_footage.mp4';

  final String assetPath;
  final DemoVisionTrackReducer reducer;
  final ValueNotifier<VisionTrackState> _trackState =
      ValueNotifier(VisionTrackState.acquiring);

  DemoRecordedCameraSource({
    this.assetPath = defaultAssetPath,
    this.reducer = const DemoVisionTrackReducer(),
  });

  @override
  CameraMediaKind get kind => CameraMediaKind.demoRecordedAsset;

  @override
  bool get isRecordedDemo => true;

  @override
  ValueListenable<VisionTrackState> get trackState => _trackState;

  void updatePlaybackPosition(Duration position) {
    final next = reducer.reduce(position);
    if (_trackState.value.phase != next.phase) _trackState.value = next;
  }

  @override
  void dispose() => _trackState.dispose();
}

class LiveWebRtcCameraSource implements CameraMediaSource {
  final WebRtcService webRtc;
  final ValueNotifier<VisionTrackState> _trackState =
      ValueNotifier(VisionTrackState.unavailable);

  LiveWebRtcCameraSource({required this.webRtc});

  @override
  CameraMediaKind get kind => CameraMediaKind.liveWebRtc;

  @override
  bool get isRecordedDemo => false;

  @override
  ValueListenable<VisionTrackState> get trackState => _trackState;

  /// Ready for the Core/Vision state adapter once its Track-state schema is
  /// finalized. This is deliberately not inferred from WebRTC link status.
  void acceptTrackState(VisionTrackState state) => _trackState.value = state;

  @override
  void dispose() => _trackState.dispose();
}
