// Deleting local Demo media: what may be deleted, what must never be, and what
// happens when persistence or cleanup fails. Uses real temp files and synchronous
// I/O (async dart:io hangs under the widget-test FakeAsync zone).

import 'dart:io';

import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/services/demo_media.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_demo_media.dart';

const _bundledAsset = 'assets/demo/gopro_dev_footage.mp4';

/// Cleanup that always reports a failure, to prove a stuck file does not bring
/// a deleted item back.
class _FailingCleanupStorage extends DemoMediaStorage {
  _FailingCleanupStorage(Directory dir) : super(directory: () async => dir);

  @override
  Future<DemoCleanupResult> deleteOwned(Iterable<String?> paths) async =>
      DemoCleanupResult(
          failed: {
        for (final p in paths)
          if (p != null) p
      }.toList());
}

/// A store whose writes fail.
class _FailingStore extends FakeDemoLibraryStore {
  bool failSaves = false;

  @override
  Future<void> save(List<Clip> clips) async {
    if (failSaves) throw const FileSystemException('disk full');
    return super.save(clips);
  }
}

class _Env {
  final Directory dir = Directory.systemTemp.createTempSync('delete_test_');
  final Directory outside = Directory.systemTemp.createTempSync('outside_');
  final FakeFrameExtractor extractor = FakeFrameExtractor();
  final _FailingStore store = _FailingStore();
  late final DemoMediaStorage storage =
      DemoMediaStorage(directory: () async => dir);
  late final DemoMediaCapture capture =
      DemoMediaCapture(extractor: extractor, mediaDirectory: () async => dir);
  late ClipRepository repo =
      ClipRepository(demoStore: store, demoStorage: storage);

  Future<Clip> snapshot({int seconds = 47}) async {
    final r = await capture.snapshot(
        assetPath: _bundledAsset, position: Duration(seconds: seconds));
    await repo.addDemoLocalClip(r.clip);
    return r.clip;
  }

  Future<Clip> highlight({int seconds = 47}) async {
    final c = await capture.highlight(
      assetPath: _bundledAsset,
      position: Duration(seconds: seconds),
      sourceDuration: const Duration(seconds: 130),
      preRoll: const Duration(seconds: 15),
      postRoll: const Duration(seconds: 30),
    );
    await repo.addDemoLocalClip(c);
    return c;
  }

  ClipRepository reload() {
    final fresh = ClipRepository(demoStore: store, demoStorage: storage);
    return fresh;
  }

