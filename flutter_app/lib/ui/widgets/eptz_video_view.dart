import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/app_config.dart';
import '../theme/binnacle_theme.dart';
import '../../core/services/webrtc_service.dart';

/// Electronic PTZ video surface. Wraps [WebRtcService] behind a widget so
/// screens never touch the transport directly. Shows a clear SIMULATED
/// state when no real stream is attached — this must never be ambiguous
/// with a genuine live feed (see manifest: never describe simulated output
/// as measured).
class EptzVideoView extends StatelessWidget {
  final WebRtcService service;
  final Widget Function(BuildContext) simulatedBuilder;

  const EptzVideoView({
    super.key,
    required this.service,
    required this.simulatedBuilder,
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
            if (AppConfig.isDemo)
              simulatedBuilder(context)
            else
              StreamBuilder<void>(
                stream: service.onStatusChange,
                builder: (context, _) => switch (service.status) {
                  WebRtcLinkStatus.idle => const Center(
                      child: Text('Live video unavailable — awaiting Core media integration')),
                  WebRtcLinkStatus.connecting =>
                    const Center(child: Text('Connecting to Vision…')),
                  WebRtcLinkStatus.live => service.renderer.liveRenderer != null
                      ? RTCVideoView(service.renderer.liveRenderer!)
                      : const Center(child: Text('Live video unavailable — awaiting Core media integration')),
                  WebRtcLinkStatus.failed => Center(
                      child: Text(
                        'Couldn\'t reach Vision for video'
                        '${service.failureReason != null ? ' — ${service.failureReason}' : ''}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                },
              ),
            if (AppConfig.isDemo)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: BinnacleColors.navyDeep.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('SIMULATED', style: BinnacleTheme.mono(size: 9, color: BinnacleColors.slate)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
