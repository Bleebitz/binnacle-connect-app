// Real smoke test for BinnacleConnectApp — replaces the placeholder
// counter-app test that `flutter create` generates by default, which
// referenced a nonexistent MyApp class and tested nothing about this app.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:binnacle_connect/main.dart';
import 'package:binnacle_connect/ui/widgets/connect_startup.dart';

void main() {
  setUp(() {
    // These tests exercise the app past the splash, not the splash itself
    // (see test/startup_test.dart for that) — skip it outright rather than
    // paying for a real asset-decode `runAsync` gap in every test here.
    ConnectStartup.debugSkipForTesting = true;

    // The Capture (Live) screen's simulated video background animates
    // forever (SimulatedWakeView), which would make every pumpAndSettle()
    // below hang indefinitely. Disabling animations is also what that
    // widget checks to respect a real device's reduce-motion setting.
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);

    // PairingService now defaults to SecureCredentialStore (real
    // Keychain/Keystore persistence, see pairing_service.dart), and
    // main.dart calls restore() on launch — stub the plugin's platform
    // channel so that read doesn't hit a real (nonexistent, in a test
    // binding) secure storage implementation.
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() => ConnectStartup.debugSkipForTesting = false);

  testWidgets('App launches, renders the BIN-32 nav, and starts on My Boat',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pumpAndSettle();

    // The reorganized nav — My Boat / Live / Session / Library / Community
    // — replaces Capture / Library / Crew / Compete / Settings. Crew and
    // Compete moved inside Community; Settings moved behind My Boat's
    // profile icon. None of the old five are bottom-nav tabs anymore.
    expect(find.text('My Boat'), findsWidgets);
    expect(find.text('Live'), findsWidgets);
    expect(find.text('Session'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Community'), findsWidgets);

    // Starts on My Boat — the boating-status dashboard is the front door
    // now, not the camera.
    expect(find.text('Binnacle connected'), findsOneWidget);
  });

  testWidgets("My Boat's profile icon reaches Settings (no longer a bottom-nav tab)",
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings & account'));
    await tester.pumpAndSettle();

    expect(find.text('Not paired'), findsOneWidget);
  });

  testWidgets('Live tab shows recorded Demo feed and disables vessel controls',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Live').last);
    await tester.pumpAndSettle();

    // Its custom topbar brand text is visible (a styled Text, not a native
    // AppBar — see capture_screen.dart).
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('DEMO — RECORDED CAMERA FEED'), findsOneWidget);
    expect(find.text('ACQUIRING RIDER'), findsOneWidget);
    expect(find.text('Recorded demo playback'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -520), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('camera, framing, capture, and vessel controls are disabled'),
        findsOneWidget);

    final captureControl = tester.widget<Switch>(find.byType(Switch));
    expect(captureControl.onChanged, isNull);
  });

  testWidgets('Community > Compete opens the hub, King of Wake speed-class validation works live',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Community').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compete'));
    await tester.pumpAndSettle();

    // Hub screen: all four destinations listed, none of their content shown yet.
    expect(find.text('King of Wake'), findsOneWidget);
    expect(find.text('Top Tricks'), findsOneWidget);
    expect(find.text('Best Falls'), findsOneWidget);
    expect(find.text('Riders'), findsOneWidget);

    await tester.tap(find.text('King of Wake'));
    await tester.pumpAndSettle();

    // Open the entry sheet and confirm the live class-validation text
    // actually reacts to a typed speed — this is the real logic under test,
    // not just that the screen renders.
    await tester.tap(find.text('Enter'));
    await tester.pumpAndSettle();
    expect(find.text('Enter GPS speed to see class'), findsOneWidget);

    // 10.0 mph falls inside Surf class A (9.5-10.5) per KingOfWakeClasses.
    await tester.enterText(find.widgetWithText(TextField, 'GPS speed (mph)'), '10.0');
    await tester.pump();
    expect(find.text('Class A'), findsOneWidget);

    // 10.5 mph is a real boundary shared by classes A and B — classify()
    // returns the first match checked (A), which is the intended behavior,
    // not a bug.
    await tester.enterText(find.widgetWithText(TextField, 'GPS speed (mph)'), '10.5');
    await tester.pump();
    expect(find.text('Class A'), findsOneWidget);

    // 8.0 mph is genuinely below every Surf class (bands start at 9.5) —
    // this is the real "no class" case, not the boundary case above.
    await tester.enterText(find.widgetWithText(TextField, 'GPS speed (mph)'), '8.0');
    await tester.pump();
    expect(find.textContaining('Not in range for any class'), findsOneWidget);
  });

  testWidgets('Top Tricks submit button reacts to typing (regression test for a real bug)',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Community').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top Tricks'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log a trick'));
    await tester.pumpAndSettle();

    // Button starts disabled — trick name is empty.
    final submitFinder = find.widgetWithText(FilledButton, 'Submit');
    expect(tester.widget<FilledButton>(submitFinder).onPressed, isNull);

    // The actual bug: typing did nothing because no onChanged->setState was
    // wired. Confirming the fix by checking the button actually enables.
    await tester.enterText(find.widgetWithText(TextField, 'Trick name'), 'Backroll');
    await tester.pump();
    expect(tester.widget<FilledButton>(submitFinder).onPressed, isNotNull);

    await tester.tap(submitFinder);
    await tester.pumpAndSettle();
    expect(find.text('Backroll'), findsOneWidget);
  });

  testWidgets('Best Falls submits from real footage, not a self-ticked checkbox',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Community').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Best Falls'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit a fall'));
    await tester.pumpAndSettle();

    // The old flow (free-typed rider name + a self-ticked "rider signaled
    // OK" checkbox) is gone entirely — regression-proof that it can't come
    // back, since that's exactly what made it unverifiable.
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Submit'), findsNothing);

    // Importing real footage submits immediately — no separate consent
    // re-ask, since that now lives in the account agreement made at
    // sign-up, not per submission.
    await tester.tap(find.text('Import from Vision or phone'));
    await tester.pumpAndSettle();

    // The board shows the rider (from the clip, not a free-typed name) and
    // ties the entry back to the real clip it came from.
    expect(find.text('Levi'), findsOneWidget);
    expect(find.textContaining('Verified capture · Imported fall clip'), findsOneWidget);
  });

  testWidgets('Riders aggregates points across King of Wake, Top Tricks, and Best Falls',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Community').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compete'));
    await tester.pumpAndSettle();

    // Submit one trick, then check Riders reflects it — proves the pure
    // computation actually reads live repository state, not a stale copy.
    await tester.tap(find.text('Top Tricks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log a trick'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Rider name'), 'Test Rider');
    await tester.enterText(find.widgetWithText(TextField, 'Trick name'), 'Tantrum');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    // Back to hub, into Riders.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Riders'));
    await tester.pumpAndSettle();

    expect(find.text('Test Rider'), findsOneWidget);
    expect(find.textContaining('0 wake · 1 tricks · 0 falls'), findsOneWidget);
  });
}
