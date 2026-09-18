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
import 'dart:io';

import 'package:binnacle_connect/core/services/connectivity_checker.dart';
import 'package:binnacle_connect/core/services/media_import_service.dart';
import 'package:binnacle_connect/core/services/media_upload_service.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Real, no-platform-channel stand-in for connectivity_plus's own default
/// `MethodChannelConnectivity` — set globally
/// (`ConnectivityPlatform.instance = FakeConnectivityPlatform()`) in any
/// test that pumps the full app (main.dart's `BinnacleConnectApp`), since
/// those tests have no seam to inject `ConnectivityChecker` directly at
/// `ClipRepository` construction. Tests that construct `ClipRepository`
/// themselves should prefer injecting `FakeConnectivityChecker` instead —
/// this one exists only because the app-level tests can't.
class FakeConnectivityPlatform extends ConnectivityPlatform with MockPlatformInterfaceMixin {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => const Stream.empty();
}

/// A real implementation of the interface, deterministic and with no
/// platform channel involved — see connectivity_checker.dart for why
/// ClipRepository depends on this abstraction instead of connectivity_plus's
/// `Connectivity` directly. Defaults to "online, Wi-Fi" so existing tests
/// that don't care about connectivity keep working unchanged; tests of the
/// offline queue itself construct one and call [setConnectivity] to drive
/// real state transitions.
class FakeConnectivityChecker implements ConnectivityChecker {
  List<ConnectivityResult> _current = const [ConnectivityResult.wifi];
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> check() async => _current;

  @override
  Stream<List<ConnectivityResult>> get onChanged => _controller.stream;

  void setConnectivity(List<ConnectivityResult> results) {
    _current = results;
    _controller.add(results);
  }

  void dispose() => _controller.close();
}

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
    // A real (tiny) file, not just a string path — ClipRepository does a
    // real File.existsSync() check before every upload attempt (the
    // "missing source file" failure mode), so a synthetic never-created
    // path would incorrectly look like a missing file. Sync I/O only
    // (createSync/writeAsBytesSync): safe under flutter_test's FakeAsync
    // zone, unlike the async File APIs — see this file's module comment.
    final dir = Directory.systemTemp.createTempSync('fake_app_storage');
    final file = File('${dir.path}/imported_${importedPaths.length}.$ext');
    file.writeAsBytesSync(const [0]);
    importedPaths.add(file.path);
    return file.path;
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

  @override
  bool get supportsResume => true;

  bool failNext = false;
  /// Set before an upload to make the next failure carry a specific
  /// reason (expired auth / insufficient storage / connection lost) —
  /// lets tests prove the UI surfaces each one distinctly, not just a
  /// generic "failed."
  UploadFailureReason? nextFailureReason;
  final _controllers = <String, StreamController<UploadProgressUpdate>>{};

  @override
  Stream<UploadProgressUpdate> upload({required String localPath, required String mediaId}) {
    final controller = StreamController<UploadProgressUpdate>();
    _controllers[mediaId] = controller;
    final shouldFail = failNext;
    final failureReason = nextFailureReason;
    failNext = false;
    nextFailureReason = null;
    scheduleMicrotask(() async {
      for (final f in [0.25, 0.5, 0.75]) {
        if (controller.isClosed) return;
        controller.add(UploadProgressUpdate(fraction: f));
        await Future<void>.delayed(Duration.zero);
      }
      if (controller.isClosed) return;
      if (shouldFail) {
        controller.add(UploadProgressUpdate(
          outcome: UploadOutcome.failed,
          failureReason: failureReason ?? UploadFailureReason.unknown,
          message: 'Simulated upload failure',
        ));
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
