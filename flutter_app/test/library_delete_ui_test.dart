// Delete from the Library detail sheet: visibility rules, the confirmation
// wording, cancel vs confirm, dismissal, and failure messaging.

import 'dart:io';

import 'package:binnacle_connect/core/models/clip.dart';
import 'package:binnacle_connect/core/services/demo_media.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';
import 'package:binnacle_connect/ui/theme/binnacle_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_demo_media.dart';
import 'support/screen_size.dart';

class _Failing extends FakeDemoLibraryStore {
  bool fail = false;

  @override
  Future<void> save(List<Clip> clips) async {
    if (fail) throw const FileSystemException('disk full');
    return super.save(clips);
  }
}

class _Env {
  final Directory dir = Directory.systemTemp.createTempSync('lib_delete_ui_');
  final extractor = FakeFrameExtractor();
  final _Failing store = _Failing();
  late final storage = DemoMediaStorage(directory: () async => dir);
  late final capture =
      DemoMediaCapture(extractor: extractor, mediaDirectory: () async => dir);
  late final repo = ClipRepository(demoStore: store, demoStorage: storage);
  int _n = 0;

  /// Distinct positions give distinct titles and file names.
  Future<Clip> snapshot() async {
    final r = await capture.snapshot(
        assetPath: 'assets/demo/gopro_dev_footage.mp4',
        position: Duration(seconds: 40 + _n++));
    await repo.addDemoLocalClip(r.clip);
    return r.clip;
  }

  Future<Clip> highlight() async {
    final c = await capture.highlight(
      assetPath: 'assets/demo/gopro_dev_footage.mp4',
      position: const Duration(seconds: 60),
      sourceDuration: const Duration(seconds: 130),
      preRoll: const Duration(seconds: 15),
      postRoll: const Duration(seconds: 30),
    );
    await repo.addDemoLocalClip(c);
    return c;
  }

  void dispose() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

Future<void> _pump(WidgetTester tester, _Env e) async {
  usePortraitPhone(tester);
  await tester.pumpWidget(MaterialApp(
    theme: BinnacleTheme.dark(),
    home: Scaffold(body: LibraryScreen(repository: e.repo)),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _open(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).first);
  await tester.pumpAndSettle();
}

Finder get _deleteButton => find.byKey(const ValueKey('delete-clip'));

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(_deleteButton);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('delete-confirm')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });

  testWidgets(
      'a Snapshot shows Delete; the dialog warns that a Gallery copy may remain',
      (tester) async {
    final e = _Env();
    addTearDown(e.dispose);
    final snap = await e.snapshot();
    await _pump(tester, e);
    await _open(tester, snap.title);

    expect(_deleteButton, findsOneWidget);
    await tester.tap(_deleteButton);
    await tester.pumpAndSettle();

    expect(find.text('Delete snapshot?'), findsOneWidget);
    expect(
        find.text('This removes the snapshot from Binnacle and deletes its '
            "local Binnacle copy. A copy saved to your phone's Gallery may remain."),
        findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('Cancel leaves the Snapshot and its file untouched',
      (tester) async {
    final e = _Env();
    addTearDown(e.dispose);
    final snap = await e.snapshot();
    await _pump(tester, e);
    await _open(tester, snap.title);

    await tester.tap(_deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-cancel')));
    await tester.pumpAndSettle();

    expect(find.text('Delete snapshot?'), findsNothing);
    expect(e.repo.clips.any((c) => c.id == snap.id), isTrue);
    expect(File(snap.localPath!).existsSync(), isTrue);
    expect(_deleteButton, findsOneWidget,
        reason: 'the detail sheet stays open');
  });

  testWidgets(
      'confirming deletes the Snapshot, closes the sheet and removes the card',
      (tester) async {
    final e = _Env();
    addTearDown(e.dispose);
    final keep = await e.snapshot();
    final snap = await e.snapshot();
    await _pump(tester, e);
    await _open(tester, snap.title);

    await _confirm(tester);

    expect(e.repo.clips.any((c) => c.id == snap.id), isFalse);
    expect(File(snap.localPath!).existsSync(), isFalse);
    expect(find.text('Snapshot deleted'), findsOneWidget);
    expect(_deleteButton, findsNothing, reason: 'the detail sheet is gone');
    expect(e.store.saved.any((c) => c.id == snap.id), isFalse);
    expect(e.repo.clips.any((c) => c.id == keep.id), isTrue);
  });

  testWidgets(
      'a Highlight shows Delete and says the source footage is not deleted',
      (tester) async {
    final e = _Env();
    addTearDown(e.dispose);
    final hl = await e.highlight();
    await _pump(tester, e);
    await _open(tester, hl.title);

    expect(_deleteButton, findsOneWidget);
    await tester.tap(_deleteButton);
    await tester.pumpAndSettle();
    expect(find.text('Delete highlight?'), findsOneWidget);
    expect(
        find.text(
            'This removes the saved Highlight from your Binnacle Library. '
            'The recorded Demo source footage will not be deleted.'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Highlight deleted'), findsOneWidget);
    expect(e.repo.clips.any((c) => c.id == hl.id), isFalse);
    expect(File('assets/demo/gopro_dev_footage.mp4').existsSync(), isTrue);
  });

  testWidgets('deleting the latest item promotes the next one without crashing',
      (tester) async {
    final e = _Env();
    addTearDown(e.dispose);
    final older = await e.snapshot();
    final newest = await e.snapshot();
    await _pump(tester, e);
    expect(e.repo.clips.first.id, newest.id);

    await _open(tester, newest.title);
    await _confirm(tester);

    expect(tester.takeException(), isNull);
    expect(e.repo.clips.first.id, older.id);
    expect(find.text(older.title), findsWidgets);
  });

  testWidgets('built-in Demo content offers no Delete and explains why',
      (tester) async {
    final e = _Env();
    addTearDown(e.dispose);
    e.repo.seedDemo();
    await _pump(tester, e);
    await _open(tester, e.repo.clips.first.title);

    expect(_deleteButton, findsNothing);
    expect(find.byKey(const ValueKey('built-in-note')), findsOneWidget);
  });

  testWidgets('a Core clip offers no Delete', (tester) async {
    final e = _Env();
    addTearDown(e.dispose);
    e.repo.add(Clip(
      id: 'core-1',
      title: 'From the vessel',
      duration: const Duration(seconds: 20),
      kind: ClipKind.highlight,
      riderId: 'levi',
      capturedAt: DateTime(2026, 9, 18),
      mediaUrl: 'https://core.invalid/clip.mp4',
    ));
    await _pump(tester, e);
    await _open(tester, 'From the vessel');

    expect(_deleteButton, findsNothing);
    expect(find.byKey(const ValueKey('built-in-note')), findsNothing);
  });

  testWidgets(
      'if the deletion cannot be saved the item stays and an error is shown',
      (tester) async {
    final e = _Env();
    addTearDown(e.dispose);
    final snap = await e.snapshot();
    await _pump(tester, e);
    await _open(tester, snap.title);
    e.store.fail = true;

    await _confirm(tester);

    expect(find.text("Couldn't delete this item. Try again."), findsOneWidget);
    expect(find.text('Snapshot deleted'), findsNothing);
    expect(e.repo.clips.any((c) => c.id == snap.id), isTrue);
    expect(File(snap.localPath!).existsSync(), isTrue);
    expect(find.textContaining('FileSystemException'), findsNothing,
        reason: 'no low-level error text for the user');
    expect(_deleteButton, findsOneWidget, reason: 'the sheet stays open');
  });
}
