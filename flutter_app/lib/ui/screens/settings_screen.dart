import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/control_channel_service.dart';
import '../../core/services/pairing_service.dart';
import '../../core/models/credential.dart';
import '../theme/binnacle_theme.dart';
import 'pairing_screen.dart';
import 'device_list_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final control = context.watch<ControlChannelService>();
    final pairing = context.watch<PairingService>();
    final state = control.state;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(title: 'Pairing', children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              title: Text(pairing.isPaired ? 'Paired as ${pairing.role.label}' : 'Not paired'),
              subtitle: Text(
                pairing.isPaired ? pairing.role.description : 'This device is a spectator until paired',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PairingScreen()),
              ),
            ),
            // Owner-only navigation gate. UX convenience — the Core enforces
            // the real boundary on every command regardless of what this app
            // shows or hides.
            if (pairing.role == DeviceRole.owner)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                title: const Text('Paired devices'),
                subtitle: const Text('View and revoke access', style: TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeviceListScreen()),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          _Section(title: 'Device', children: [
            _Row('Connection', control.status.name.toUpperCase()),
            _Row('Compute', 'PI 5 · HAILO-8'),
            _Row('Transport', 'HTTPS/WSS · C-07'),
            _Row('On disconnect', 'HOLD STATE · KEEP RECORDING'),
          ]),
          const SizedBox(height: 16),
          _Section(title: 'Safety', children: [
            _Row('Fall detection', state.safety.fallDetection ? 'ALWAYS ON' : '—'),
            _Row('MOB alert', state.safety.mobAlert ? 'ALWAYS ON' : '—'),
            _Row('Escalation', '${state.safety.escalationSeconds}s'),
          ]),
          const SizedBox(height: 16),
          Text(
            'Running on simulated data until Vision hardware is assembled and Track is '
            'validated on the Hailo target. This is a Connect UX/architecture prototype, '
            'not an implementation — see Binnacle_Connect_App_Architecture_Flutter_Spec.',
            style: TextStyle(color: BinnacleColors.slateDim, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BinnacleColors.navy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Align(alignment: Alignment.centerLeft, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        ),
        // Material(type: transparency) so ListTile children paint ink
        // splashes correctly — the outer Container's solid background
        // would otherwise hide them (Flutter raises this as a hard
        // assertion in debug/test builds, caught by the widget test).
        Material(type: MaterialType.transparency, child: Column(children: children)),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label),
        Text(value, style: BinnacleTheme.mono(size: 11, color: BinnacleColors.tealBright)),
      ]),
    );
  }
}
