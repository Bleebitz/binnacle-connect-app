// Pre-stream check — a real check run before "Start broadcast" is ever
// allowed to actually request a broadcast. Every item here is either a
// real, freshly-measured signal, or an honest "not reported"/"not
// available" — nothing is fabricated to look more ready than it is.
//
// BLOCKING vs ADVISORY: a blocking item disables "Start broadcast"
// outright; an advisory item is shown but doesn't prevent starting. This
// screen never claims that passing it guarantees an uninterrupted
// stream — see the disclaimer text below the checklist.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../core/models/live_broadcast.dart';
import '../../core/services/connected_services.dart';
import '../../core/services/connectivity_checker.dart';
import '../theme/binnacle_theme.dart';

enum CheckSeverity { pass, advisory, blocking }

class CheckItem {
  final String title;
  final String detail;
  final CheckSeverity severity;
  const CheckItem({required this.title, required this.detail, required this.severity});
}

class PreStreamCheckScreen extends StatefulWidget {
  final OutgoingView view;
  final List<BroadcastDestination> destinations;
  final VoidCallback onStartBroadcast;

  const PreStreamCheckScreen({
    super.key,
    required this.view,
    required this.destinations,
    required this.onStartBroadcast,
  });

  @override
  State<PreStreamCheckScreen> createState() => _PreStreamCheckScreenState();
}

class _PreStreamCheckScreenState extends State<PreStreamCheckScreen> {
  bool _running = true;
  List<CheckItem> _items = const [];
  final ConnectivityChecker _connectivity = RealConnectivityChecker();

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<void> _runChecks() async {
    final items = <CheckItem>[];

    // 1. Camera/source — honest, not fabricated: this app has no phone-
    // side live preview of Vision's feed, and Core doesn't publish real
    // Vision/Track readiness telemetry yet (see My Boat's own "readiness
    // not reported" labels) — so this is advisory, not a pass, and never
    // a blocking failure on a signal that's never actually available.
    items.add(const CheckItem(
      title: 'Camera / source',
      detail: 'Vision readiness isn\'t reported by Core yet, and this build has no live '
          'preview here — this can\'t be verified before starting.',
      severity: CheckSeverity.advisory,
    ));

    // 2. Destination authorization — real: reads the same
    // ConnectedServicesService the destination-selection screen used.
    final connected = context.read<ConnectedServicesService>();
    for (final destination in widget.destinations) {
      if (!destination.kind.requiresConnectedService) {
        items.add(CheckItem(
          title: destination.kind == DestinationKind.customRtmp
              ? 'Destination: ${destination.customEndpoint ?? 'Custom RTMP'}'
              : 'Destination: ${destination.kind.label}',
          detail: 'No account link required.',
          severity: CheckSeverity.pass,
        ));
        continue;
      }
      final matching = connected.statuses.where((s) => s.kind == destination.kind);
      final status = matching.isEmpty ? null : matching.first;
      final isConnected = status?.connected ?? false;
      items.add(CheckItem(
        title: 'Destination: ${destination.kind.label}',
        detail: isConnected
            ? (status?.accountLabel ?? 'Connected')
            : 'Not connected — link this in Settings before going live here.',
        severity: isConnected ? CheckSeverity.pass : CheckSeverity.blocking,
      ));
    }

    // 3. Network — real: actual connectivity type, plus a real HTTP HEAD
    // timing as a practical (not guaranteed) quality signal.
    final connectivityResult = await _connectivity.check();
    final hasConnection = connectivityResult.isNotEmpty &&
        !connectivityResult.every((r) => r == ConnectivityResult.none);
    if (!hasConnection) {
      items.add(const CheckItem(
        title: 'Network',
        detail: 'No network connection detected.',
        severity: CheckSeverity.blocking,
      ));
    } else {
      final quality = await _measureNetworkQuality();
      items.add(CheckItem(
        title: 'Network',
        detail: quality.detail,
        severity: quality.severity,
      ));
    }

    // 4. Audience/destination summary — real: just reflects the actual
    // selection made on the previous screen.
    items.add(CheckItem(
      title: 'Outgoing view & audience',
      detail: '${widget.view.label} → ${widget.destinations.map((d) => d.label).join(', ')}',
      severity: CheckSeverity.pass,
    ));

    // 5. Audio — honest: Core/Vision owns audio capture per the approved
    // architecture: the phone has no audio path into a broadcast, and no
    // mute control exists for it yet. Advisory, not fabricated as
    // "available" or given a working mute toggle that would do nothing.
    items.add(const CheckItem(
      title: 'Audio',
      detail: 'Captured on Vision hardware, not this phone — availability and mute '
          'aren\'t reportable here yet.',
      severity: CheckSeverity.advisory,
    ));

    if (!mounted) return;
    setState(() {
      _items = items;
      _running = false;
    });
  }

  Future<({String detail, CheckSeverity severity})> _measureNetworkQuality() async {
    final stopwatch = Stopwatch()..start();
    try {
      await http.head(Uri.parse('https://www.google.com')).timeout(const Duration(seconds: 5));
      stopwatch.stop();
      final ms = stopwatch.elapsedMilliseconds;
      // A single round-trip timing is a practical signal, not a
      // guarantee — stated explicitly in the disclaimer below, not just
      // implied by a "Good" label.
      if (ms < 400) return (detail: 'Connected — round-trip ${ms}ms (looks good)', severity: CheckSeverity.pass);
      if (ms < 1200) {
        return (detail: 'Connected — round-trip ${ms}ms (fair; may buffer)', severity: CheckSeverity.advisory);
      }
      return (detail: 'Connected — round-trip ${ms}ms (slow; likely to struggle)', severity: CheckSeverity.advisory);
    } catch (_) {
      stopwatch.stop();
      return (
        detail: 'A connection is reported, but a real reachability check failed.',
        severity: CheckSeverity.advisory,
      );
    }
  }

  bool get _hasBlockingFailure => _items.any((i) => i.severity == CheckSeverity.blocking);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BinnacleColors.navyDeep,
      appBar: AppBar(title: const Text('Pre-stream check')),
      body: SafeArea(
        child: _running
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final item in _items) _CheckRow(item: item),
                        const SizedBox(height: 12),
                        const Text(
                          'This check reflects conditions right now — it does not guarantee '
                          'an uninterrupted stream once you go live.',
                          style: TextStyle(color: BinnacleColors.slateDim, fontSize: 11.5, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _hasBlockingFailure
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                widget.onStartBroadcast();
                              },
                        child: const Text('Start broadcast'),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final CheckItem item;
  const _CheckRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.severity) {
      CheckSeverity.pass => (Icons.check_circle, BinnacleColors.tealBright),
      CheckSeverity.advisory => (Icons.info, BinnacleColors.amber),
      CheckSeverity.blocking => (Icons.error, BinnacleColors.orange),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BinnacleColors.navy,
        borderRadius: BorderRadius.circular(12),
        border: item.severity == CheckSeverity.blocking
            ? Border.all(color: BinnacleColors.orange.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: BinnacleColors.offWhite)),
            const SizedBox(height: 2),
            Text(item.detail, style: const TextStyle(color: BinnacleColors.slateLight, fontSize: 12, height: 1.3)),
          ]),
        ),
      ]),
    );
  }
}
