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
}
