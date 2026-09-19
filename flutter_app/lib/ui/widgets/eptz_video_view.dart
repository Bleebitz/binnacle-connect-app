import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:video_player/video_player.dart';

import '../../core/services/camera_media_source.dart';
import '../../core/services/webrtc_service.dart';
import '../theme/binnacle_theme.dart';
import 'simulated_wake_view.dart';

/// Electronic PTZ video surface. Recorded Demo and live WebRTC sources render
/// through the same production-cropped surface so screens never touch either
/// transport directly. The recorded source is persistently labeled and must
/// never be ambiguous with a genuine live feed.
class EptzVideoView extends StatelessWidget {
  final CameraMediaSource source;

  const EptzVideoView({
    super.key,
    required this.source,
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
              _DemoRecordedVideo(source: demo)
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
            if (source.isRecordedDemo)
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
  const _DemoRecordedVideo({required this.source});

  @override
  State<_DemoRecordedVideo> createState() => _DemoRecordedVideoState();
}

class _DemoRecordedVideoState extends State<_DemoRecordedVideo> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(widget.source.assetPath)
      ..addListener(_onVideoTick);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      await _controller.setLooping(true);
      await _controller.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _onVideoTick() {
    widget.source.updatePlaybackPosition(_controller.value.position);
  }

  @override
  void dispose() {
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
    final size = _controller.value.size;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}
