// Storage management — real, measured local disk usage, a clear
// separation between "delete the local copy" and "delete from the
// cloud" (the latter is honestly unavailable, since no cloud backend
// exists), and no clip is ever labeled "backed up" without a real,
// verified remote object — which today means never, since uploads
// aren't available (see media_upload_service.dart).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/clip.dart';
import '../theme/binnacle_theme.dart';
import 'library_screen.dart' show ClipRepository;

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  @override
  Widget build(BuildContext context) {
    final clips = context.watch<ClipRepository>().clips;
    final local = clips.where((c) => c.localPath != null).toList();
    final awaitingUpload = local
        .where((c) =>
            c.uploadStatus == UploadStatus.queued ||
            c.uploadStatus == UploadStatus.uploading ||
            c.uploadStatus == UploadStatus.paused ||
            c.uploadStatus == UploadStatus.onPhoneOnly)
        .toList();
    // Deliberately always empty today: `uploaded` is only ever set on a
    // real UploadOutcome.uploaded from a real MediaUploadService (see
    // library_screen.dart's _beginUploadAttempt) — never inferred, never
    // set just because an upload was attempted.
    final confirmedRemote = local.where((c) => c.uploadStatus == UploadStatus.uploaded).toList();

    final localBytes = local.fold<int>(0, (sum, c) => sum + (_realFileSize(c.localPath) ?? 0));

    return Scaffold(
      backgroundColor: BinnacleColors.navyDeep,
      appBar: AppBar(title: const Text('Storage')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StorageCard(
              title: 'On this phone',
              subtitle: '${local.length} item${local.length == 1 ? '' : 's'} · ${_fmtBytes(localBytes)}',
              icon: Icons.phone_iphone,
            ),
            const SizedBox(height: 10),
            _StorageCard(
              title: 'Awaiting upload',
              subtitle: '${awaitingUpload.length} item${awaitingUpload.length == 1 ? '' : 's'} — queued, '
                  'uploading, or on this phone only because cloud upload isn\'t available yet',
              icon: Icons.cloud_upload_outlined,
            ),
            const SizedBox(height: 10),
            _StorageCard(
              title: 'Confirmed stored remotely',
              subtitle: confirmedRemote.isEmpty
                  ? 'None — no cloud backend exists yet (see Settings → Uploads). Nothing here is '
                      'ever labeled stored remotely without a real server confirmation.'
                  : '${confirmedRemote.length} item${confirmedRemote.length == 1 ? '' : 's'}',
              icon: Icons.cloud_done_outlined,
            ),
            const SizedBox(height: 10),
            // Core reports no real storage telemetry today (see
            // vessel_state.dart's HealthState — storageFreePct is a
            // simulated-only figure in demo mode) — shown honestly as
            // unavailable rather than a number that isn't real.
            const _StorageCard(
              title: 'Core storage',
              subtitle: 'Not available — Core doesn\'t report real storage telemetry yet.',
              icon: Icons.sd_storage_outlined,
              muted: true,
            ),
            const SizedBox(height: 20),
            if (local.isNotEmpty) Text('Local media', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final clip in local)
              _LocalMediaRow(
                clip: clip,
                sizeBytes: _realFileSize(clip.localPath),
                onDeleteLocal: () => _confirmDeleteLocal(context, clip),
              ),
          ],
        ),
      ),
    );
  }

  int? _realFileSize(String? path) {
    if (path == null) return null;
    final file = File(path);
    return file.existsSync() ? file.lengthSync() : null;
  }

  Future<void> _confirmDeleteLocal(BuildContext context, Clip clip) async {
    final remoteConfirmed = clip.uploadStatus == UploadStatus.uploaded;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BinnacleColors.navy,
        title: const Text('Delete local copy?'),
        content: Text(
          remoteConfirmed
              ? 'This removes only the copy stored on this phone. It stays available from the '
                  'cloud copy that was actually confirmed uploaded.'
              : 'This media has not been confirmed uploaded anywhere. Deleting the local copy '
                  'removes your only copy of it — this cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BinnacleColors.orange),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<ClipRepository>().deleteLocalCopy(clip.id);
    }
  }

  String _fmtBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _StorageCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool muted;
  const _StorageCard({required this.title, required this.subtitle, required this.icon, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BinnacleColors.navy,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, color: muted ? BinnacleColors.slateDim : BinnacleColors.tealBright),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: muted ? BinnacleColors.slateDim : BinnacleColors.offWhite)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: BinnacleColors.slateLight, fontSize: 11.5, height: 1.3)),
          ]),
        ),
      ]),
    );
  }
}

class _LocalMediaRow extends StatelessWidget {
  final Clip clip;
  final int? sizeBytes;
  final VoidCallback onDeleteLocal;
  const _LocalMediaRow({required this.clip, required this.sizeBytes, required this.onDeleteLocal});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(clip.title, style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(
        sizeBytes == null
            ? 'File missing on disk'
            : '${(sizeBytes! / 1024).toStringAsFixed(0)} KB · ${clip.uploadStatus.name}',
        style: BinnacleTheme.mono(size: 10.5, color: BinnacleColors.slateLight),
      ),
      trailing: IconButton(
        tooltip: 'Delete local copy',
        icon: const Icon(Icons.delete_outline, color: BinnacleColors.orange),
        onPressed: onDeleteLocal,
      ),
    );
  }
}
