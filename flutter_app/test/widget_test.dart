// Real smoke test for BinnacleConnectApp — replaces the placeholder
// counter-app test that `flutter create` generates by default, which
// referenced a nonexistent MyApp class and tested nothing about this app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:binnacle_connect/main.dart';

void main() {
  testWidgets('App launches, renders nav, and starts on Capture',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pump(const Duration(milliseconds: 500));

    // Bottom nav renders all four destinations.
    expect(find.text('Capture'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.text('Crew'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    // Starts on the Capture screen — its app bar title is visible.
    expect(find.widgetWithText(AppBar, 'Connect'), findsOneWidget);
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

  testWidgets('Compete tab opens King of Wake and speed-class validation works live',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BinnacleConnectApp());
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Compete').last);
    await tester.pumpAndSettle();
    expect(find.text('King of Wake'), findsOneWidget);

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
}
