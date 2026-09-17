// Focused layout/readability tests for Community and its children — added
// alongside the readability pass (dark navy backing on tabs/content, off-white
// primary + slateLight secondary text, filled rider-name input) rather than
// relying only on the existing app-level widget_test.dart, which never
// asserted on font sizes, contrast-relevant colors, or overflow at scaled
// text/small viewports.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:binnacle_connect/core/app_config.dart';
import 'package:binnacle_connect/core/models/fall_entry.dart';
import 'package:binnacle_connect/core/models/rider.dart';
import 'package:binnacle_connect/core/models/trick_entry.dart';
import 'package:binnacle_connect/core/models/wake_entry.dart';
import 'package:binnacle_connect/ui/screens/community_screen.dart';
import 'package:binnacle_connect/ui/screens/crew_screen.dart';
import 'package:binnacle_connect/ui/theme/binnacle_theme.dart';

Widget _harness(CrewRepository crew) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<CrewRepository>.value(value: crew),
      ChangeNotifierProvider(create: (_) => WakeRepository()),
      ChangeNotifierProvider(create: (_) => TrickRepository()),
      ChangeNotifierProvider(create: (_) => FallRepository()),
    ],
    child: MaterialApp(
      theme: BinnacleTheme.dark(),
      home: const CommunityScreen(),
    ),
  );
}

void main() {
  setUp(() {
    // BinnacleEmptyState's icon badge (Sessions' empty state) and other
    // ambient animations loop perpetually unless reduced-motion is set —
    // same reasoning as widget_test.dart's setUp — otherwise pumpAndSettle()
    // below never terminates.
    TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  });

  testWidgets(
      'Crew > Sessions: empty state renders on a solid panel, no overflow',
      (tester) async {
    await tester.pumpWidget(_harness(CrewRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No sessions yet'), findsOneWidget);
    expect(
        tester.widget<Text>(find.text('No sessions yet')).style?.fontSize, 16);
    expect(
        tester
            .widget<Text>(find.textContaining('They show up automatically'))
            .style
            ?.fontSize,
        14);
    expect(tester.takeException(), isNull);
  }, skip: !AppConfig.isDemo);

  testWidgets(
      'empty Sessions stays scrollable on a small phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_harness(CrewRepository()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
  }, skip: !AppConfig.isDemo);

  testWidgets(
      'Crew > Sessions: populated session shows readable label/location sizes',
      (tester) async {
    final crew = CrewRepository();
    crew.addSession(const CrewSession(
      id: 's1',
      label: 'Saturday',
      location: 'Lake Travis — north cove',
      riderIds: ['r0'],
      clipIds: [],
      reactions: {'🔥': 2},
    ));
    await tester.pumpWidget(_harness(crew));
    await tester.pumpAndSettle();

    expect(find.text('Saturday'), findsOneWidget);
    final label = tester.widget<Text>(find.text('Saturday'));
    expect(label.style?.fontSize, 16);

    final location = tester.widget<Text>(find.text('Lake Travis — north cove'));
    // Was 10 (mono default) before the readability pass; target ~14.
    expect(location.style?.fontSize, greaterThanOrEqualTo(14));
    expect(tester.takeException(), isNull);
  }, skip: !AppConfig.isDemo);

  testWidgets(
      'Crew > People: names/descriptions meet target sizes, input is filled',
      (tester) async {
    final crew = CrewRepository()..addRider('Mika');
    await tester.pumpWidget(_harness(crew));
    await tester.pumpAndSettle();
    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();

    // Default rider "You" plus the fixture-added "Mika".
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Mika'), findsOneWidget);

    final nameStyle = tester.widget<Text>(find.text('Mika')).style;
    expect(nameStyle?.fontSize, greaterThanOrEqualTo(16));

    final descFinder = find.text('No biometric consent on file');
    expect(descFinder, findsWidgets);
    final descStyle = tester.widget<Text>(descFinder.first).style;
    // Was fontSize: 11 before the readability pass; target ~14.
    expect(descStyle?.fontSize, greaterThanOrEqualTo(14));

    // The rider-name input has a filled dark background, not the bare
    // underline style it had before.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.filled, isTrue);
    expect(field.decoration?.fillColor, BinnacleColors.navyRaised);

    expect(tester.takeException(), isNull);
  }, skip: !AppConfig.isDemo);

  testWidgets(
      'Crew > People: Add button adds a rider through the real repository',
      (tester) async {
    final crew = CrewRepository();
    await tester.pumpWidget(_harness(crew));
    await tester.pumpAndSettle();
    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Test Rider');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Test Rider'), findsOneWidget);
    expect(crew.riders.any((r) => r.name == 'Test Rider'), isTrue);
  }, skip: !AppConfig.isDemo);

  testWidgets(
      'Community > Compete: all four destination cards meet target text sizes',
      (tester) async {
    await tester.pumpWidget(_harness(CrewRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compete'));
    await tester.pumpAndSettle();

    for (final title in [
      'King of Wake',
      'Top Tricks',
      'Best Falls',
      'Riders'
    ]) {
      final titleWidget = tester.widget<Text>(find.text(title));
      expect(titleWidget.style?.fontSize, greaterThanOrEqualTo(16),
          reason: title);
    }
    for (final subtitle in [
      'GPS-verified speed leaderboard, surf and ramp',
      'Community-voted trick leaderboard',
      'Submitted from real Vision/phone footage',
      'Season standings across all three',
    ]) {
      final subtitleWidget = tester.widget<Text>(find.text(subtitle));
      // Was 11.5 before the readability pass; target ~14.
      expect(subtitleWidget.style?.fontSize, greaterThanOrEqualTo(14),
          reason: subtitle);
    }
    expect(tester.takeException(), isNull);
  }, skip: !AppConfig.isDemo);

  testWidgets('Compete card tap still navigates (behavior preserved)',
      (tester) async {
    await tester.pumpWidget(_harness(CrewRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('King of Wake'));
    await tester.pumpAndSettle();

    expect(find.text('King of Wake'),
        findsWidgets); // now also the pushed screen's title
  }, skip: !AppConfig.isDemo);

  testWidgets(
      'larger text scale and a small phone viewport: no overflow anywhere',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568); // a genuinely small phone
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final crew = CrewRepository()
      ..addRider('A Rider With A Genuinely Long Display Name')
      ..addSession(const CrewSession(
        id: 's1',
        label: 'Today',
        location: 'A fairly long location string to test wrapping behavior',
        riderIds: ['r0'],
        clipIds: [],
      ));

    await tester.pumpWidget(_harness(crew));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Compete'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, skip: !AppConfig.isDemo);

  testWidgets('non-demo Community message renders on a readable solid panel',
      (tester) async {
    await tester.pumpWidget(_harness(CrewRepository()));
    await tester.pumpAndSettle();

    expect(
        find.textContaining(
            'Community and Compete preview remains available in Demo'),
        findsOneWidget);
    final text = tester.widget<Text>(find.textContaining(
        'Community and Compete preview remains available in Demo'));
    expect(text.style?.fontSize, greaterThanOrEqualTo(14));
    expect(text.style?.color, BinnacleColors.offWhite);
    expect(tester.takeException(), isNull);
  }, skip: AppConfig.isDemo);
}
