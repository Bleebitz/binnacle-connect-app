import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:video_player/video_player.dart';

import '../../core/models/rider_track.dart';
import '../../core/services/camera_media_source.dart';
import '../../core/services/demo_media.dart';
import '../../core/services/track_framing.dart';
import '../../core/services/webrtc_service.dart';
import '../theme/binnacle_theme.dart';
import 'rider_box_painter.dart';
import 'simulated_wake_view.dart';

/// Electronic PTZ video surface. Recorded Demo and live WebRTC sources render
/// through the same production-cropped surface so screens never touch either
/// transport directly. The recorded source is persistently labeled and must
/// never be ambiguous with a genuine live feed.
class EptzVideoView extends StatelessWidget {
  final CameraMediaSource source;

  /// How the video fills its box. Portrait crops to fill; the landscape console
  /// shows the whole frame so nothing of the rider is cropped by the display.
  final BoxFit fit;

  /// Whether the video handles its own two-finger pinch (portrait). The
  /// landscape console owns all gestures and turns this off.
  final bool enablePinch;

  /// Whether this view draws its own recorded-feed label. The landscape console
  /// draws the label itself, inside the display safe area.
  final bool showDemoLabel;

  /// Keeps the rider tag below a HUD strip along the top (the landscape console).
  final double tagTopInset;

