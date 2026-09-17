// Connected Services — architecture §14's Settings/Account entry point.
// Lists YouTube/Facebook/Twitch (honestly not connected — no OAuth flow is
// implemented; see connected_services.dart's module comment) and manages
// custom RTMP/RTMPS targets, which need no third-party account at all.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/live_broadcast.dart';
import '../../core/services/connected_services.dart';
import '../theme/binnacle_theme.dart';

class ConnectedServicesScreen extends StatelessWidget {
  const ConnectedServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<ConnectedServicesService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Connected Services')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Link an external destination to broadcast Connect Live there. '
              'Binnacle account linking for YouTube, Facebook and Twitch requires '
              'the Binnacle Cloud control plane, which does not exist yet — '
              'these show honestly as not connected rather than a placeholder login.',
              style: TextStyle(color: BinnacleColors.slateDim, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 16),
            for (final status in connected.statuses)
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(status.kind.label),
                  subtitle: Text(status.connected ? (status.accountLabel ?? 'Connected') : 'Not connected'),
                  trailing: OutlinedButton(
                    onPressed: null, // No OAuth implementation exists — disabled, not faked.
                    child: Text(status.connected ? 'Manage' : 'Connect'),
                  ),
                ),
              ),
            const Divider(height: 32),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Custom RTMP/RTMPS', style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            if (connected.customDestinations.isEmpty)
              Text('No custom destinations added yet.', style: TextStyle(color: BinnacleColors.slateDim, fontSize: 12)),
            for (final custom in connected.customDestinations)
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(custom.customEndpoint ?? 'Custom destination'),
                  subtitle: const Text('Stream key stored only for this app session'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => connected.removeCustomDestination(custom),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _addCustomRtmp(context),
              icon: const Icon(Icons.add),
              label: const Text('Add custom RTMP/RTMPS'),
            ),
          ],
        ),
      ),
    );
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
            onPressed: endpointController.text.trim().isEmpty ? null : () => Navigator.of(dialogContext).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (added == true && context.mounted) {
      context.read<ConnectedServicesService>().addCustomDestination(
            endpoint: endpointController.text.trim(),
            streamKey: keyController.text.trim(),
          );
    }
  }
}
