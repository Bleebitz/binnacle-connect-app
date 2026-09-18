// Fakes for MediaImportService/MediaUploadService — used wherever a test
// needs to exercise the real pick -> preview -> confirm -> import (and,
// for upload, progress -> outcome) flow without touching an OS picker
// plugin or a real network.
//
// Deliberately no real dart:io Directory/File I/O here: flutter_test runs
// widget tests inside a FakeAsync zone (see AutomatedTestWidgetsFlutterBinding),
// and real async file-system operations never complete inside it (they'd
// need `tester.runAsync()`, which the widget-interaction tests using these
// fakes don't need at all once the fakes themselves are synchronous-ish).
// Production's ImagePickerMediaImportService still does real file I/O —
// that behavior is real, just not exercised by these particular tests.

import 'dart:async';

import 'package:binnacle_connect/core/services/media_import_service.dart';
import 'package:binnacle_connect/core/services/media_upload_service.dart';

/// Returns a fixed [PickedMedia] with a synthetic source path (no real
/// file backing it) from `pickPhoto`/`pickVideo`, or null when
/// [cancelNext] is set — simulating the user cancelling the system picker.
class FakeMediaImportService implements MediaImportService {
  bool cancelNext = false;
  bool failNextWithPermissionDenied = false;

  /// Every path `copyIntoAppStorage` has returned — for assertions that
  /// want to check the "imported" path was produced, without needing it
  /// to be a real file on disk.
  final List<String> importedPaths = [];

  @override
  Future<PickedMedia?> pickPhoto() async {
    if (failNextWithPermissionDenied) {
      failNextWithPermissionDenied = false;
      throw const MediaImportException(MediaImportFailure.permissionDenied, 'Photo permission denied');
    }
    if (cancelNext) {
      cancelNext = false;
      return null;
    }
    return const PickedMedia(
        kind: ImportMediaKind.photo, sourcePath: '/fake/picker/photo.jpg', fileName: 'photo.jpg', sizeBytes: 1024 * 50);
  }

  @override
  Future<PickedMedia?> pickVideo() async {
    if (failNextWithPermissionDenied) {
      failNextWithPermissionDenied = false;
      throw const MediaImportException(MediaImportFailure.permissionDenied, 'Video permission denied');
    }
    if (cancelNext) {
      cancelNext = false;
      return null;
    }
    return const PickedMedia(
        kind: ImportMediaKind.video, sourcePath: '/fake/picker/clip.mp4', fileName: 'clip.mp4', sizeBytes: 1024 * 1024 * 5);
  }

  @override
  Future<String> copyIntoAppStorage(PickedMedia media) async {
    final ext = media.kind == ImportMediaKind.photo ? 'jpg' : 'mp4';
    final path = '/fake/app_storage/imported_${importedPaths.length}.$ext';
    importedPaths.add(path);
    return path;
  }
}

/// A [MediaImportService] whose `copyIntoAppStorage` always fails — for
/// testing the real "import failed" path (disk/IO failure) distinctly
/// from a picker cancel.
class FailingCopyMediaImportService extends FakeMediaImportService {
  @override
  Future<String> copyIntoAppStorage(PickedMedia media) async {
    throw const MediaImportException(MediaImportFailure.ioError, 'Simulated disk failure');
  }
}

/// Real progress -> outcome emission, deterministic (no `Future.delayed`
/// needed for tests to observe intermediate states), so tests can assert
/// on progress fractions before the terminal event — this is what "cloud
/// upload IS available" looks like when a real backend eventually exists;
/// production ships NoOpMediaUploadService instead (see main.dart).
class FakeProgressUploadService implements MediaUploadService {
  @override
  bool get isAvailable => true;

  bool failNext = false;
  final _controllers = <String, StreamController<UploadProgressUpdate>>{};

  @override
  Stream<UploadProgressUpdate> upload({required String localPath, required String mediaId}) {
    final controller = StreamController<UploadProgressUpdate>();
    _controllers[mediaId] = controller;
    final shouldFail = failNext;
    failNext = false;
    scheduleMicrotask(() async {
      for (final f in [0.25, 0.5, 0.75]) {
        if (controller.isClosed) return;
        controller.add(UploadProgressUpdate(fraction: f));
        await Future<void>.delayed(Duration.zero);
      }
      if (controller.isClosed) return;
      if (shouldFail) {
        controller.add(const UploadProgressUpdate(outcome: UploadOutcome.failed, message: 'Simulated upload failure'));
      } else {
        controller.add(const UploadProgressUpdate(fraction: 1.0, outcome: UploadOutcome.uploaded));
      }
      await controller.close();
    });
    return controller.stream;
  }

  /// Lets a test cancel mid-upload the same way ClipRepository.cancelUpload
  /// does (by cancelling the subscription) — exposed here so a test can
  /// also simulate the *server* side dropping the connection if needed.
  void forceCancel(String mediaId) {
    _controllers[mediaId]?.close();
  }
}
