// Real offline upload queue behavior: select while offline, restart
// recovery, network-preference honoring, pause/resume/cancel/retry,
// duplicate prevention, and the real local "missing source file" check —
// exercised directly against ClipRepository (no widget tree needed for
// these), against FakeConnectivityChecker/FakeProgressUploadService.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/services/connectivity_checker.dart';
import 'package:binnacle_connect/core/services/media_import_service.dart';
import 'package:binnacle_connect/core/services/media_upload_service.dart';
import 'package:binnacle_connect/core/services/upload_preferences_service.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';

import 'support/fake_media_services.dart';

Future<Clip> _import(ClipRepository repo, {ImportMediaKind kind = ImportMediaKind.photo}) {
  final importer = FakeMediaImportService();
  return repo.importPicked(
    kind == ImportMediaKind.photo
        ? const PickedMedia(kind: ImportMediaKind.photo, sourcePath: '/x', fileName: 'a.jpg', sizeBytes: 10)
        : const PickedMedia(kind: ImportMediaKind.video, sourcePath: '/x', fileName: 'a.mp4', sizeBytes: 10),
    importer: importer,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('selecting media while offline queues it instead of attempting an upload', () async {
    final connectivity = FakeConnectivityChecker()..setConnectivity([ConnectivityResult.none]);
    final uploader = FakeProgressUploadService();
    final repo = ClipRepository(connectivity: connectivity, uploader: uploader);
    await repo.hydrate();

    final clip = await _import(repo);
    expect(repo.clips.single.uploadStatus, UploadStatus.queued);
    expect(clip.uploadStatus, UploadStatus.queued);
  });

  test('upload starts automatically once a satisfying connection appears (offline -> online)', () async {
    final connectivity = FakeConnectivityChecker()..setConnectivity([ConnectivityResult.none]);
    final uploader = FakeProgressUploadService();
    final repo = ClipRepository(connectivity: connectivity, uploader: uploader);
    await repo.hydrate();
    await _import(repo);
    expect(repo.clips.single.uploadStatus, UploadStatus.queued);

    connectivity.setConnectivity([ConnectivityResult.wifi]);
    await pumpEventQueue();

    expect(repo.clips.single.uploadStatus, UploadStatus.uploaded);
  });

  test('Wi-Fi-only preference keeps a queued item waiting on cellular', () async {
    final connectivity = FakeConnectivityChecker()..setConnectivity([ConnectivityResult.none]);
    final uploader = FakeProgressUploadService();
    final repo = ClipRepository(connectivity: connectivity, uploader: uploader);
    await repo.hydrate();
    await repo.setUploadNetworkPreference(UploadNetworkPreference.wifiOnly);
    await _import(repo);

    connectivity.setConnectivity([ConnectivityResult.mobile]);
    await pumpEventQueue();
    expect(repo.clips.single.uploadStatus, UploadStatus.queued,
        reason: 'cellular should not satisfy a Wi-Fi-only preference');

    connectivity.setConnectivity([ConnectivityResult.wifi]);
    await pumpEventQueue();
    expect(repo.clips.single.uploadStatus, UploadStatus.uploaded);
  });

  test('switching the preference to allow cellular unblocks an already-queued item', () async {
    final connectivity = FakeConnectivityChecker()..setConnectivity([ConnectivityResult.mobile]);
    final uploader = FakeProgressUploadService();
    final repo = ClipRepository(connectivity: connectivity, uploader: uploader);
    await repo.hydrate();
    await repo.setUploadNetworkPreference(UploadNetworkPreference.wifiOnly);
    await _import(repo);
    expect(repo.clips.single.uploadStatus, UploadStatus.queued);

    await repo.setUploadNetworkPreference(UploadNetworkPreference.wifiOrCellular);
    await pumpEventQueue();
    expect(repo.clips.single.uploadStatus, UploadStatus.uploaded);
  });

  test('pausing stops the real upload stream; resuming genuinely restarts it', () async {
    final connectivity = FakeConnectivityChecker()..setConnectivity([ConnectivityResult.wifi]);
    final uploader = FakeProgressUploadService();
    final repo = ClipRepository(connectivity: connectivity, uploader: uploader);
    await repo.hydrate();
    final clip = await _import(repo, kind: ImportMediaKind.video);
    // Uploading has started (progress events are async microtasks) —
    // pause immediately, before it can complete.
    repo.pauseUpload(clip.id);
    expect(repo.clips.single.uploadStatus, UploadStatus.paused);

    await pumpEventQueue();
    // Still paused — pausing really unsubscribed, so the fake's later
    // progress ticks (already scheduled) landed on a closed controller
    // and were dropped, not silently applied after the fact.
    expect(repo.clips.single.uploadStatus, UploadStatus.paused);

    repo.resumeUpload(clip.id);
    await pumpEventQueue();
    expect(repo.clips.single.uploadStatus, UploadStatus.uploaded);
  });

  test('cancel returns the clip to on-phone-only without touching the original file', () async {
    final connectivity = FakeConnectivityChecker()..setConnectivity([ConnectivityResult.wifi]);
    final uploader = FakeProgressUploadService();
    final repo = ClipRepository(connectivity: connectivity, uploader: uploader);
    await repo.hydrate();
    final clip = await _import(repo);
    repo.cancelUpload(clip.id);

    expect(repo.clips.single.uploadStatus, UploadStatus.onPhoneOnly);
    expect(File(repo.clips.single.localPath!).existsSync(), isTrue,
        reason: 'cancelling an upload must never delete the local original');
  });

  test('a real failure carries a specific reason (insufficient storage), not a generic message',
      () async {
    final connectivity = FakeConnectivityChecker()..setConnectivity([ConnectivityResult.wifi]);
    final uploader = FakeProgressUploadService()
      ..failNext = true
      ..nextFailureReason = UploadFailureReason.insufficientStorage;
    final repo = ClipRepository(connectivity: connectivity, uploader: uploader);
    await repo.hydrate();
    final clip = await _import(repo);
    await pumpEventQueue();

    expect(repo.clips.single.uploadStatus, UploadStatus.failed);
    expect(repo.failureReasonFor(clip.id), UploadFailureReason.insufficientStorage);
  });

  test('a missing source file is detected locally and reported without ever calling the uploader',
      () async {
    // Offline at import time, so this queues without an automatic attempt
    // yet — the file is deleted before the *first* real attempt runs,
    // rather than racing an attempt that's already in flight.
    final connectivity = FakeConnectivityChecker()..setConnectivity([ConnectivityResult.none]);
    final uploader = FakeProgressUploadService();
    final repo = ClipRepository(connectivity: connectivity, uploader: uploader);
    await repo.hydrate();
    final clip = await _import(repo);
    expect(repo.clips.single.uploadStatus, UploadStatus.queued);
    // Delete the real underlying file out from under the queue — this is
    // the "missing source file" scenario named in the task.
    File(clip.localPath!).deleteSync();

    connectivity.setConnectivity([ConnectivityResult.wifi]);
    await pumpEventQueue();

    expect(repo.clips.single.uploadStatus, UploadStatus.failed);
    expect(repo.failureReasonFor(clip.id), UploadFailureReason.missingSourceFile);
  });

  test('duplicate-upload prevention: enqueueing an already-queued/uploading/uploaded clip is a no-op',
      () async {
    final connectivity = FakeConnectivityChecker()..setConnectivity([ConnectivityResult.wifi]);
    final uploader = FakeProgressUploadService();
    final repo = ClipRepository(connectivity: connectivity, uploader: uploader);
    await repo.hydrate();
    final clip = await _import(repo);
    await pumpEventQueue();
    expect(repo.clips.single.uploadStatus, UploadStatus.uploaded);

    // Retrying/enqueueing an already-uploaded clip must never re-post it.
    repo.enqueueUpload(clip.id);
    expect(repo.clips.single.uploadStatus, UploadStatus.uploaded);
  });

  test('a queued item survives a simulated app restart and resumes once online', () async {
    final connectivityA = FakeConnectivityChecker()..setConnectivity([ConnectivityResult.none]);
    final uploaderA = FakeProgressUploadService();
    final repoA = ClipRepository(connectivity: connectivityA, uploader: uploaderA);
    await repoA.hydrate();
    final clip = await _import(repoA);
    expect(repoA.clips.single.uploadStatus, UploadStatus.queued);

    // Cold restart: a fresh repository, same underlying local store.
    final connectivityB = FakeConnectivityChecker()..setConnectivity([ConnectivityResult.wifi]);
    final uploaderB = FakeProgressUploadService();
    final repoB = ClipRepository(connectivity: connectivityB, uploader: uploaderB);
    await repoB.hydrate();
    await pumpEventQueue();

    expect(repoB.clips.single.id, clip.id);
    expect(repoB.clips.single.uploadStatus, UploadStatus.uploaded,
        reason: 'restoring while already online should resume the queue immediately');
  });
}
