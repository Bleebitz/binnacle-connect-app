// High-rate telemetry stream (speed, rider distance, framing state),
// separate from the low-rate control-state channel per the Flutter spec's
// file layout. In the approved architecture this still rides over the
// same HTTPS/WSS path to the Core (C-07) — it is a logically separate
// concern, not a separate transport.

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

class TelemetrySample {
  final double speedMph;
  final double riderDistanceM;
  final DateTime at;
  const TelemetrySample(this.speedMph, this.riderDistanceM, this.at);
}

class TelemetrySocket extends ChangeNotifier {
  TelemetrySample latest = TelemetrySample(0, 0, DateTime.now());
  Timer? _simTimer;
  final _rand = Random();

  static const _historyLength = 40;
  final List<TelemetrySample> _history = [];

  /// Recent samples, oldest first, capped at [_historyLength] — feeds the
  /// speed sparkline in the capture-screen telemetry overlay. Not meant as
  /// a real trace store; the Core is the source of truth for ride history.
  List<TelemetrySample> get history => List.unmodifiable(_history);

  /// Real implementation subscribes to a WSS telemetry topic and parses
  /// ~20 Hz JSON frames (see lib/core/services/control_channel_service.dart
  /// for the sibling low-rate channel). Until a device is paired, this
  /// simulates plausible values so UI built against this class is testable.
  void startSimulated() {
    _simTimer?.cancel();
    double speed = 18;
    double distance = 9;
    _simTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      // A bounded random walk reads as real telemetry on the sparkline;
      // independent per-tick random values just look like sensor noise.
      speed = (speed + (_rand.nextDouble() - 0.5) * 2.2).clamp(12, 26);
      distance = (distance + (_rand.nextDouble() - 0.5) * 1.4).clamp(4, 15);
      latest = TelemetrySample(speed, distance, DateTime.now());
      _history.add(latest);
      if (_history.length > _historyLength) _history.removeAt(0);
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    super.dispose();
  }
}
