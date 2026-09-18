// Community's real "Post a highlight" flow: select existing Library media
// or import new media, caption, choose audience, explicit Publish. There
// is no external identity/social backend, so "Crew" (real, local) is the
// only enabled audience — this verifies that boundary is enforced in the
// UI, not just documented, and that Publish produces a real, checkable
// state change (CrewSession.clipIds + Clip.caption), not a fabricated
// "posted" message with nothing behind it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:binnacle_connect/core/services/media_import_service.dart';
import 'package:binnacle_connect/core/services/media_upload_service.dart';
import 'package:binnacle_connect/ui/screens/crew_screen.dart';
import 'package:binnacle_connect/ui/screens/library_screen.dart';
import 'package:binnacle_connect/ui/theme/binnacle_theme.dart';
import 'package:binnacle_connect/ui/widgets/post_highlight_sheet.dart';

import 'support/fake_media_services.dart';

Widget _harness({
  required MediaImportService importer,
  required ClipRepository clips,
  required CrewRepository crew,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ClipRepository>.value(value: clips),
      ChangeNotifierProvider<CrewRepository>.value(value: crew),
      Provider<MediaImportService>.value(value: importer),
      Provider<MediaUploadService>.value(value: NoOpMediaUploadService()),
    ],
    child: MaterialApp(
      theme: BinnacleTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showPostHighlightSheet(context),
              child: const Text('Open sheet'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  _persistenceTests();
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('importing new media, captioning, and publishing to Crew is real end to end',
      (tester) async {
    final importer = FakeMediaImportService();
    final clips = ClipRepository();
    final crew = CrewRepository();
    await tester.pumpWidget(_harness(importer: importer, clips: clips, crew: crew));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import photo'));
    await tester.pumpAndSettle();
    expect(find.text('Import this photo?'), findsOneWidget);
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    // The imported clip is now selected in the sheet, before any publish.
    expect(crew.sessions, isEmpty); // not published yet

    await tester.enterText(find.byType(TextField), 'Nice one, Levi');
    await tester.tap(find.text('Save to Crew sessions'));
    await tester.pumpAndSettle();

    expect(find.text('Saved to Crew sessions'), findsOneWidget);
    expect(crew.sessions, hasLength(1));
    expect(clips.clips.single.caption, 'Nice one, Levi');
    expect(crew.sessions.first.clipIds, contains(clips.clips.single.id));
  });

  testWidgets('Public audience is shown but disabled, with an honest reason', (tester) async {
    final importer = FakeMediaImportService();
    final clips = ClipRepository();
    final crew = CrewRepository();
    await tester.pumpWidget(_harness(importer: importer, clips: clips, crew: crew));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();

    final publicTile = tester.widget<RadioListTile<HighlightAudience>>(
        find.byWidgetPredicate((w) => w is RadioListTile<HighlightAudience> && w.value == HighlightAudience.public));
    expect(publicTile.onChanged, isNull);
    expect(find.textContaining('requires an account/identity system'), findsOneWidget);
  });

  testWidgets('selecting an existing Library clip publishes that clip, not a new import',
      (tester) async {
    final importer = FakeMediaImportService();
    final clips = ClipRepository()..seedDemo();
    final crew = CrewRepository();
    await tester.pumpWidget(_harness(importer: importer, clips: clips, crew: crew));
    await tester.pumpAndSettle();

    final existingId = clips.clips.first.id;

    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    // Tap the first Library thumbnail (horizontal list of existing clips,
    // scoped to the ListView so this doesn't accidentally hit some other
    // GestureDetector in the sheet/modal chrome).
    final thumbsList = find.byType(ListView);
    final firstThumb = find.descendant(of: thumbsList, matching: find.byType(GestureDetector)).first;
    await tester.tap(firstThumb);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Crew sessions'));
    await tester.pumpAndSettle();

    expect(crew.sessions.first.clipIds, [existingId]);
  });
}

// Truthfulness/persistence of "Post to Crew": the entry is a local session
// record that survives an app restart, and the UI never says "Posted".
void _persistenceTests() {
  test('Crew session entries and riders survive a restart (same phone)', () async {
    SharedPreferences.setMockInitialValues({});
    final a = CrewRepository(store: CrewLocalStore());
    await a.hydrate();
    a.addRider('Mika');
    a.postHighlight('clip-1');
    // notifyListeners saves asynchronously; let it flush.
    await Future<void>.delayed(Duration.zero);

    final b = CrewRepository(store: CrewLocalStore());
    await b.hydrate();
    expect(b.riders.map((r) => r.name), contains('Mika'));
    expect(b.sessions.single.clipIds, ['clip-1']);
  });

  test('an unsent draft is persisted and cleared when saved', () async {
    SharedPreferences.setMockInitialValues({});
    final a = CrewRepository(store: CrewLocalStore());
    await a.saveDraft({'clipId': 'c', 'caption': 'hi'});
    final b = CrewRepository(store: CrewLocalStore());
    expect((await b.loadDraft())?['caption'], 'hi');
    await b.saveDraft(null);
    expect(await b.loadDraft(), isNull);
  });
}