  const EptzVideoView({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.enablePinch = true,
    this.showDemoLabel = true,
    this.tagTopInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (source case DemoRecordedCameraSource demo)
              _DemoRecordedVideo(
                  source: demo,
                  fit: fit,
                  enablePinch: enablePinch,
                  tagTopInset: tagTopInset)
            else
              StreamBuilder<void>(
                stream:
                    (source as LiveWebRtcCameraSource).webRtc.onStatusChange,
                builder: (context, _) =>
                    switch ((source as LiveWebRtcCameraSource).webRtc.status) {
                  WebRtcLinkStatus.idle => const Center(
                      child: Text(
                          'Live video unavailable — awaiting Core media integration')),
                  WebRtcLinkStatus.connecting =>
                    const Center(child: Text('Connecting to Vision…')),
                  WebRtcLinkStatus.live => (source as LiveWebRtcCameraSource)
                              .webRtc
                              .renderer
                              .liveRenderer !=
                          null
                      ? RTCVideoView(
                          (source as LiveWebRtcCameraSource)
                              .webRtc
                              .renderer
                              .liveRenderer!,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      : const Center(
                          child: Text(
                              'Live video unavailable — awaiting Core media integration')),
                  WebRtcLinkStatus.failed => Center(
                      child: Text(
                        'Couldn\'t reach Vision for video'
                        '${(source as LiveWebRtcCameraSource).webRtc.failureReason != null ? ' — ${(source as LiveWebRtcCameraSource).webRtc.failureReason}' : ''}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                },
              ),
            if (source.isRecordedDemo && showDemoLabel)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: BinnacleColors.navyDeep.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'DEMO — RECORDED CAMERA FEED',
                    style: BinnacleTheme.mono(
                        size: 8.5, color: BinnacleColors.offWhite),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DemoRecordedVideo extends StatefulWidget {
  final DemoRecordedCameraSource source;
  final BoxFit fit;
  final bool enablePinch;
  final double tagTopInset;
  const _DemoRecordedVideo(
      {required this.source,
      required this.fit,
      required this.enablePinch,
      required this.tagTopInset});

  @override
  State<_DemoRecordedVideo> createState() => _DemoRecordedVideoState();
}

class _DemoRecordedVideoState extends State<_DemoRecordedVideo>
    with SingleTickerProviderStateMixin {
  late final VideoPlayerController _controller;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(widget.source.assetPath)
      ..addListener(_onVideoTick);
    // One frame callback advances the rider box and crop from the player's
    // (extrapolated) position; see DemoPlaybackClock. It reads the player, it is
    // not a second clock.
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
      _lastTick = elapsed;
      widget.source.tick(dt.clamp(0.0, 0.1).toDouble());
    });
    _initialize();
    _loadRiderTrack();
  }

  /// The pre-authored spatial rider track ships as a small JSON asset. A missing
  /// or invalid file leaves the Demo without a rider overlay (centre framing);
  /// it is never replaced by invented positions.
  Future<void> _loadRiderTrack() async {
    try {
      final text = await rootBundle.loadString(DemoRiderTrack.assetPath);
      final track = DemoRiderTrack.parse(text);
      if (mounted) widget.source.attachRiderTrack(track);
    } catch (_) {
      if (mounted) widget.source.attachRiderTrack(null);
    }
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.setLooping(true);
      await _controller.play();
      // Register as the single position source (Track state, Snapshot and
      // Save Highlight all read this same controller).
      widget.source.attachPlayer(
        readPosition: () => _controller.position,
        duration: _controller.value.duration,
        seekTo: _controller.seekTo,
      );
      if (mounted) {
        setState(() => _ready = true);
        _ticker.start();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onVideoTick() {
    widget.source.updatePlaybackPosition(_controller.value.position,
        playing: _controller.value.isPlaying);
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.source.detachPlayer();
    _controller.removeListener(_onVideoTick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Stack(
        fit: StackFit.expand,
        children: [
          SimulatedWakeView(),
          Center(child: Text('Demo camera asset unavailable')),
        ],
      );
    }
    if (!_ready || !_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final source = widget.source;
    final fit =
        widget.fit == BoxFit.contain ? FrameFit.contain : FrameFit.cover;
    final stage = DemoFramedStage(
      source: source,
      videoSize: _controller.value.size,
      fit: fit,
      tagTopInset: widget.tagTopInset,
      child: VideoPlayer(_controller),
    );
    return widget.enablePinch
        ? DemoPinchZoom(zoom: source.zoom, child: stage)
        : stage;
  }
}

/// The recorded feed's framed stage: the video (any [child] the size of the
/// source) drawn through the shared [FramingGeometry], with the rider box drawn
/// through the SAME geometry so pixels and marker cannot disagree at any zoom or
/// pan. Digital zoom and Track Follow panning are presentation of the recorded
/// video only; surrounding controls and labels are siblings in the parent Stack
/// and are never scaled.
class DemoFramedStage extends StatelessWidget {
  final DemoRecordedCameraSource source;
  final Size videoSize;
  final FrameFit fit;
  final Widget child;

  /// Height of any HUD strip along the top that the rider tag must stay below.
  final double tagTopInset;

  const DemoFramedStage({
    super.key,
    required this.source,
    required this.videoSize,
    required this.fit,
    required this.child,
    this.tagTopInset = 0,
  });

  @override
  Widget build(BuildContext context) {
    final framing = source.framing;
    return LayoutBuilder(builder: (context, c) {
      final viewport = Size(c.maxWidth, c.maxHeight);
      // Publish the layout to the shared framing (after this frame).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        framing.setViewport(viewport, fit);
      });
      return ClipRect(
        child: AnimatedBuilder(
          animation: Listenable.merge([framing, source.zoom]),
          builder: (context, _) {
            final g = framing.geometry ??
                FramingGeometry(
                    source: videoSize,
                    viewport: viewport,
                    fit: fit,
                    zoom: source.zoom.value);
            final m = g.matrix;
            final target = framing.target;
            final style = source.boxStyle;
            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: 0,
                  minHeight: 0,
                  maxWidth: videoSize.width,
                  maxHeight: videoSize.height,
                  child: Transform(
                    key: const ValueKey('video-transform'),
                    alignment: Alignment.topLeft,
                    transform: Matrix4.identity()
                      ..translateByDouble(m.tx, m.ty, 0, 1)
                      ..scaleByDouble(m.scale, m.scale, 1, 1),
                    child: SizedBox(
                      width: videoSize.width,
                      height: videoSize.height,
                      child: child,
                    ),
                  ),
                ),
                if (target != null && style != null)
                  IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: const ValueKey('rider-box'),
                        painter: RiderBoxPainter(
                          rect: g.boxToScreen(target.box),
                          style: style,
                          tagTopInset: tagTopInset,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    });
  }
}

/// Two-finger pinch for the recorded demo's digital zoom. It needs two
/// pointers, so single-finger scrolling of the page is unaffected. The value
/// is clamped by [DemoZoom].
class DemoPinchZoom extends StatefulWidget {
  final DemoZoom zoom;
  final Widget child;
  const DemoPinchZoom({super.key, required this.zoom, required this.child});

  @override
  State<DemoPinchZoom> createState() => _DemoPinchZoomState();
}

class _DemoPinchZoomState extends State<DemoPinchZoom> {
  double _base = DemoZoom.min;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleStart: (_) => _base = widget.zoom.value,
      onScaleUpdate: (d) {
        if (d.pointerCount >= 2) widget.zoom.setZoom(_base * d.scale);
      },
      child: widget.child,
    );
  }
}