  void dispose() {
    for (final d in [dir, outside]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  }
}

void main() {
  group('DemoMediaStorage path safety', () {
    late _Env e;
    setUp(() => e = _Env());
    tearDown(() => e.dispose());

    test('only regular files strictly inside the owned directory are owned',
        () async {
      final inside = File('${e.dir.path}/snapshot_1.jpg')
        ..writeAsBytesSync([1]);
      final nested = Directory('${e.dir.path}/sub')..createSync();
      final nestedFile = File('${nested.path}/a.jpg')..writeAsBytesSync([1]);
      final elsewhere = File('${e.outside.path}/x.jpg')..writeAsBytesSync([1]);

      expect(await e.storage.isOwned(inside.path), isTrue);
      expect(await e.storage.isOwned(nestedFile.path), isTrue);
      expect(await e.storage.isOwned(elsewhere.path), isFalse);
      expect(await e.storage.isOwned(e.dir.path), isFalse,
          reason: 'the directory itself');
      expect(await e.storage.isOwned('${e.dir.path}/'), isFalse);
      expect(await e.storage.isOwned(''), isFalse);
      expect(await e.storage.isOwned(null), isFalse);
      expect(await e.storage.isOwned(_bundledAsset), isFalse,
          reason: 'an asset key is not an owned file');
    });

    test('.. traversal out of the directory is refused', () async {
      final elsewhere = File('${e.outside.path}/x.jpg')..writeAsBytesSync([1]);
      final name = elsewhere.uri.pathSegments.last;
      final outsideName =
          e.outside.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final sneaky = '${e.dir.path}/../$outsideName/$name';
      expect(await e.storage.isOwned(sneaky), isFalse);

      final res = await e.storage.deleteOwned([sneaky]);
      expect(res.refused, isNotEmpty);
      expect(elsewhere.existsSync(), isTrue);
    });

    test('a sibling directory that merely shares the prefix is refused',
        () async {
      final sibling = Directory('${e.dir.path}_evil')..createSync();
      addTearDown(() {
        if (sibling.existsSync()) sibling.deleteSync(recursive: true);
      });
      final f = File('${sibling.path}/x.jpg')..writeAsBytesSync([1]);
      expect(await e.storage.isOwned(f.path), isFalse);
      await e.storage.deleteOwned([f.path]);
      expect(f.existsSync(), isTrue);
    });

    test('deleteOwned removes owned files, deduplicates, and tolerates missing',
        () async {
      final f = File('${e.dir.path}/snapshot_2.jpg')..writeAsBytesSync([1, 2]);
      final missing = '${e.dir.path}/gone.jpg';
      final res =
          await e.storage.deleteOwned([f.path, f.path, missing, null, '']);
      expect(res.deleted, [f.path], reason: 'listed twice, deleted once');
      expect(res.alreadyMissing, [missing]);
      expect(res.failed, isEmpty);
      expect(f.existsSync(), isFalse);
    });

    test('a directory inside the owned directory is never removed', () async {
      final sub = Directory('${e.dir.path}/keepme')..createSync();
      final res = await e.storage.deleteOwned([sub.path]);
      expect(res.refused, [sub.path]);
      expect(sub.existsSync(), isTrue);
    });

    test('the bundled demo footage is never deleted, by any spelling',
        () async {
      final asset = File(_bundledAsset);
      expect(asset.existsSync(), isTrue, reason: 'tests run from flutter_app');
      final size = asset.lengthSync();
      final res =
          await e.storage.deleteOwned([_bundledAsset, asset.absolute.path]);
      expect(res.deleted, isEmpty);
      expect(res.refused.length, 2);
      expect(asset.existsSync(), isTrue);
      expect(asset.lengthSync(), size);
    });
  });

  group('ClipRepository.deleteClip', () {
    late _Env e;
    setUp(() => e = _Env());
    tearDown(() => e.dispose());

    test('deleting a Snapshot removes the record, its metadata and its JPEG',
        () async {
      final snap = await e.snapshot();
      final file = File(snap.localPath!);
      expect(file.existsSync(), isTrue);
      expect(snap.thumbnailPath, snap.localPath,
          reason: 'a Snapshot lists the same JPEG twice');

      final res = await e.repo.deleteClip(snap.id);

      expect(res.outcome, DeleteClipOutcome.deleted);
      expect(e.repo.clips.any((c) => c.id == snap.id), isFalse);
      expect(e.store.saved.any((c) => c.id == snap.id), isFalse);
      expect(file.existsSync(), isFalse);
    });

    test(
        'deleting a Highlight removes its record and thumbnail but never the source',
        () async {
      final asset = File(_bundledAsset);
      final size = asset.lengthSync();
      final hl = await e.highlight();
      expect(hl.origin, ClipOrigin.demoSegment);
      final thumb = hl.thumbnailPath;
      expect(thumb, isNotNull);
      expect(File(thumb!).existsSync(), isTrue);

      final res = await e.repo.deleteClip(hl.id);

      expect(res.outcome, DeleteClipOutcome.deleted);
      expect(e.repo.clips.any((c) => c.id == hl.id), isFalse);
      expect(e.store.saved.any((c) => c.id == hl.id), isFalse);
      expect(File(thumb).existsSync(), isFalse);
      expect(asset.existsSync(), isTrue);
      expect(asset.lengthSync(), size);
    });

    test('a highlight without a thumbnail deletes cleanly', () async {
      e.extractor.failWith = FrameExtractionException('no thumbnail');
      final hl = await e.highlight();
      expect(hl.thumbnailPath, isNull);
      final res = await e.repo.deleteClip(hl.id);
      expect(res.outcome, DeleteClipOutcome.deleted);
    });

    test('deleted items do not come back after a restart', () async {
      final snap = await e.snapshot();
      final hl = await e.highlight(seconds: 90);
      final keep = await e.snapshot(seconds: 12);

      await e.repo.deleteClip(snap.id);
      await e.repo.deleteClip(hl.id);

      final fresh = e.reload();
      await fresh.hydrateDemo();
      final ids = fresh.clips.map((c) => c.id).toList();
      expect(ids, contains(keep.id));
      expect(ids, isNot(contains(snap.id)));
      expect(ids, isNot(contains(hl.id)));
    });

    test('an unknown id is reported, not thrown', () async {
      final res = await e.repo.deleteClip('nope');
      expect(res.outcome, DeleteClipOutcome.notFound);
      expect(res.removedFromLibrary, isFalse);
    });

    test('built-in Demo content is protected because it would just return',
        () async {
      e.repo.seedDemo();
      final seed = e.repo.clips.firstWhere((c) => c.id.startsWith('seed-'));
      expect(e.repo.canDelete(seed), isFalse);
      final before = e.repo.clips.length;
      final res = await e.repo.deleteClip(seed.id);
      expect(res.outcome, DeleteClipOutcome.notDeletable);
      expect(e.repo.clips.length, before);
    });

    test(
        'a Core clip cannot be deleted locally (no Core delete contract exists)',
        () async {
      final core = Clip(
        id: 'core-1',
        title: 'From the vessel',
        duration: const Duration(seconds: 20),
        kind: ClipKind.highlight,
        riderId: 'levi',
        capturedAt: DateTime(2026, 9, 18),
        mediaUrl: 'https://core.invalid/clip.mp4',
      );
      e.repo.add(core);
      expect(core.origin, ClipOrigin.core);
      expect(e.repo.canDelete(core), isFalse);
      final res = await e.repo.deleteClip(core.id);
      expect(res.outcome, DeleteClipOutcome.notDeletable);
      expect(e.repo.clips.any((c) => c.id == 'core-1'), isTrue);
    });

    test('if the removal cannot be saved nothing is deleted and the item stays',
        () async {
      final snap = await e.snapshot();
      final file = File(snap.localPath!);
      e.store.failSaves = true;

      final res = await e.repo.deleteClip(snap.id);

      expect(res.outcome, DeleteClipOutcome.persistenceFailed);
      expect(res.removedFromLibrary, isFalse);
      expect(e.repo.clips.any((c) => c.id == snap.id), isTrue);
      expect(file.existsSync(), isTrue, reason: 'no file is touched');
      // And it really is still persisted, so a restart still shows it.
      e.store.failSaves = false;
      expect(e.store.saved.any((c) => c.id == snap.id), isTrue);
    });

    test('a failed rollback keeps list order', () async {
      final a = await e.snapshot(seconds: 10);
      final b = await e.snapshot(seconds: 20);
      final c = await e.snapshot(seconds: 30);
      final before = e.repo.clips.map((x) => x.id).toList();
      e.store.failSaves = true;
      await e.repo.deleteClip(b.id);
      expect(e.repo.clips.map((x) => x.id).toList(), before);
      expect([a.id, b.id, c.id].every(before.contains), isTrue);
    });

    test('a cleanup failure leaves the item deleted and reports the orphan',
        () async {
      final repo = ClipRepository(
          demoStore: e.store, demoStorage: _FailingCleanupStorage(e.dir));
      final snap = (await e.capture.snapshot(
              assetPath: _bundledAsset, position: const Duration(seconds: 5)))
          .clip;
      await repo.addDemoLocalClip(snap);

      final res = await repo.deleteClip(snap.id);

      expect(res.outcome, DeleteClipOutcome.deletedCleanupIncomplete);
      expect(res.removedFromLibrary, isTrue);
      expect(res.orphanedFiles, [snap.localPath]);
      expect(repo.clips.any((c) => c.id == snap.id), isFalse);
      expect(e.store.saved.any((c) => c.id == snap.id), isFalse);
    });

    test(
        'corrupt metadata pointing outside the owned directory never deletes that file',
        () async {
      final victim = File('${e.outside.path}/precious.jpg')
        ..writeAsBytesSync([9]);
      final bad = Clip(
        id: 'demo-snap-evil',
        title: 'Snapshot — evil',
        duration: Duration.zero,
        kind: ClipKind.photo,
        riderId: 'levi',
        capturedAt: DateTime(2026, 9, 18),
        origin: ClipOrigin.demoLocalCapture,
        localPath: victim.path,
        thumbnailPath:
            '${e.dir.path}/../${e.outside.uri.pathSegments.where((s) => s.isNotEmpty).last}/precious.jpg',
      );
      e.repo.add(bad);

      final res = await e.repo.deleteClip(bad.id);

      expect(res.outcome, DeleteClipOutcome.deleted,
          reason: 'the record goes; the foreign file is simply left alone');
      expect(victim.existsSync(), isTrue);
    });

    test('the pending open request for a deleted clip is cleared', () async {
      final snap = await e.snapshot();
      e.repo.requestOpen(snap.id);
      await e.repo.deleteClip(snap.id);
      expect(e.repo.takePendingOpen(), isNull);
    });

    test('a Snapshot delete does not touch the gallery copy', () async {
      final snap = await e.snapshot();
      expect(e.extractor.exported, isNotEmpty,
          reason: 'the snapshot was exported to the gallery');
      final exportedBefore = List.of(e.extractor.exported);
      await e.repo.deleteClip(snap.id);
      // There is no gallery-delete call at all, so the extractor saw nothing new.
      expect(e.extractor.exported, exportedBefore);
    });
  });
}
