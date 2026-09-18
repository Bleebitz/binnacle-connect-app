// Real local media import: the system photo/video picker, plus copying
// the picked file into this app's own documents directory so it survives
// app restarts (the OS-managed picker cache/temp path is not guaranteed
// to persist). No cloud upload happens here — see media_upload_service.dart
// for that boundary, which is honestly unavailable (no backend exists;
// see BIN-41/BIN-48, both still Todo).

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

enum ImportMediaKind { photo, video }

/// What the system picker returned, before it's copied anywhere — enough
/// for a real preview (path + size), not yet imported into the Library.
class PickedMedia {
  final ImportMediaKind kind;
  final String sourcePath;
  final String fileName;
  final int sizeBytes;
  const PickedMedia({
    required this.kind,
    required this.sourcePath,
    required this.fileName,
    required this.sizeBytes,
  });
}

/// Why a pick or import attempt didn't produce media — always shown to
/// the user, never silently swallowed.
enum MediaImportFailure { permissionDenied, unsupportedFile, ioError, unknown }

class MediaImportException implements Exception {
  final MediaImportFailure reason;
  final String message;
  const MediaImportException(this.reason, this.message);
  @override
  String toString() => message;
}

abstract class MediaImportService {
  /// Null return means the user cancelled the system picker — not an error.
  Future<PickedMedia?> pickPhoto();
  Future<PickedMedia?> pickVideo();

  /// Copies an already-picked file into durable app storage, returning the
  /// new local path. Thrown [MediaImportException] on a real I/O failure
  /// (disk full, permission revoked mid-copy, source file vanished) —
  /// never a silently-empty file passed off as imported.
  Future<String> copyIntoAppStorage(PickedMedia media);
}

/// A file was picked (or a large one is about to be), pre-import — lets
/// the caller show a real preview and let the user cancel before any copy
/// happens, per "preview their selection and cancel before importing."
const largeFileWarningBytes = 200 * 1024 * 1024; // 200MB

class ImagePickerMediaImportService implements MediaImportService {
  final ImagePicker _picker;
  ImagePickerMediaImportService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  Future<PickedMedia?> _pick(ImportMediaKind kind, Future<XFile?> Function() pick) async {
    XFile? file;
    try {
      file = await pick();
    } on PlatformException catch (e) {
      // image_picker surfaces OS permission denial as a PlatformException
      // (code varies by platform/version) rather than a typed exception —
      // treat any picker-time platform failure as a permission/availability
      // problem, since that's overwhelmingly what it means in practice.
      throw MediaImportException(
        MediaImportFailure.permissionDenied,
        'Could not access photos/videos — check the app\'s permission in system settings. (${e.message ?? e.code})',
      );
    } catch (e) {
      throw MediaImportException(MediaImportFailure.unknown, 'Could not open the picker: $e');
    }
    if (file == null) return null; // user cancelled — not an error
    int size;
    try {
      size = await file.length();
    } on FileSystemException catch (e) {
      throw MediaImportException(MediaImportFailure.ioError, 'Could not read the selected file: ${e.message}');
    }
    return PickedMedia(kind: kind, sourcePath: file.path, fileName: file.name, sizeBytes: size);
  }

  @override
  Future<PickedMedia?> pickPhoto() =>
      _pick(ImportMediaKind.photo, () => _picker.pickImage(source: ImageSource.gallery));

  @override
  Future<PickedMedia?> pickVideo() =>
      _pick(ImportMediaKind.video, () => _picker.pickVideo(source: ImageSource.gallery));

  @override
  Future<String> copyIntoAppStorage(PickedMedia media) async {
    final Directory docsDir;
    try {
      docsDir = await getApplicationDocumentsDirectory();
    } on MissingPlatformDirectoryException catch (e) {
      throw MediaImportException(MediaImportFailure.ioError, 'No app storage directory available: ${e.message}');
    }
    final mediaDir = Directory('${docsDir.path}/library_media');
    try {
      await mediaDir.create(recursive: true);
      final ext = media.fileName.contains('.') ? media.fileName.split('.').last : (media.kind == ImportMediaKind.photo ? 'jpg' : 'mp4');
      final destPath = '${mediaDir.path}/${const Uuid().v4()}.$ext';
      final source = File(media.sourcePath);
      if (!await source.exists()) {
        throw const MediaImportException(
            MediaImportFailure.unsupportedFile, 'The selected file no longer exists.');
      }
      await source.copy(destPath);
      return destPath;
    } on MediaImportException {
      rethrow;
    } on FileSystemException catch (e) {
      // Covers disk-full, permission-revoked-mid-copy, and an interrupted
      // copy (e.g. storage removed) — surfaced as a real import failure,
      // never a partially-written file silently treated as imported.
      throw MediaImportException(MediaImportFailure.ioError, 'Could not save the file locally: ${e.message}');
    }
  }
}
