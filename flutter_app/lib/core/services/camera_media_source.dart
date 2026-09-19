import 'package:flutter/foundation.dart';

import '../models/rider_track.dart';
import 'demo_media.dart';
import 'track_framing.dart';
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

  /// Spatial targets the UI can mark and frame. This is the contract real
  /// Binnacle Track will later fill from the Core. The recorded Demo fills it
  /// from its pre-authored annotation (provenance says so); the live source
  /// stays EMPTY until real Core target data exists, and never fabricates any.
  ValueListenable<List<TrackTargetState>> get targets;

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

  /// The shared framing for the video, the rider box and tap hit-testing.
  DemoFraming get framing;

  /// How the current target should be drawn (null: draw nothing).
  RiderBoxStyle? get boxStyle;
}

/// How the rider box is drawn. Derived from the Demo Track state (so the box
/// never looks more certain than the state label) and from Rider Lock.
enum RiderBoxStyle {
  /// Seen but not yet acquired/locked: amber outline.
  candidate,

  /// Confirmed and locked by the operator: teal, `RIDER LOCKED`.
  locked,

  /// Tracking without an operator lock: white/teal outline.
  tracking,

  /// Lost recently; last-known box: dashed, reduced, `COASTING`.
  coasting,
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

  /// Extrapolates the player's position between its polls so the rider box and
  /// crop move every frame. The player stays the only clock: every report
  /// re-anchors it and a seek or loop is adopted immediately.
  final DemoPlaybackClock clock;

  @override
  late final DemoFraming framing =
      DemoFraming(zoom: zoom, viewMode: viewMode, riderLock: riderLock);

  final ValueNotifier<List<TrackTargetState>> _targets = ValueNotifier(const []);
  bool _seekPending = false;

  Duration _lastPosition = Duration.zero;
  Duration? _sourceDuration;
  Future<Duration?> Function()? _positionReader;
  Future<void> Function(Duration)? _seeker;

  DemoRecordedCameraSource({
    this.assetPath = defaultAssetPath,
    this.reducer = const DemoVisionTrackReducer(),
    DemoPlaybackClock? clock,
  }) : clock = clock ?? DemoPlaybackClock();

  @override
  CameraMediaKind get kind => CameraMediaKind.demoRecordedAsset;

  @override
  bool get isRecordedDemo => true;

  @override
  ValueListenable<VisionTrackState> get trackState => _trackState;

  @override
  Duration? get sourceDuration => _sourceDuration;

  @override
  ValueListenable<List<TrackTargetState>> get targets => _targets;

  /// Loads the pre-authored spatial rider track for this recorded asset. A
  /// track annotated for a different source video is refused, so it can never
  /// be drawn over footage it does not describe.
  void attachRiderTrack(DemoRiderTrack? track) {
    if (track != null && track.sourceAsset != assetPath) {
      framing.attachTrack(null);
      return;
    }
    framing.attachTrack(track);
  }

  @override
  RiderBoxStyle? get boxStyle {
    final t = framing.target;
    if (t == null) return null;
    final phase = _trackState.value.phase;
    if (t.isCoasting || phase == VisionTrackPhase.occluded) {
      return RiderBoxStyle.coasting;
    }
    if (phase == VisionTrackPhase.acquiring ||
        phase == VisionTrackPhase.unavailable) {
      return RiderBoxStyle.candidate;
    }
    return riderLock.isLockedOn(t.id)
        ? RiderBoxStyle.locked
        : RiderBoxStyle.tracking;
  }

  /// Advance the per-frame framing. Called by the video view's frame callback.
  /// Uses the extrapolated player position, so there is no second timeline.
  void tick(double dt) {
    final pos = clock.now;
    final next = reducer.reduce(pos);
    if (_trackState.value.phase != next.phase) _trackState.value = next;
    framing.update(pos, dt: dt, seeked: _seekPending);
    _seekPending = false;
    final t = framing.target;
    final cur = _targets.value;
    if (t == null) {
      if (cur.isNotEmpty) _targets.value = const [];
    } else if (cur.isEmpty || cur.first.box != t.box || cur.first.visibility != t.visibility) {
      _targets.value = [t];
    }
  }

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
    clock.duration = duration;
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

  void updatePlaybackPosition(Duration position, {bool playing = true}) {
    _lastPosition = position;
    _position.value = position;
    if (clock.anchor(position, playing: playing)) _seekPending = true;
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
    _targets.dispose();
    framing.dispose();
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

  final ValueNotifier<List<TrackTargetState>> _targets = ValueNotifier(const []);

  /// Empty until the Core supplies real Track targets. Deliberately not filled
  /// from anything local: BIN-51 (Jetson-to-app stream and HUD timing) is open.
  @override
  ValueListenable<List<TrackTargetState>> get targets => _targets;

  /// Ready for the Core/Vision state adapter once its Track-state schema is
  /// finalized. This is deliberately not inferred from WebRTC link status.
  void acceptTrackState(VisionTrackState state) => _trackState.value = state;

  /// Ready for the Core/Vision target adapter. Only real Track output may be
  /// passed here.
  void acceptTargets(List<TrackTargetState> targets) => _targets.value = targets;

  @override
  void dispose() {
    _trackState.dispose();
    _targets.dispose();
  }
}
