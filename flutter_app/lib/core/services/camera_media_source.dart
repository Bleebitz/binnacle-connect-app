import 'package:flutter/foundation.dart';

import 'demo_media.dart';
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

/// Local media actions that only the recorded demo source can perform. The
/// live WebRTC source deliberately does not implement this: Core Mode's zoom,
/// snapshot and highlight are Core commands, so nothing local can be invoked
/// on it by mistake.
abstract interface class DemoMediaControls {
  DemoZoom get zoom;
  String get assetPath;

  /// Total length of the recorded source, once the player has loaded it.
  Duration? get sourceDuration;

  /// The recorded video's real playback position, read fresh from the player.
  /// Throws [StateError] when the player is not ready.
  Future<Duration> readPlaybackPosition();

  /// Live view of the recorded player's position, for the timeline.
  ValueListenable<Duration> get position;

  /// Seeks the recorded player. The player stays the single clock: Track state,
  /// Snapshot and Highlight all read the position it reports after the seek.
  Future<void> seekTo(Duration target);

  ValueNotifier<DemoViewMode> get viewMode;
  DemoRiderLock get riderLock;
}

class DemoRecordedCameraSource implements CameraMediaSource, DemoMediaControls {
  static const defaultAssetPath = 'assets/demo/gopro_dev_footage.mp4';

  @override
  final String assetPath;
  final DemoVisionTrackReducer reducer;
  final ValueNotifier<VisionTrackState> _trackState =
      ValueNotifier(VisionTrackState.acquiring);

  /// Digital zoom for the recorded feed (presentation only, never a command).
  @override
  final DemoZoom zoom = DemoZoom();

  @override
  final ValueNotifier<DemoViewMode> viewMode =
      ValueNotifier(DemoViewMode.trackFollow);

  @override
  final DemoRiderLock riderLock = DemoRiderLock();

  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);

  Duration _lastPosition = Duration.zero;
  Duration? _sourceDuration;
  Future<Duration?> Function()? _positionReader;
  Future<void> Function(Duration)? _seeker;

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

  @override
  Duration? get sourceDuration => _sourceDuration;

  /// The video player registers itself here. Its position is the single clock
  /// for Track state, Snapshot and Save Highlight; there is no second timer.
  void attachPlayer({
    required Future<Duration?> Function() readPosition,
    required Duration? duration,
    Future<void> Function(Duration)? seekTo,
  }) {
    _seeker = seekTo;
    _positionReader = readPosition;
    _sourceDuration = duration;
  }

  void detachPlayer() {
    _positionReader = null;
    _seeker = null;
  }

  @override
  ValueListenable<Duration> get position => _position;

  @override
  Future<void> seekTo(Duration target) async {
    final seeker = _seeker;
    if (seeker == null) {
      throw StateError('The recorded feed is not ready yet');
    }
    final total = _sourceDuration;
    var t = target < Duration.zero ? Duration.zero : target;
    if (total != null && t > total) t = total;
    await seeker(t);
    // Re-read from the player: whatever it reports is the truth.
    await readPlaybackPosition();
  }

  void updatePlaybackPosition(Duration position) {
    _lastPosition = position;
    _position.value = position;
    final next = reducer.reduce(position);
    if (_trackState.value.phase != next.phase) _trackState.value = next;
  }

  @override
  Future<Duration> readPlaybackPosition() async {
    final reader = _positionReader;
    if (reader == null) {
      throw StateError('The recorded feed is not ready yet');
    }
    final fresh = await reader();
    if (fresh != null) {
      updatePlaybackPosition(fresh);
      return fresh;
    }
    return _lastPosition;
  }

  @override
  void dispose() {
    _trackState.dispose();
    _position.dispose();
    viewMode.dispose();
    riderLock.dispose();
    zoom.dispose();
  }
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
