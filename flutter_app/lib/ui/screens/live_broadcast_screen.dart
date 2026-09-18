// Connect Live — BIN-38's GO LIVE flow. Destination + view selection, then
// authoritative-only health while a broadcast attempt is in progress. See
// live_broadcast_service.dart for the state machine this screen only ever
// reads; nothing here mutates a lifecycle state directly.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/models/live_broadcast.dart';
import '../../core/services/connected_services.dart';
import '../../core/services/entitlement_service.dart';
import '../../core/services/live_broadcast_service.dart';
import '../theme/binnacle_theme.dart';
import 'pre_stream_check_screen.dart';

class LiveBroadcastScreen extends StatefulWidget {
  const LiveBroadcastScreen({super.key});

  @override
  State<LiveBroadcastScreen> createState() => _LiveBroadcastScreenState();
}

class _LiveBroadcastScreenState extends State<LiveBroadcastScreen> {
  OutgoingView _view = OutgoingView.rawCamera;
  final Set<BroadcastDestination> _selected = {};

  void _toggleDestination(BroadcastDestination destination, LiveEntitlement entitlement) {
    setState(() {
      if (_selected.contains(destination)) {
        _selected.remove(destination);
        return;
      }
      // Free (and any plan capped at exactly one destination) behaves like
      // a radio group — selecting a new one replaces the old one instead of
      // silently rejecting the tap, which would look broken rather than
      // entitlement-gated.
      if (entitlement.maxSimultaneousDestinations == 1) _selected.clear();
      if (_selected.length < entitlement.maxSimultaneousDestinations) {
        _selected.add(destination);
      }
    });
  }

  Future<void> _addCustomRtmp(BuildContext context) async {
    final endpointController = TextEditingController();
    final keyController = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BinnacleColors.navy,
        title: const Text('Custom RTMP/RTMPS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: endpointController,
              decoration: const InputDecoration(labelText: 'Server URL (rtmps://...)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(labelText: 'Stream key'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: endpointController.text.trim().isEmpty
                ? null
                : () => Navigator.of(dialogContext).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (added == true && mounted) {
      context.read<ConnectedServicesService>().addCustomDestination(
            endpoint: endpointController.text.trim(),
            streamKey: keyController.text.trim(),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<LiveBroadcastService>();
    final entitlement = context.watch<EntitlementService>().liveEntitlement;
    final connected = context.watch<ConnectedServicesService>();

    return Scaffold(
      backgroundColor: BinnacleColors.navyDeep,
      appBar: AppBar(title: const Text('Connect Live')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (AppConfig.isDemo) const _SimulatedBanner(),
            const SizedBox(height: 12),
            if (live.session == null)
              _SetupPanel(
                view: _view,
                onViewChanged: (v) => setState(() => _view = v),
                selected: _selected,
                entitlement: entitlement,
                connected: connected,
                onToggle: (d) => _toggleDestination(d, entitlement),
                onAddCustomRtmp: () => _addCustomRtmp(context),
                busy: live.busy,
                error: live.lastError,
                onGoLive: _selected.isEmpty || live.busy
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PreStreamCheckScreen(
                            view: _view,
                            destinations: _selected.toList(),
                            onStartBroadcast: () =>
                                live.goLive(view: _view, destinations: _selected.toList(), entitlement: entitlement),
                          ),
                        )),
              )
            else
              _HealthPanel(session: live.session!, busy: live.busy, error: live.lastError, onStop: live.stop),
          ],
        ),
      ),
    );
  }
}

class _SimulatedBanner extends StatelessWidget {
  const _SimulatedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BinnacleColors.amber.withValues(alpha: 0.1),
        border: Border.all(color: BinnacleColors.amber),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        const Icon(Icons.science_outlined, size: 16, color: BinnacleColors.amber),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'SIMULATED — demo mode. No real Core/cloud connection exists; every '
            'state below is a scripted demonstration, not measured broadcast health.',
            style: TextStyle(color: BinnacleColors.amber, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

class _SetupPanel extends StatelessWidget {
  final OutgoingView view;
  final ValueChanged<OutgoingView> onViewChanged;
  final Set<BroadcastDestination> selected;
  final LiveEntitlement entitlement;
  final ConnectedServicesService connected;
  final ValueChanged<BroadcastDestination> onToggle;
  final VoidCallback onAddCustomRtmp;
  final bool busy;
  final String? error;
  final VoidCallback? onGoLive;

  const _SetupPanel({
    required this.view,
    required this.onViewChanged,
    required this.selected,
    required this.entitlement,
    required this.connected,
    required this.onToggle,
    required this.onAddCustomRtmp,
    required this.busy,
    required this.error,
    required this.onGoLive,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Outgoing view', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: OutgoingView.values.map((v) {
            final on = v == view;
            return ChoiceChip(
              label: Text(v.isAvailableNow ? v.label : '${v.label} (soon)'),
              selected: on,
              onSelected: v.isAvailableNow ? (_) => onViewChanged(v) : null,
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text(view.description, style: TextStyle(color: BinnacleColors.slate, fontSize: 11.5)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Destinations', style: Theme.of(context).textTheme.titleMedium),
          Text('${entitlement.tier.label} · up to ${entitlement.maxSimultaneousDestinations}',
              style: BinnacleTheme.mono(size: 10.5, color: BinnacleColors.slateDim)),
        ]),
        const SizedBox(height: 8),
        _DestinationTile(
          destination: const BroadcastDestination(kind: DestinationKind.binnacleLive),
          subtitle: 'Watch inside Binnacle',
          enabled: true,
          selected: selected.contains(const BroadcastDestination(kind: DestinationKind.binnacleLive)),
          onTap: () => onToggle(const BroadcastDestination(kind: DestinationKind.binnacleLive)),
        ),
        for (final status in connected.statuses)
          _DestinationTile(
            destination: BroadcastDestination(kind: status.kind),
            subtitle: status.connected ? (status.accountLabel ?? 'Connected') : 'Not connected — add in Settings',
            enabled: status.connected,
            selected: selected.contains(BroadcastDestination(kind: status.kind)),
            onTap: () => onToggle(BroadcastDestination(kind: status.kind)),
          ),
        for (final custom in connected.customDestinations)
          _DestinationTile(
            destination: custom,
            subtitle: 'Custom RTMP/RTMPS',
            enabled: true,
            selected: selected.contains(custom),
            onTap: () => onToggle(custom),
          ),
        // Not a DestinationKind — permanently disabled, informational only.
        // See connected_services_screen.dart for the documented limitation.
        const _UnsupportedDestinationTile(
          label: 'Instagram',
          reason: 'Instagram streaming is not supported by this implementation',
        ),
        TextButton.icon(
          onPressed: onAddCustomRtmp,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add custom RTMP/RTMPS'),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: const TextStyle(color: BinnacleColors.orange, fontSize: 12)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onGoLive,
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sensors),
            label: Text(busy ? 'Requesting…' : 'GO LIVE'),
          ),
        ),
      ],
    );
  }
}

