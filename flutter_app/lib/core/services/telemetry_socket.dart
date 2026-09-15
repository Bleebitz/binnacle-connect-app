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

  /// Real implementation subscribes to a WSS telemetry topic and parses
  /// ~20 Hz JSON frames (see lib/core/services/control_channel_service.dart
  /// for the sibling low-rate channel). Until a device is paired, this
  /// simulates plausible values so UI built against this class is testable.
  void startSimulated() {
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      latest = TelemetrySample(
        16 + _rand.nextDouble() * 8,
        7 + _rand.nextDouble() * 6,
        DateTime.now(),
      );
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    super.dispose();
  }
}
