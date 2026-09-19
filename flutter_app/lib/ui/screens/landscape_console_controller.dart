// Presentation-only state for the landscape Live camera console.
//
// Nothing authoritative lives here. Zoom, Track state, Rider Lock, the
// recorded playback position, Core connection and saved media all live in their
// own domain objects (DemoZoom, VisionTrackState, DemoRiderLock,
// DemoRecordedCameraSource, ControlChannelService, ClipRepository). This object
// only remembers what the console is currently *showing*: whether the controls
// are faded out, whether Clean View is on, and the short-lived Snapshot
// thumbnail. It is owned by the Live screen (not by the console widget), so
// rotating the phone back and forth does not reset it.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/clip.dart';

class LandscapeConsoleController extends ChangeNotifier {
  /// How long the controls stay after the last interaction.
  final Duration idleDelay;

  /// How long the new-Snapshot thumbnail stays on screen.
  final Duration thumbnailDuration;

  LandscapeConsoleController({
    this.idleDelay = const Duration(seconds: 3),
    this.thumbnailDuration = const Duration(seconds: 5),
  }) {
    _restartIdleTimer();
  }

  Timer? _idleTimer;
  Timer? _thumbTimer;
  bool _disposed = false;

  bool _controlsVisible = true;
  bool _cleanView = false;
  bool _hudExpanded = false;
  bool _riderPickerOpen = false;
  Clip? _thumbnail;
  int _highlightPulse = 0;

  /// Non-critical controls (buttons, zoom, view modes, timeline handle).
  bool get controlsVisible => _controlsVisible && !_cleanView;
  bool get cleanView => _cleanView;
  bool get hudExpanded => _hudExpanded;
  bool get riderPickerOpen => _riderPickerOpen;

  /// The Snapshot just taken, while its thumbnail is on screen.
  Clip? get thumbnail => _thumbnail;

  /// Increments on every saved Highlight; drives the ring animation.
  int get highlightPulse => _highlightPulse;

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleDelay, _onIdle);
  }

  void _onIdle() {
    if (_disposed) return;
    _controlsVisible = false;
    _hudExpanded = false;
    _riderPickerOpen = false;
    notifyListeners();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Any meaningful interaction: show the controls and restart the idle clock.
  /// In Clean View this only keeps the clock alive; leaving Clean View is an
  /// explicit tap ([exitCleanView]) so a pinch does not bring the HUD back.
  void interact() {
    _restartIdleTimer();
    if (!_controlsVisible && !_cleanView) {
      _controlsVisible = true;
      _notify();
    }
  }

  void enterCleanView() {
    if (_cleanView) return;
    _cleanView = true;
    _hudExpanded = false;
    _riderPickerOpen = false;
    _notify();
  }

  void exitCleanView() {
    if (!_cleanView) return;
    _cleanView = false;
    _controlsVisible = true;
    _restartIdleTimer();
    _notify();
  }

  void toggleCleanView() => _cleanView ? exitCleanView() : enterCleanView();

  void toggleHud() {
    _hudExpanded = !_hudExpanded;
    interact();
    _notify();
  }

  void toggleRiderPicker() {
    _riderPickerOpen = !_riderPickerOpen;
    interact();
    _notify();
  }

  void closeRiderPicker() {
    if (!_riderPickerOpen) return;
    _riderPickerOpen = false;
    _notify();
  }

  void showThumbnail(Clip clip) {
    _thumbnail = clip;
    _thumbTimer?.cancel();
    _thumbTimer = Timer(thumbnailDuration, dismissThumbnail);
    interact();
    _notify();
  }

  void dismissThumbnail() {
    _thumbTimer?.cancel();
    if (_thumbnail == null) return;
    _thumbnail = null;
    _notify();
  }

  void pulseHighlight() {
    _highlightPulse++;
    interact();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _thumbTimer?.cancel();
    super.dispose();
  }
}
