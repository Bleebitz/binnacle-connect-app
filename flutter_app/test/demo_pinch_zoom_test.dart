// Two-finger pinch drives the local demo zoom; one finger never does.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:binnacle_connect/core/services/demo_media.dart';
import 'package:binnacle_connect/ui/widgets/eptz_video_view.dart';

Future<void> _pump(WidgetTester tester, DemoZoom zoom) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 225,
            child: DemoPinchZoom(
                zoom: zoom, child: const ColoredBox(color: Colors.blueGrey)),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
      'spreading two fingers zooms in, pinching them together zooms out',
      (tester) async {
    final zoom = DemoZoom();
    addTearDown(zoom.dispose);
    await _pump(tester, zoom);
    final c = tester.getCenter(find.byType(DemoPinchZoom));

    final a = await tester.startGesture(c - const Offset(30, 0), pointer: 1);
    final b = await tester.startGesture(c + const Offset(30, 0), pointer: 2);
    await a.moveTo(c - const Offset(60, 0));
    await b.moveTo(c + const Offset(60, 0));
    await tester.pump();
    expect(zoom.value, greaterThan(1.5),
        reason: 'fingers moved from 60 to 120 apart');
    expect(zoom.value, lessThanOrEqualTo(DemoZoom.max));
    final zoomedIn = zoom.value;
    await a.up();
    await b.up();
    await tester.pump();

    final a2 = await tester.startGesture(c - const Offset(80, 0), pointer: 3);
    final b2 = await tester.startGesture(c + const Offset(80, 0), pointer: 4);
    await a2.moveTo(c - const Offset(30, 0));
    await b2.moveTo(c + const Offset(30, 0));
    await tester.pump();
    expect(zoom.value, lessThan(zoomedIn));
    await a2.up();
    await b2.up();
  });

  testWidgets('a pinch clamps at the maximum and the minimum', (tester) async {
    final zoom = DemoZoom();
    addTearDown(zoom.dispose);
    await _pump(tester, zoom);
    final c = tester.getCenter(find.byType(DemoPinchZoom));

    final a = await tester.startGesture(c - const Offset(10, 0), pointer: 1);
    final b = await tester.startGesture(c + const Offset(10, 0), pointer: 2);
    await a.moveTo(c - const Offset(190, 0));
    await b.moveTo(c + const Offset(190, 0));
    await tester.pump();
    expect(zoom.value, DemoZoom.max);
    await a.moveTo(c - const Offset(1, 0));
    await b.moveTo(c + const Offset(1, 0));
    await tester.pump();
    expect(zoom.value, DemoZoom.min);
    await a.up();
    await b.up();
  });

  testWidgets('a single finger drag does not change the zoom', (tester) async {
    final zoom = DemoZoom();
    addTearDown(zoom.dispose);
    await _pump(tester, zoom);
    final c = tester.getCenter(find.byType(DemoPinchZoom));

    final g = await tester.startGesture(c, pointer: 1);
    await g.moveBy(const Offset(150, 20));
    await tester.pump();
    await g.up();
    expect(zoom.value, DemoZoom.min);
  });

  testWidgets('a pinch continues from the current button-set zoom',
      (tester) async {
    final zoom = DemoZoom()
      ..zoomIn()
      ..zoomIn(); // 2.0x
    addTearDown(zoom.dispose);
    await _pump(tester, zoom);
    final c = tester.getCenter(find.byType(DemoPinchZoom));

    final a = await tester.startGesture(c - const Offset(50, 0), pointer: 1);
    final b = await tester.startGesture(c + const Offset(50, 0), pointer: 2);
    await a.moveTo(c - const Offset(75, 0));
    await b.moveTo(c + const Offset(75, 0));
    await tester.pump();
    expect(zoom.value, greaterThan(2.5),
        reason: 'scaled 1.5x from the 2.0x start');
    await a.up();
    await b.up();
  });
}
