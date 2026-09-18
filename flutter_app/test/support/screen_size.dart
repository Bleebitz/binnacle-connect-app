import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

/// Flutter's default test surface is 800x600, which is LANDSCAPE. The Live
/// screen switches to the landscape camera console there, so tests of the
/// portrait Live layout must ask for a phone-shaped portrait surface.
void usePortraitPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(480, 960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// A phone held horizontally (S25 Ultra-like proportions).
void useLandscapePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(960, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
