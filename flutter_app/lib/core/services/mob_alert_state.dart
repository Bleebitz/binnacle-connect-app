import 'package:flutter/foundation.dart';

/// Whether a man-overboard alert is currently active. Lifted out of the
/// Capture screen's local state (where it started as a demo-only toggle)
/// so the rest of the app can react to it too — a real MOB alert is not a
/// "Capture tab" concern, it's an app-wide one, and the bottom nav now
/// tints toward orange while this is true (see main.dart's _RootShell) as
/// a small piece of context-aware theming: chrome that reflects what's
/// actually happening, not just a fixed palette.
class MobAlertState extends ChangeNotifier {
  bool _active = false;
  bool get active => _active;

  void trigger() {
    _active = true;
    notifyListeners();
  }

  void acknowledge() {
    _active = false;
    notifyListeners();
  }
}
