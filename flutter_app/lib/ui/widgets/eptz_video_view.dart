import 'package:flutter/material.dart';
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
            simulatedBuilder(context),
            if (!service.renderer.isAttached)
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
