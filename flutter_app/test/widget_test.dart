// Real smoke test for BinnacleConnectApp — replaces the placeholder
// counter-app test that `flutter create` generates by default, which
// referenced a nonexistent MyApp class and tested nothing about this app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:binnacle_connect/main.dart';

void main() {
  setUp(() {
    // The Capture screen's simulated video background animates forever
    // (SimulatedWakeView), which would make every pumpAndSettle() below
    // hang indefinitely. Disabling animations is also what that widget
    // checks to respect a real device's reduce-motion setting.
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });

  testWidgets('App launches, renders nav, and starts on Capture',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pump(const Duration(milliseconds: 500));

    // Bottom nav renders all four destinations.
    expect(find.text('Capture'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Crew'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    // Starts on the Capture screen — its custom topbar brand text is
    // visible (a styled Text, not a native AppBar — see capture_screen.dart).
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('Navigating to Settings shows pairing status',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(find.text('Not paired'), findsOneWidget);
  });

  testWidgets('Simulated capture screen shows link badge',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('SIMULATED'), findsWidgets);
  });

  testWidgets('Compete tab opens the hub, King of Wake speed-class validation works live',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Compete').last);
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
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Compete').last);
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
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Compete').last);
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
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Compete').last);
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
