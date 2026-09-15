import 'package:flutter/material.dart';
import '../../core/models/credential.dart';
import '../theme/binnacle_theme.dart';

/// Owner-only paired-device list and revocation. Per
/// Connect_Device_Pairing_and_Authorization_Design_v0.1 §5.
///
/// Revocation must be immediate and must work with the internet
/// disconnected — the Core holds this list, not the cloud. This screen is
/// gated at the navigation point (only reachable if role == owner); it is
/// UI convenience, same caveat as everywhere else: the Core is the real
/// enforcement point.
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  // DEMO DATA — a real build fetches this from the Core over the control
  // channel. No such endpoint exists yet in this scaffold.
  final List<PairedDevice> _devices = [
    PairedDevice(
      credentialId: 'demo-owner',
      displayName: "Levi's phone",
      role: DeviceRole.owner,
      pairedAt: DateTime.now().subtract(const Duration(days: 3)),
      lastSeen: DateTime.now(),
      isThisDevice: true,
    ),
    PairedDevice(
      credentialId: 'demo-crew-1',
      displayName: "Seth's phone",
      role: DeviceRole.crew,
      pairedAt: DateTime.now().subtract(const Duration(days: 2)),
      lastSeen: DateTime.now().subtract(const Duration(hours: 4)),
    ),
    PairedDevice(
      credentialId: 'demo-spectator-1',
      displayName: 'Guest tablet',
      role: DeviceRole.spectator,
      pairedAt: DateTime.now().subtract(const Duration(hours: 6)),
      lastSeen: DateTime.now().subtract(const Duration(hours: 6)),
    ),
  ];

  Future<void> _confirmRevoke(PairedDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: BinnacleColors.navy,
        title: Text('Revoke ${d.displayName}?'),
        content: const Text(
          'This device will be disconnected immediately and refused on any '
          'reconnect attempt, with or without internet access.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BinnacleColors.orange),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _devices.removeWhere((x) => x.credentialId == d.credentialId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${d.displayName} revoked')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paired devices')),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _devices.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final d = _devices[i];
          return Container(
            decoration: BoxDecoration(
              color: BinnacleColors.navy,
              borderRadius: BorderRadius.circular(12),
            ),
            // Same fix as settings_screen.dart's _Section — a ListTile
            // directly inside a solid-color Container loses its ink
            // splashes; Flutter raises a hard assertion for this in debug
            // and test builds, which is how it was actually caught here.
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _roleColor(d.role),
                child: Icon(_roleIcon(d.role), size: 18, color: BinnacleColors.navyDeep),
              ),
              title: Row(children: [
                Flexible(child: Text(d.displayName, overflow: TextOverflow.ellipsis)),
                if (d.isThisDevice) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: BinnacleColors.slateDim, borderRadius: BorderRadius.circular(6)),
                    child: const Text('THIS DEVICE', style: TextStyle(fontSize: 8)),
                  ),
                ],
              ]),
              subtitle: Text(
                '${d.role.label} · paired ${_ago(d.pairedAt)} · last seen ${d.lastSeen != null ? _ago(d.lastSeen!) : '—'}',
                style: BinnacleTheme.mono(size: 10),
              ),
              trailing: d.isThisDevice || d.role == DeviceRole.owner
                  ? null // cannot revoke yourself, or (in this simple model) another owner, from here
                  : IconButton(
                      icon: const Icon(Icons.link_off, color: BinnacleColors.orange, size: 20),
                      onPressed: () => _confirmRevoke(d),
                    ),
              ), // closes ListTile
            ), // closes Material
          );
        },
      ),
    );
  }

  Color _roleColor(DeviceRole r) => switch (r) {
        DeviceRole.owner => BinnacleColors.amber,
        DeviceRole.crew => BinnacleColors.tealBright,
        DeviceRole.spectator => BinnacleColors.slate,
      };

  IconData _roleIcon(DeviceRole r) => switch (r) {
        DeviceRole.owner => Icons.key,
        DeviceRole.crew => Icons.videocam,
        DeviceRole.spectator => Icons.visibility_outlined,
      };

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
