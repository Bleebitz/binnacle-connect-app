// Snapshot / Save Highlight service behavior with real files (plain test(),
// not testWidgets: async dart:io needs the real zone), plus Demo Library
// persistence across a simulated restart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/services/demo_media.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';

import 'support/fake_demo_media.dart';

const _asset = 'assets/demo/gopro_dev_footage.mp4';
const _src = Duration(seconds: 130);

void main() {
  late Directory dir;
  late FakeFrameExtractor extractor;
  late DemoMediaCapture capture;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('demo_media_test_');
    extractor = FakeFrameExtractor();
    capture = DemoMediaCapture(
      extractor: extractor,
      mediaDirectory: () async => dir,
      now: () => DateTime.utc(2026, 9, 18, 12, 0, 0, 123),
    );
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('snapshot', () {
    test('extracts the frame at the given playback position into a real file',
        () async {
      final result = await capture.snapshot(
        assetPath: _asset,
        position: const Duration(seconds: 62, milliseconds: 500),
      );

      expect(extractor.requests, hasLength(1));
      expect(extractor.requests.single.asset, _asset);
      expect(extractor.requests.single.position,
          const Duration(seconds: 62, milliseconds: 500));

      final clip = result.clip;
      expect(clip.kind, ClipKind.photo);
      expect(clip.origin, ClipOrigin.demoLocalCapture);
      expect(clip.isDemoOrigin, isTrue);
      expect(clip.mediaUrl, isNull, reason: 'never a Core URL');
      expect(clip.signed, isFalse, reason: 'not signed on Vision');
      expect(clip.gpsAttached, isFalse);
      expect(clip.title, 'Snapshot — 1:02');
      expect(File(clip.localPath!).existsSync(), isTrue);
      expect(File(clip.localPath!).lengthSync(), greaterThan(0));
      expect(clip.thumbnailPath, clip.localPath);
      expect(result.galleryUri, isNotNull);
      expect(extractor.exported.single, startsWith('Binnacle_Demo_'));
    });

    test('a failed extraction throws and leaves no file behind', () async {
      extractor.failWith = FrameExtractionException('decoder unavailable');
      await expectLater(
        capture.snapshot(
            assetPath: _asset, position: const Duration(seconds: 5)),
        throwsA(isA<FrameExtractionException>()
            .having((e) => e.message, 'message', 'decoder unavailable')),
      );
      expect(dir.listSync(), isEmpty);
      expect(extractor.exported, isEmpty, reason: 'nothing to export');
    });

    test('an empty image file is an error, never a saved snapshot', () async {
      extractor.writeEmptyFile = true;
      await expectLater(
        capture.snapshot(
            assetPath: _asset, position: const Duration(seconds: 5)),
        throwsA(isA<FrameExtractionException>()),
      );
      expect(dir.listSync(), isEmpty, reason: 'the empty file is removed');
      expect(extractor.exported, isEmpty);
    });

    test('a gallery export failure does not lose the in-app snapshot',
        () async {
      extractor.galleryUri = null;
      final result = await capture.snapshot(
          assetPath: _asset, position: const Duration(seconds: 5));
      expect(result.galleryUri, isNull);
      expect(File(result.clip.localPath!).existsSync(), isTrue);
    });
  });

  group('highlight', () {
    test('is a segment reference into the bundled source, not a copy',
        () async {
      final clip = await capture.highlight(
        assetPath: _asset,
        position: const Duration(seconds: 60),
        sourceDuration: _src,
        preRoll: const Duration(seconds: 15),
        postRoll: const Duration(seconds: 30),
      );

      expect(clip.kind, ClipKind.highlight);
      expect(clip.origin, ClipOrigin.demoSegment);
      expect(clip.mediaUrl, isNull);
      expect(
          clip.segment,
          const MediaSegment(
              assetPath: _asset,
              start: Duration(seconds: 45),
              end: Duration(seconds: 90)));
      expect(clip.duration, const Duration(seconds: 45));
      expect(clip.title, 'Highlight — 0:45–1:30');

      // Only a small thumbnail image is written: no video is duplicated.
      final files = dir.listSync().whereType<File>().toList();
      expect(files.where((f) => f.path.endsWith('.mp4')), isEmpty);
      expect(files.single.path, endsWith('_thumb.jpg'));
      expect(File(clip.thumbnailPath!).uri.pathSegments.last,
          files.single.uri.pathSegments.last);
    });

    test('near the beginning and the end the window clamps to the source',
        () async {
      final early = await capture.highlight(
        assetPath: _asset,
        position: const Duration(seconds: 4),
        sourceDuration: _src,
        preRoll: const Duration(seconds: 15),
        postRoll: const Duration(seconds: 30),
      );
      expect(early.segment!.start, Duration.zero);
      expect(early.segment!.end, const Duration(seconds: 34));
      expect(early.duration, const Duration(seconds: 34));

      final late = await capture.highlight(
        assetPath: _asset,
        position: const Duration(seconds: 128),
        sourceDuration: _src,
        preRoll: const Duration(seconds: 15),
        postRoll: const Duration(seconds: 30),
      );
      expect(late.segment!.start, const Duration(seconds: 113));
      expect(late.segment!.end, _src);
      expect(late.duration, const Duration(seconds: 17));
    });

    test('a thumbnail failure does not stop the highlight from being saved',
        () async {
      extractor.failWith = FrameExtractionException('no frame');
      final clip = await capture.highlight(
        assetPath: _asset,
        position: const Duration(seconds: 60),
        sourceDuration: _src,
        preRoll: const Duration(seconds: 15),
        postRoll: const Duration(seconds: 30),
      );
      expect(clip.segment, isNotNull);
      expect(clip.thumbnailPath, isNull);
    });
  });

  group('Demo Library persistence', () {
    Future<Clip> snap(DemoMediaCapture c, int seconds) async => (await c
            .snapshot(assetPath: _asset, position: Duration(seconds: seconds)))
        .clip;

    test('saved snapshots and highlights come back after a restart', () async {
      final store = FakeDemoLibraryStore();
      final session1 = ClipRepository(demoStore: store)..seedDemo();
      final photo = await snap(capture, 20);
      final highlight = await capture.highlight(
        assetPath: _asset,
        position: const Duration(seconds: 60),
        sourceDuration: _src,
        preRoll: const Duration(seconds: 15),
        postRoll: const Duration(seconds: 30),
      );
      await session1.addDemoLocalClip(photo);
      await session1.addDemoLocalClip(highlight);

      // "Restart": a fresh repository over the same storage.
      final session2 = ClipRepository(demoStore: store)..seedDemo();
      await session2.hydrateDemo();

      final ids = session2.clips.map((c) => c.id).toList();
      expect(ids, containsAll([photo.id, highlight.id]));
      final restoredHighlight =
          session2.clips.firstWhere((c) => c.id == highlight.id);
      expect(restoredHighlight.segment, highlight.segment);
      expect(restoredHighlight.origin, ClipOrigin.demoSegment);
      final restoredPhoto = session2.clips.firstWhere((c) => c.id == photo.id);
      expect(File(restoredPhoto.localPath!).existsSync(), isTrue);
    });

    test('seeded showcase clips are not persisted', () async {
      final store = FakeDemoLibraryStore();
      final repo = ClipRepository(demoStore: store)..seedDemo();
      await repo.addDemoLocalClip(await snap(capture, 20));
      expect(store.saved.where((c) => c.id.startsWith('seed-')), isEmpty);
      expect(store.saved, hasLength(1));
    });

    test('a snapshot whose image file was deleted is dropped on restore',
        () async {
      final store = FakeDemoLibraryStore();
      final repo = ClipRepository(demoStore: store)..seedDemo();
      final photo = await snap(capture, 20);
      await repo.addDemoLocalClip(photo);
      File(photo.localPath!).deleteSync();

      final restarted = ClipRepository(demoStore: store)..seedDemo();
      await restarted.hydrateDemo();
      expect(restarted.clips.map((c) => c.id), isNot(contains(photo.id)));
    });

    test('a favorite toggled on a demo clip is persisted', () async {
      final store = FakeDemoLibraryStore();
      final repo = ClipRepository(demoStore: store)..seedDemo();
      final photo = await snap(capture, 20);
      await repo.addDemoLocalClip(photo);
      repo.toggleFavorite(photo.id);
      await Future<void>.delayed(Duration.zero);
      expect(store.saved.single.favorite, isTrue);
    });

    test('hydrating twice does not duplicate clips', () async {
      final store = FakeDemoLibraryStore();
      final repo = ClipRepository(demoStore: store)..seedDemo();
      await repo.addDemoLocalClip(await snap(capture, 20));
      await repo.hydrateDemo();
      await repo.hydrateDemo();
      expect(repo.clips.where((c) => c.origin == ClipOrigin.demoLocalCapture),
          hasLength(1));
    });

    test('Core-origin clips cannot be added through the demo path', () async {
      final repo = ClipRepository(demoStore: FakeDemoLibraryStore());
      await expectLater(
        repo.addDemoLocalClip(Clip(
          id: 'c1',
          title: 'core',
          duration: Duration.zero,
          kind: ClipKind.photo,
          riderId: 'x',
          capturedAt: DateTime(2026),
        )),
        throwsArgumentError,
      );
    });

    test(
        'the shared_preferences store round-trips real clips and survives corrupt data',
        () async {
      final store = SharedPrefsDemoLibraryStore();
      final highlight = await capture.highlight(
        assetPath: _asset,
        position: const Duration(seconds: 60),
        sourceDuration: _src,
        preRoll: const Duration(seconds: 15),
        postRoll: const Duration(seconds: 30),
      );
      await store.save([highlight]);
      final loaded = await SharedPrefsDemoLibraryStore().load();
      expect(loaded.single.segment, highlight.segment);

      SharedPreferences.setMockInitialValues({'demo_library_v1': 'not json'});
      expect(await SharedPrefsDemoLibraryStore().load(), isEmpty);
      SharedPreferences.setMockInitialValues({
        'demo_library_v1': '[{"id":"x"}, 5, null]',
      });
      expect(await SharedPrefsDemoLibraryStore().load(), isEmpty);
    });
  });
}
