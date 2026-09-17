import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/models/vessel_state.dart';
import '../../core/services/control_channel_service.dart';
import '../../core/services/pairing_service.dart';
import '../theme/binnacle_theme.dart';
import '../widgets/binnacle_background.dart';
import 'crew_screen.dart';
import 'pairing_screen.dart';
import 'settings_screen.dart';

/// My Boat — the first screen after opening the app. Per the BIN-32 product
/// reorganization, this answers the actual boating-experience questions
/// before anything else: is Binnacle connected, is Vision online, is Track
/// ready, who's riding, are we recording, is storage/temperature/network
/// healthy. Previously there was no single place that answered all of
/// this — it was scattered across Capture's link bar and Settings' Device
/// section, discoverable only after already picking a tab.
///
/// Settings intentionally isn't a bottom-nav tab anymore — it's reached
/// from the profile icon in this screen's AppBar, per the same
/// reorganization: account/device management isn't a primary boating
/// activity on the same footing as riding, reviewing, or competing.
class MyBoatScreen extends StatelessWidget {
  final VoidCallback onGoLive;
  const MyBoatScreen({super.key, required this.onGoLive});

  @override
  Widget build(BuildContext context) {
    final control = context.watch<ControlChannelService>();
    final pairing = context.watch<PairingService>();
    final crew = context.watch<CrewRepository>();
    final state = control.state;

    return BinnacleBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('My Boat'),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: 'Settings & account',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusCard(
              icon: Icons.link,
              title: 'Binnacle connected',
              statusLine: _connectionLine(control.status),
              accent: _connectionColor(control.status),
            ),
            const SizedBox(height: 10),
            _StatusCard(
              icon: Icons.videocam_outlined,
              title: 'Vision online',
              // Vision's own liveness isn't modeled separately from the
              // control-channel link yet — they're the same signal here
              // honestly, not two independent checks dressed up as two.
              statusLine: 'Vision readiness not reported',
              accent: BinnacleColors.slate,
            ),
            const SizedBox(height: 10),
            _StatusCard(
              icon: Icons.gps_fixed,
              title: 'Track ready',
              statusLine: 'Track readiness not reported',
              accent: BinnacleColors.slate,
            ),
            const SizedBox(height: 10),
            _StatusCard(
              icon: state.capture.recording
                  ? Icons.fiber_manual_record
                  : Icons.circle_outlined,
              title: !control.hasCurrentState
                  ? 'Recording state unknown'
                  : state.capture.recording
                      ? 'Recording — pass ${state.capture.passNumber}'
                      : 'Not recording',
              statusLine: !control.hasCurrentState
                  ? 'Awaiting Core state'
                  : state.capture.recording
                      ? 'trigger: ${state.capture.triggerSource}'
                      : 'Awaiting capture',
              accent: state.capture.recording
                  ? BinnacleColors.orange
                  : BinnacleColors.tealBright,
            ),
            const SizedBox(height: 10),
            _RiderCard(crew: crew),
            const SizedBox(height: 10),
            if (control.hasCurrentState)
              _HealthCard(health: state.health, ts: state.ts)
            else
              const Text('Core health unavailable'),
            const SizedBox(height: 20),
            if (!pairing.isPaired)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner_outlined),
                  label: const Text('Pair a device'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PairingScreen()),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.videocam),
                label: const Text('Go Live'),
                onPressed: onGoLive,
              ),
            ),
            if (AppConfig.isDemo) ...[
              const SizedBox(height: 16),
              Text(
                'Demo mode — nothing above is a real connection. See Settings for details.',
                textAlign: TextAlign.center,
                style: TextStyle(color: BinnacleColors.slateDim, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _connectionLine(LinkStatus s) => switch (s) {
        LinkStatus.simulated => 'Simulated — no Vision device paired',
        LinkStatus.connecting => 'Connecting…',
        LinkStatus.connected => 'Connected',
        LinkStatus.stale => 'Not responding',
        LinkStatus.offline => 'Offline — recording state unknown',
      };

  static Color _connectionColor(LinkStatus s) => switch (s) {
        LinkStatus.simulated => BinnacleColors.slate,
        LinkStatus.connecting => BinnacleColors.amber,
        LinkStatus.connected => BinnacleColors.tealBright,
        LinkStatus.stale => BinnacleColors.amber,
        LinkStatus.offline => BinnacleColors.orange,
      };
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String statusLine;
  final Color accent;
  const _StatusCard(
      {required this.icon,
      required this.title,
      required this.statusLine,
      required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BinnacleColors.navy,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: BinnacleColors.offWhite.withValues(alpha: 0.09)),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontSize: 13.5)),
              Text(statusLine,
                  style: BinnacleTheme.mono(
                      size: 10.5, color: BinnacleColors.slate)),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Honest about a real gap rather than fabricating a "current rider" the
/// app has no way to actually know — automatic rider identification is a
/// Track capability that doesn't exist yet (see BIN-32). Shows the crew
/// roster that IS real (manually managed in Community → Crew) instead.
class _RiderCard extends StatelessWidget {
  final CrewRepository crew;
  const _RiderCard({required this.crew});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BinnacleColors.navy,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: BinnacleColors.offWhite.withValues(alpha: 0.09)),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: BinnacleColors.slate.withValues(alpha: 0.12),
              shape: BoxShape.circle),
          child: const Icon(Icons.person_outline,
              size: 18, color: BinnacleColors.slate),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Who\'s riding',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontSize: 13.5)),
              Text(
                crew.riders.length <= 1
                    ? 'Automatic rider ID needs Track — not available yet'
                    : '${crew.riders.length} in crew — automatic ID needs Track',
                style:
                    BinnacleTheme.mono(size: 10.5, color: BinnacleColors.slate),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _HealthCard extends StatelessWidget {
  final HealthState health;
  final DateTime ts;
  const _HealthCard({required this.health, required this.ts});

  static String _ago(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    return s < 60 ? '${s}s ago' : '${s ~/ 60}m ago';
  }

  @override
  Widget build(BuildContext context) {
    final warm = health.thermalState != 'nominal';
    // No network transport diagnostics exist in the wire schema yet (this
    // was a hardcoded 'LAN' before — a fabricated value the Core never
    // reported). Showing when the Core's state last actually arrived is
    // real, Core-reported data instead.
    final stale = DateTime.now().difference(ts) > const Duration(seconds: 5);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BinnacleColors.navy,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: BinnacleColors.offWhite.withValues(alpha: 0.09)),
      ),
      child: Row(
        children: [
          Expanded(
              child: _HealthStat(
                  label: 'TEMP',
                  value: '${health.tempC.toStringAsFixed(0)}°C',
                  warn: warm)),
          _VDivider(),
          Expanded(
            child: _HealthStat(
              label: 'STORAGE',
              value: '${health.storageFreePct}% free',
              warn: health.storageFreePct < 15,
            ),
          ),
          _VDivider(),
          Expanded(
              child:
                  _HealthStat(label: 'UPDATED', value: _ago(ts), warn: stale)),
        ],
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 1,
      height: 30,
      color: BinnacleColors.offWhite.withValues(alpha: 0.09));
}

class _HealthStat extends StatelessWidget {
  final String label;
  final String value;
  final bool warn;
  const _HealthStat(
      {required this.label, required this.value, required this.warn});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: warn ? BinnacleColors.amber : BinnacleColors.offWhite)),
        const SizedBox(height: 2),
        Text(label,
            style:
                BinnacleTheme.mono(size: 8.5, color: BinnacleColors.slateDim)),
      ],
    );
  }
}
