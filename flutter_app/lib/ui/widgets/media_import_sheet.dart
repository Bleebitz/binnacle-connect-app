// Shared "pick from phone -> preview -> confirm/cancel -> import" flow,
// used by Library's Add media action, Best Falls' real-import entry, and
// Community's Post a highlight flow — one real implementation instead of
// three divergent copies. See media_import_service.dart for the picker/
// copy boundary and media_upload_service.dart for why upload stays
// unavailable today.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/clip.dart';
import '../../core/services/media_import_service.dart';
import '../../core/services/media_upload_service.dart';
import '../screens/library_screen.dart' show ClipRepository;
import '../theme/binnacle_theme.dart';

/// Runs the whole pick -> preview -> confirm -> import flow. Returns the
/// imported [Clip], or null if the user cancelled at any step (system
/// picker cancel, or declining the preview) — never a partially-imported
/// clip on cancel.
Future<Clip?> pickAndImportMedia(
  BuildContext context, {
  required ImportMediaKind kind,
  ClipKind? kindOverride,
  String? titleOverride,
  String? riderId,
}) async {
  final importer = context.read<MediaImportService>();
  final uploader = context.read<MediaUploadService>();
  final repo = context.read<ClipRepository>();

  PickedMedia? picked;
  try {
    picked = kind == ImportMediaKind.photo ? await importer.pickPhoto() : await importer.pickVideo();
  } on MediaImportException catch (e) {
    if (context.mounted) _showError(context, e.message);
    return null;
  }
  if (picked == null) return null; // user cancelled the system picker
  if (!context.mounted) return null;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _PreviewDialog(media: picked!),
  );
  if (confirmed != true) return null; // user cancelled the preview

  if (!context.mounted) return null;
  _showImporting(context);
  try {
    final clip = await repo.importPicked(
      picked,
      importer: importer,
      uploader: uploader,
      kindOverride: kindOverride,
      titleOverride: titleOverride,
      riderId: riderId,
    );
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop(); // dismiss "Importing…"
    return clip;
  } on MediaImportException catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      _showError(context, e.message);
    }
    return null;
  }
}

void _showImporting(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      backgroundColor: BinnacleColors.navy,
      content: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 16),
        Text('Importing…'),
      ]),
    ),
  );
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _formatSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _PreviewDialog extends StatelessWidget {
  final PickedMedia media;
  const _PreviewDialog({required this.media});

  @override
  Widget build(BuildContext context) {
    final tooLarge = media.sizeBytes > largeFileWarningBytes;
    return AlertDialog(
      backgroundColor: BinnacleColors.navy,
      title: Text(media.kind == ImportMediaKind.photo ? 'Import this photo?' : 'Import this video?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (media.kind == ImportMediaKind.photo)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(media.sourcePath), height: 160, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                        height: 160,
                        child: Center(child: Icon(Icons.broken_image_outlined)),
                      )),
            )
          else
            Container(
              height: 90,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: BinnacleColors.navyRaised,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.videocam_outlined, size: 32, color: BinnacleColors.tealBright),
            ),
          const SizedBox(height: 10),
          Text(media.fileName, style: BinnacleTheme.mono(size: 11, color: BinnacleColors.slateLight)),
          Text(_formatSize(media.sizeBytes), style: BinnacleTheme.mono(size: 11, color: BinnacleColors.slateLight)),
          if (tooLarge) ...[
            const SizedBox(height: 8),
            const Text(
              'This is a large file. Cloud upload isn\'t available yet, so it '
              'will stay on this phone only — importing it uses local storage.',
              style: TextStyle(color: BinnacleColors.amber, fontSize: 11.5, height: 1.4),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Import')),
      ],
    );
  }
}
