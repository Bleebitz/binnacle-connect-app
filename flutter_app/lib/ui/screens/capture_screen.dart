import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/vessel_state.dart';
import '../../core/services/control_channel_service.dart';
import '../../core/services/telemetry_socket.dart';
import '../../core/services/webrtc_service.dart';
import '../theme/binnacle_theme.dart';
import '../widgets/eptz_video_view.dart';
import '../widgets/gauge_painter.dart';
import '../widgets/mob_alert_banner.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _webrtc = WebRtcService();
  bool _mobActive = false;

  @override
  Widget build(BuildContext context) {
    final control = context.watch<ControlChannelService>();
    final telemetry = context.watch<TelemetrySocket>();
    final state = control.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect'),
        actions: [_LinkBadge(status: control.status, lastSeen: control.lastSeen)],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PresetRow(onPreset: (p) => control.loadPreset(p, actor: 'levi')),
            const SizedBox(height: 12),
            _RecordingStateCard(capture: state.capture, triggerMode: state.triggerMode),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 4 / 5,
              child: Stack(
                children: [
                  EptzVideoView(
                    service: _webrtc,
                    simulatedBuilder: (_) => Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF0F3244), Color(0xFF081A25)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Icon(Icons.gps_fixed, color: BinnacleColors.tealBright, size: 40),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: _TelemetryChip(telemetry: telemetry),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: FloatingActionButton.small(
                      heroTag: 'snapshot',
                      backgroundColor: BinnacleColors.navyRaised,
                      onPressed: () => control.snapshot(actor: 'levi'),
                      child: const Icon(Icons.camera_alt_outlined, size: 18),
                    ),
                  ),
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: MobAlertBanner(
                          active: _mobActive,
                          lat: '36.02083° N',
                          lon: '114.74215° W',
                          headingDegrees: 128,
                          onAcknowledge: () {
                            control.acknowledgeMob(actor: 'levi');
                            setState(() => _mobActive = false);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (state.framing.isManual) const _ManualFramingFlag(),
            const SizedBox(height: 8),
            _ArmSwitchRow(control: control, capture: state.capture),
            const SizedBox(height: 12),
            _SafetyCard(safety: state.safety), // always locked — see model
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _mobActive = !_mobActive),
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text('Simulate fall alert (demo)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkBadge extends StatelessWidget {
  final LinkStatus status;
  final DateTime lastSeen;
  const _LinkBadge({required this.status, required this.lastSeen});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      LinkStatus.simulated => ('SIMULATED', BinnacleColors.slate),
      LinkStatus.connecting => ('CONNECTING', BinnacleColors.amber),
      LinkStatus.connected => ('CONNECTED', BinnacleColors.tealBright),
      LinkStatus.stale => ('NOT RESPONDING', BinnacleColors.amber),
      LinkStatus.offline => ('OFFLINE — STILL RECORDING', BinnacleColors.orange),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Center(child: Text(label, style: BinnacleTheme.mono(size: 9, color: color, weight: FontWeight.w700))),
    );
  }
}

class _PresetRow extends StatelessWidget {
  final void Function(String) onPreset;
  const _PresetRow({required this.onPreset});
  static const presets = ['wakesurf', 'wakeboard', 'ski', 'tube', 'swim', 'cruise'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ActionChip(
          label: Text(presets[i]),
          onPressed: () => onPreset(presets[i]),
        ),
      ),
    );
  }
}

class _RecordingStateCard extends StatelessWidget {
  final CaptureState capture;
  final String triggerMode;
  const _RecordingStateCard({required this.capture, required this.triggerMode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BinnacleColors.navy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: capture.recording ? BinnacleColors.orange : BinnacleColors.slateDim, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: capture.recording ? BinnacleColors.orange : BinnacleColors.slateDim),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(capture.recording ? 'Recording — pass ${capture.passNumber}' : 'Buffering',
                  style: Theme.of(context).textTheme.titleMedium),
              Text('trigger: ${capture.triggerSource} · buffer ${capture.bufferHealth}',
                  style: BinnacleTheme.mono(size: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TelemetryChip extends StatelessWidget {
  final TelemetrySocket telemetry;
  const _TelemetryChip({required this.telemetry});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      TelemetryGauge(value: (telemetry.latest.speedMph / 30).clamp(0, 1), maxLabel: 30, unit: 'MPH', size: 52),
      const SizedBox(width: 6),
      TelemetryGauge(
        value: (telemetry.latest.riderDistanceM / 20).clamp(0, 1),
        maxLabel: 20,
        unit: 'M',
        size: 52,
        accent: BinnacleColors.amber,
      ),
    ]);
  }
}

class _ManualFramingFlag extends StatelessWidget {
  const _ManualFramingFlag();

  @override
  Widget build(BuildContext context) {
    final control = context.read<ControlChannelService>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: BinnacleColors.amber.withValues(alpha: 0.1),
        border: Border.all(color: BinnacleColors.amber),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        const Icon(Icons.pan_tool_alt_outlined, color: BinnacleColors.amber, size: 16),
        const SizedBox(width: 8),
        const Expanded(
            child: Text('MANUAL FRAMING — AI is not controlling the shot',
                style: TextStyle(color: BinnacleColors.amber, fontSize: 11, fontWeight: FontWeight.w700))),
        TextButton(
          onPressed: () => control.setControlMode('ai', actor: 'levi'),
          child: const Text('Hand back to AI'),
        ),
      ]),
    );
  }
}

class _ArmSwitchRow extends StatelessWidget {
  final ControlChannelService control;
  final CaptureState capture;
  const _ArmSwitchRow({required this.control, required this.capture});

  @override
  Widget build(BuildContext context) {
    final pending = control.isPending('arm') || control.isPending('disarm');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Armed'),
      subtitle: Text(capture.armed ? 'Tracking active on Vision' : 'Tracking paused',
          style: TextStyle(color: BinnacleColors.slate)),
      trailing: pending
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
          : Switch(
              value: capture.armed,
              onChanged: (v) => v ? control.arm(actor: 'levi') : control.disarm(actor: 'levi'),
            ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  final SafetyState safety;
  const _SafetyCard({required this.safety});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: BinnacleColors.navy, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.shield_outlined, size: 16, color: BinnacleColors.tealBright),
            const SizedBox(width: 8),
            Text('Safety', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: BinnacleColors.tealBright.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('LOCKED', style: BinnacleTheme.mono(size: 9, color: BinnacleColors.tealBright)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Fall detection and man-overboard alert are always on. '
            'No disable command exists in the control protocol.',
            style: TextStyle(color: BinnacleColors.slate, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
