import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/pairing_service.dart';
import '../../core/models/credential.dart';
import '../theme/binnacle_theme.dart';

/// Pairing flow. Per Connect_Device_Pairing_and_Authorization_Design_v0.1 §2.
///
/// Root of trust is physical access to the boat: a credential is only ever
/// issued while the Core has an open pairing window (button press, or an
/// owner opening one from the app). This screen supports both entry paths —
/// QR (normal) and manual/button fallback — and, critically, enforces the
/// unclaimed-unit warning from §2.4 before an owner role can be accepted.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _manualController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  Future<void> _attemptPair(PairingTarget? target) async {
    if (target == null) {
      setState(() => _error = 'That does not look like a Binnacle pairing code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final pairing = context.read<PairingService>();
    final result = await pairing.pair(target);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result.outcome) {
      case PairingOutcome.success:
        if (result.unitWasUnclaimed) {
          // §2.4 — DO NOT silently accept owner. This is the exact mitigation
          // for "a unit sitting unclaimed could be claimed by someone else
          // first." The user must read and confirm before the role sticks.
          await _showUnclaimedWarning(result.credential!);
        } else if (mounted) {
          Navigator.of(context).pop();
        }
        break;
      case PairingOutcome.windowClosed:
        setState(() => _error = result.message ??
            'No pairing window is open. Press the pairing button on the '
            'Vision unit, or ask the owner to open one from their app.');
        break;
      case PairingOutcome.refused:
        setState(() => _error = 'The Core refused this pairing request.');
        break;
      case PairingOutcome.unreachable:
        setState(() => _error = 'Could not reach the Core. Check the boat Wi-Fi.');
        break;
      case PairingOutcome.alreadyPaired:
        setState(() => _error = 'This device is already paired.');
        break;
    }
  }

  Future<void> _showUnclaimedWarning(DeviceCredential credential) async {
    bool acknowledged = false;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: BinnacleColors.navy,
          title: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: BinnacleColors.amber),
            const SizedBox(width: 10),
            const Expanded(child: Text('This unit had no previous owner')),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You are about to become the OWNER of this Vision unit. '
                'It reported no prior owner.\n\n'
                'If you just unboxed this unit, that is expected — continue.\n\n'
                'If you did not expect that — for example, this unit should '
                'already belong to someone else, or you found it already '
                'installed on a boat — STOP and check before continuing.',
                style: TextStyle(height: 1.5, fontSize: 13.5),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: acknowledged,
                onChanged: (v) => setDialogState(() => acknowledged = v ?? false),
                title: const Text(
                  'I expected this and want to become the owner of this unit.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stop'),
            ),
            FilledButton(
              // Deliberately disabled until the checkbox is ticked — cannot
              // be dismissed into ownership by reflexively tapping through.
              onPressed: acknowledged ? () => Navigator.of(dialogContext).pop(true) : null,
              child: const Text('Continue as owner'),
            ),
          ],
        ),
      ),
    );

    if (accepted == true) {
      if (mounted) Navigator.of(context).pop();
    } else {
      // User chose Stop, or dismissed without acknowledging: the credential
      // was already issued by the (simulated) Core, so we must actively
      // unpair rather than leave a half-accepted owner credential sitting on
      // the device.
      await context.read<PairingService>().unpair();
      if (mounted) {
        setState(() => _error =
            'Pairing cancelled. If this unit is not yours, do not pair with it.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairing = context.watch<PairingService>();

    if (pairing.isPaired) {
      return _AlreadyPairedView(credential: pairing.credential!);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pair with Vision')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: BinnacleColors.navy,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: BinnacleColors.slateDim),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.qr_code_scanner, size: 48, color: BinnacleColors.tealBright),
                  const SizedBox(height: 12),
                  const Text('Scan the QR label on the Vision unit'),
                  const SizedBox(height: 4),
                  Text('Camera scanning not wired in this scaffold',
                      style: BinnacleTheme.mono(size: 10, color: BinnacleColors.slateDim)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('No camera, or unreadable label?',
                style: TextStyle(color: BinnacleColors.slate, fontSize: 12.5)),
            const SizedBox(height: 8),
            Text(
              'Press the physical pairing button on the Vision unit — it opens '
              'a 60-second window — then enter the code it displays below.',
              style: TextStyle(color: BinnacleColors.slate, fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _manualController,
              decoration: const InputDecoration(
                hintText: 'binnacle://pair?d=...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () => _attemptPair(PairingTarget.tryParse(_manualController.text)),
                child: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Pair'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: BinnacleColors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: BinnacleColors.orange.withValues(alpha: 0.4)),
                ),
                child: Text(_error!, style: const TextStyle(color: BinnacleColors.orange, fontSize: 12.5)),
              ),
            ],
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 10),
            Text(
              'DEMO ONLY — no real Core exists in this scaffold to pair with. '
              'This button fabricates a successful pairing so the unclaimed-'
              'unit warning flow can actually be exercised.',
              style: BinnacleTheme.mono(size: 9.5, color: BinnacleColors.slateDim),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final result = await context.read<PairingService>().debugSimulatePairing(
                            unclaimed: true,
                            role: DeviceRole.owner,
                          );
                      if (!mounted) return;
                      setState(() => _busy = false);
                      if (result.unitWasUnclaimed) {
                        await _showUnclaimedWarning(result.credential!);
                      }
                    },
              child: const Text('Simulate pairing to an unclaimed unit'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlreadyPairedView extends StatelessWidget {
  final DeviceCredential credential;
  const _AlreadyPairedView({required this.credential});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pairing')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, color: BinnacleColors.tealBright, size: 40),
              const SizedBox(height: 12),
              Text('Paired as ${credential.role.label}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(credential.role.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: BinnacleColors.slate, fontSize: 12.5)),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => context.read<PairingService>().unpair(),
                child: const Text('Unpair this device'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
