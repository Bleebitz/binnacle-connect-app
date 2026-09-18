// Real pick -> preview -> confirm -> import -> submit flow for Best
// Falls, replacing the removed fake importFallClip() demo shortcut. Uses
// FakeMediaImportService (a real MediaImportService implementation, just
// with a deterministic picker instead of the OS one) so this exercises
// the actual ClipRepository.importPicked/pickAndImportMedia code path.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:binnacle_connect/core/models/fall_entry.dart';
import 'package:binnacle_connect/core/services/media_import_service.dart';
import 'package:binnacle_connect/core/services/media_upload_service.dart';
import 'package:binnacle_connect/ui/screens/best_falls_screen.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';
import 'package:binnacle_connect/ui/theme/binnacle_theme.dart';

import 'support/fake_media_services.dart';

Widget _harness({
  required MediaImportService importer,
  required MediaUploadService uploader,
  required ClipRepository clips,
  required FallRepository falls,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ClipRepository>.value(value: clips),
      Provider<MediaImportService>.value(value: importer),
      Provider<MediaUploadService>.value(value: uploader),
    ],
    child: MaterialApp(
      theme: BinnacleTheme.dark(),
      home: BestFallsScreen(repository: falls),
    ),
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('importing real footage submits a fall entry with a real source clip', (tester) async {
    final importer = FakeMediaImportService();
    final clips = ClipRepository();
    final falls = FallRepository();
    await tester.pumpWidget(_harness(
      importer: importer,
      uploader: NoOpMediaUploadService(),
      clips: clips,
      falls: falls,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit a fall'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import from Vision or phone'));
    await tester.pumpAndSettle();

    // Preview dialog appears with the real picked file's name/size —
    // confirm it, rather than the old flow's immediate fabricated submit.
    expect(find.text('Import this video?'), findsOneWidget);
    expect(find.text('clip.mp4'), findsOneWidget);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    // A real Clip was added to the Library (not just the Falls board) —
    expect(clips.clips, hasLength(1));
    expect(clips.clips.single.localPath, isNotNull);
    // And the fall entry is genuinely tied back to that real clip.
    expect(falls.ranked, hasLength(1));
    expect(falls.ranked.single.sourceClipId, clips.clips.single.id);

  });

  testWidgets('cancelling the preview imports nothing and submits nothing', (tester) async {
    final importer = FakeMediaImportService();
    final clips = ClipRepository();
    final falls = FallRepository();
    await tester.pumpWidget(_harness(
      importer: importer,
      uploader: NoOpMediaUploadService(),
      clips: clips,
      falls: falls,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit a fall'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import from Vision or phone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(clips.clips, isEmpty);
    expect(falls.ranked, isEmpty);

  });

  testWidgets('a real copy failure shows an error, not a fabricated submission', (tester) async {
    final importer = FailingCopyMediaImportService();
    final clips = ClipRepository();
    final falls = FallRepository();
    await tester.pumpWidget(_harness(
      importer: importer,
      uploader: NoOpMediaUploadService(),
      clips: clips,
      falls: falls,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit a fall'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import from Vision or phone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(clips.clips, isEmpty);
    expect(falls.ranked, isEmpty);
    expect(find.textContaining('Simulated disk failure'), findsOneWidget);

  });
}