class _DestinationTile extends StatelessWidget {
  final BroadcastDestination destination;
  final String subtitle;
  final bool enabled;
  final bool selected;
  final VoidCallback onTap;

  const _DestinationTile({
    required this.destination,
    required this.subtitle,
    required this.enabled,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: selected,
        onChanged: enabled ? (_) => onTap() : null,
        title: Text(destination.label),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}

/// A destination that isn't selectable at all — distinct from a
/// [_DestinationTile] with `enabled: false` (which means "connect it in
/// Settings first"). This means "this platform is not offered," with an
/// honest reason, not a checkbox that will work once something else is set up.
class _UnsupportedDestinationTile extends StatelessWidget {
  final String label;
  final String reason;
  const _UnsupportedDestinationTile({required this.label, required this.reason});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.block, size: 20, color: BinnacleColors.slateDim),
        title: Text(label, style: const TextStyle(color: BinnacleColors.slateDim)),
        subtitle: Text(reason, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}

class _HealthPanel extends StatelessWidget {
  final LiveBroadcastSession session;
  final bool busy;
  final String? error;
  final VoidCallback onStop;

  const _HealthPanel({required this.session, required this.busy, required this.error, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final duration = session.duration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: BinnacleColors.navy, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('Cloud ingest', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                _StateChip(state: session.ingestState),
              ]),
              const SizedBox(height: 6),
              Text(
                'View: ${session.view.label} · '
                '${duration == null ? 'Not live yet' : 'Live ${_formatDuration(duration)}'}',
                style: BinnacleTheme.mono(size: 11, color: BinnacleColors.slateDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('Destinations', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final health in session.destinations.values) _DestinationHealthCard(health: health),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: const TextStyle(color: BinnacleColors.orange, fontSize: 12)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: session.ingestState == BroadcastLifecycleState.stopped ? null : (busy ? null : onStop),
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.stop_circle_outlined),
            // "Working…" rather than "Stopping…": busy is also true right
            // after a fresh GO LIVE tap, while ingest is still only
            // REQUESTED — this button hasn't necessarily been pressed at
            // all yet, so it must not claim a stop is in progress.
            label: Text(busy ? 'Working…' : 'STOP'),
          ),
        ),
      ],
    );
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}m ${s}s';
  }
}

class _DestinationHealthCard extends StatelessWidget {
  final DestinationHealth health;
  const _DestinationHealthCard({required this.health});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final stale = health.isStale(now);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BinnacleColors.navy,
        border: Border.all(color: health.degraded ? BinnacleColors.amber : Colors.transparent),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(health.destination.label, style: const TextStyle(fontWeight: FontWeight.w600))),
            _StateChip(state: health.state),
          ]),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            children: [
              if (health.bitrateKbps != null) Text('${health.bitrateKbps} kbps', style: BinnacleTheme.mono(size: 10.5)),
              if (health.outputQuality != null) Text(health.outputQuality!, style: BinnacleTheme.mono(size: 10.5)),
              if (health.degraded)
                Text('DEGRADED — dropped frames', style: BinnacleTheme.mono(size: 10.5, color: BinnacleColors.amber)),
              Text(
                stale ? 'STALE — last update ${now.difference(health.asOf).inSeconds}s ago' : 'updated just now',
                style: BinnacleTheme.mono(size: 10.5, color: stale ? BinnacleColors.orange : BinnacleColors.slateDim),
              ),
            ],
          ),
          if (health.reason != null) ...[
            const SizedBox(height: 4),
            Text(health.reason!, style: const TextStyle(color: BinnacleColors.orange, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final BroadcastLifecycleState state;
  const _StateChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      BroadcastLifecycleState.live => BinnacleColors.tealBright,
      BroadcastLifecycleState.degraded => BinnacleColors.amber,
      BroadcastLifecycleState.connecting => BinnacleColors.amber,
      BroadcastLifecycleState.requested => BinnacleColors.slate,
      BroadcastLifecycleState.failed => BinnacleColors.orange,
      BroadcastLifecycleState.stopped => BinnacleColors.slateDim,
      BroadcastLifecycleState.unknown => BinnacleColors.slateDim,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(state.label.toUpperCase(), style: BinnacleTheme.mono(size: 9.5, color: color)),
    );
  }
}
