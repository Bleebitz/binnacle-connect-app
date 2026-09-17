import 'package:flutter/foundation.dart';

import '../app_config.dart';
import '../models/vessel_state.dart';

/// Whether a man-overboard alert is currently active, and where. Lifted out
/// of the Capture screen's local state so the rest of the app can react to
/// it too — a real MOB alert is not a "Capture tab" concern, it's an
/// app-wide one, and the bottom nav tints toward orange while this is true
/// (see main.dart's _RootShell).
///
/// BIN-9: this class used to be a bare local boolean toggled by a demo
/// button, with fixed coordinates shown regardless of build mode. It is now
/// two clearly separated paths sharing one app-wide surface:
///   - Core mode: [applyCoreEvent] mirrors whatever Core's [MobEvent] most
///     recently reported (see VesselState.mob) — this is the ONLY way
///     [active]/[lat]/[lon]/[headingDegrees] change in a Core build.
///   - Demo mode: [triggerDemo] is a local, clearly-[simulated] stand-in for
///     exercising the banner UI without hardware; it throws outside demo
///     mode so a Core build can never reach it, matching the same
///     defense-in-depth pattern as PairingService.debugSimulatePairing.
/// [acknowledgeLocally] clears the local display in both modes — it is
/// deliberately NOT how a real Core-mode acknowledgment gets its
/// authority; see capture_screen.dart's acknowledge handler, which only
/// calls it after ControlChannelService.acknowledgeMob() actually confirms
/// (and which Core's own next state update can still override, since Core
/// is always the final authority on whether the event is really over).
class MobAlertState extends ChangeNotifier {
  bool _active = false;
  String? _lat;
  String? _lon;
  double? _headingDegrees;
  bool _simulated = false;

  bool get active => _active;
  String? get lat => _lat;
  String? get lon => _lon;
  double? get headingDegrees => _headingDegrees;

  /// True only when the currently-displayed alert came from [triggerDemo],
  /// never from a real Core event — the UI uses this to render a
  /// "SIMULATED" tag so a demo alert can never be mistaken for a real one.
  bool get simulated => _simulated;

  /// DEMO ONLY. Fabricates a MOB event with fixed, clearly-simulated
  /// coordinates so the alert banner can be exercised without hardware.
  /// Throws outside demo mode — there is no corresponding "simulate an
  /// emergency" concept in a real build, and this must never be reachable
  /// in one even if a caller forgets to gate the button that invokes it.
  void triggerDemo() {
    if (!AppConfig.isDemo) throw StateError('MOB simulation is unavailable in Core mode');
    _active = true;
    _simulated = true;
    _lat = '36.02083° N';
    _lon = '114.74215° W';
    _headingDegrees = 128;
    notifyListeners();
  }

  /// Core mode's only write path. Applies Core's latest reported MOB event
  /// verbatim — never invents a location Core didn't send, never assumes
  /// "active" just because the app wants to show something.
  void applyCoreEvent(MobEvent event) {
    if (AppConfig.isDemo) return; // demo mode never takes Core-shaped data
    _active = event.active;
    _simulated = false;
    _lat = event.lat;
    _lon = event.lon;
    _headingDegrees = event.headingDegrees;
    notifyListeners();
  }

  /// Clears the local display immediately. Callers are responsible for
  /// only invoking this once they have their own authoritative reason to
  /// (an actual Core acknowledgment, or — in demo mode — the local
  /// "Acknowledge" tap, which has no Core to wait on). See the class doc.
  void acknowledgeLocally() {
    _active = false;
    _simulated = false;
    _lat = null;
    _lon = null;
    _headingDegrees = null;
    notifyListeners();
  }
}
