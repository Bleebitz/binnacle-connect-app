// Mirrors the state object published on spotter/{device_id}/state,
// per Connect_Platform_and_Control_Channel_CORRECTED_v2.0 §4.
//
// THE CORE IS THE STATE AUTHORITY. This class is a pure data holder for
// what the Core reported — it must never be locally mutated to "look right"
// ahead of an acknowledgment. See ControlChannelService for how updates flow.

class CaptureState {
  final bool armed;
  final bool recording;
  final int passNumber;
  final String triggerSource;
  final String bufferHealth; // ok | recovering | degraded
  final int preRollSeconds;
  final int postRollSeconds;

  const CaptureState({
    required this.armed,
    required this.recording,
    required this.passNumber,
    required this.triggerSource,
    required this.bufferHealth,
    required this.preRollSeconds,
    required this.postRollSeconds,
  });

  factory CaptureState.fromJson(Map<String, dynamic> j) => CaptureState(
        armed: j['armed'] ?? false,
        recording: j['recording'] ?? false,
        passNumber: j['pass_number'] ?? 0,
        triggerSource: j['trigger_source'] ?? 'unknown',
        bufferHealth: j['buffer_health'] ?? 'ok',
        preRollSeconds: j['pre_roll_s'] ?? 15,
        postRollSeconds: j['post_roll_s'] ?? 30,
      );

  static CaptureState simulated() => const CaptureState(
        armed: true,
        recording: false,
        passNumber: 0,
        triggerSource: 'rider_in_frame',
        bufferHealth: 'ok',
        preRollSeconds: 15,
        postRollSeconds: 30,
      );
}

class FramingState {
  final String controlMode; // ai | manual — see protocol §1.3, no auto-resume
  final double zoom;
  final double maxZoom;
  final bool autoFramingEnabled;

  const FramingState({
    required this.controlMode,
    required this.zoom,
    required this.maxZoom,
    required this.autoFramingEnabled,
  });

  bool get isManual => controlMode == 'manual';

  factory FramingState.fromJson(Map<String, dynamic> j) => FramingState(
        controlMode: j['control_mode'] ?? 'ai',
        zoom: (j['zoom'] ?? 1.0).toDouble(),
        maxZoom: (j['max_zoom'] ?? 6.0).toDouble(),
        autoFramingEnabled: j['auto_framing_enabled'] ?? true,
      );

  static FramingState simulated() => const FramingState(
        controlMode: 'ai',
        zoom: 1.0,
        maxZoom: 6.0,
        autoFramingEnabled: true,
      );
}

// SAFETY IS ALWAYS ON. This class deliberately has no setter for
// fallDetection / mobAlert. There is no command in the protocol vocabulary
// that can change these — see ControlChannelService.NO_DISABLE_COMMANDS.
//
// POLICY vs. READINESS (BIN-9): fallDetection/mobAlert/locked express a
// PRODUCT POLICY — safety can never be disabled from this app, full stop —
// and are correctly hard-coded true regardless of payload; that is a
// promise this client makes, not a sensor reading. [fallDetectionReadiness]
// / [mobAlertReadiness] are the separate, AUTHORITATIVE question of whether
// the underlying service is actually working right now, per Core. The two
// must never be collapsed into one field again: a Core that goes silent on
// health say nothing about whether the non-disableable policy still holds.
enum SafetyReadiness { unknown, operational, degraded, faulted }

extension SafetyReadinessX on SafetyReadiness {
  static SafetyReadiness parse(dynamic v) => switch (v) {
        'operational' => SafetyReadiness.operational,
        'degraded' => SafetyReadiness.degraded,
        'faulted' => SafetyReadiness.faulted,
        // Fail closed: missing, null, or an unrecognized string (an older/
        // newer Core, a typo, a field that was never implemented) must never
        // be read as "operational" — that would be exactly the bug this
        // issue exists to fix, just moved one field over.
        _ => SafetyReadiness.unknown,
      };

  String get label => switch (this) {
        SafetyReadiness.unknown => 'UNKNOWN',
        SafetyReadiness.operational => 'OPERATIONAL',
        SafetyReadiness.degraded => 'DEGRADED',
        SafetyReadiness.faulted => 'FAULTED',
      };
}

class SafetyState {
  final bool fallDetection;
  final bool mobAlert;
  final bool locked; // true => UI must render these read-only
  final int escalationSeconds;
  final bool audibleAlarm;
  final SafetyReadiness fallDetectionReadiness;
  final SafetyReadiness mobAlertReadiness;

  const SafetyState({
    required this.fallDetection,
    required this.mobAlert,
    required this.locked,
    required this.escalationSeconds,
    required this.audibleAlarm,
    required this.fallDetectionReadiness,
    required this.mobAlertReadiness,
  });

  /// PROPOSED CLIENT CONTRACT — awaiting Core agreement, not yet part of
  /// the approved wire schema (Connect_Platform_and_Control_Channel_
  /// CORRECTED_v2.0 §4 documents no readiness field today). This client
  /// optionally reads two new string fields on the existing `safety` object:
  ///   safety.fall_detection_readiness: "operational" | "degraded" | "faulted"
  ///   safety.mob_alert_readiness:      "operational" | "degraded" | "faulted"
  /// Absent, null, or any other value parses to [SafetyReadiness.unknown].
  /// This is backward-compatible with the current Core (which sends
  /// neither field) — every real Core response today parses to unknown for
  /// both, which is the correct, honest answer until the Core contract is
  /// extended, not a regression.
  factory SafetyState.fromJson(Map<String, dynamic> j) => SafetyState(
        fallDetection: true, // policy — see §1.2 and the class doc above
        mobAlert: true,
        locked: true,
        escalationSeconds: j['escalation_s'] ?? 20,
        audibleAlarm: j['audible_alarm'] ?? true,
        fallDetectionReadiness: SafetyReadinessX.parse(j['fall_detection_readiness']),
        mobAlertReadiness: SafetyReadinessX.parse(j['mob_alert_readiness']),
      );

  static SafetyState simulated() => const SafetyState(
        fallDetection: true,
        mobAlert: true,
        locked: true,
        escalationSeconds: 20,
        audibleAlarm: true,
        // Demo mode is not "unknown" — it is a fully scripted stand-in
        // presenting as a healthy boat, and is always labeled Simulated at
        // the link-status level; showing operational here is honest within
        // that framing, not a health claim about real hardware.
        fallDetectionReadiness: SafetyReadiness.operational,
        mobAlertReadiness: SafetyReadiness.operational,
      );
}

class HealthState {
  final double tempC;
  final String thermalState; // nominal | warm | throttling
  final int storageFreePct;

  const HealthState({
    required this.tempC,
    required this.thermalState,
    required this.storageFreePct,
  });

  factory HealthState.fromJson(Map<String, dynamic> j) => HealthState(
        tempC: (j['temp_c'] ?? 30.0).toDouble(),
        thermalState: j['thermal_state'] ?? 'nominal',
        storageFreePct: j['storage_free_pct'] ?? 100,
      );

  static HealthState simulated() => const HealthState(
        tempC: 31.0,
        thermalState: 'nominal',
        storageFreePct: 62,
      );
}

class BroadcastState {
  final bool live;
  final String mode; // boat | public
  final int viewers;
  final String linkQuality; // strong | adaptive | weak

  const BroadcastState({
    required this.live,
    required this.mode,
    required this.viewers,
    required this.linkQuality,
  });

  factory BroadcastState.fromJson(Map<String, dynamic> j) => BroadcastState(
        live: j['live'] ?? false,
        mode: j['mode'] ?? 'boat',
        viewers: j['viewers'] ?? 0,
        linkQuality: j['link_quality'] ?? 'strong',
      );

  static BroadcastState simulated() => const BroadcastState(
        live: false,
        mode: 'boat',
        viewers: 0,
        linkQuality: 'strong',
      );
}

enum LinkStatus { simulated, connecting, connected, stale, offline }

/// A man-overboard event as Core reported it — never fabricated locally.
/// See MobAlertState for how this feeds the app-wide alert banner in Core
/// mode, and why Demo mode uses a wholly separate, clearly-labeled path.
///
/// PROPOSED CLIENT CONTRACT — awaiting Core agreement. No current wire
/// message carries MOB location; this optionally reads a top-level `mob`
/// object on the state payload:
///   mob.active: bool
///   mob.lat / mob.lon: string (already-formatted, matching this client's
///     existing display convention, e.g. "36.02083° N")
///   mob.heading_degrees: number
/// Total absence of `mob` parses to inactive with no location — that is
/// the correct default (no evidence of an event), not an unknown/fault
/// state; MOB is a discrete event signal, not a continuously-reported
/// health channel like [SafetyState]'s readiness fields.
class MobEvent {
  final bool active;
  final String? lat;
  final String? lon;
  final double? headingDegrees;

  const MobEvent({required this.active, this.lat, this.lon, this.headingDegrees});

  factory MobEvent.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const MobEvent(active: false);
    return MobEvent(
      active: j['active'] == true,
      lat: j['lat'] as String?,
      lon: j['lon'] as String?,
      headingDegrees: (j['heading_degrees'] as num?)?.toDouble(),
    );
  }

  static const inactive = MobEvent(active: false);
}

class VesselState {
  final int seq;
  final DateTime ts;
  final CaptureState capture;
  final String triggerMode; // rider | gps | swimmer | onboard
  final FramingState framing;
  final SafetyState safety;
  final HealthState health;
  final BroadcastState broadcast;
  final MobEvent mob;

  const VesselState({
    required this.seq,
    required this.ts,
    required this.capture,
    required this.triggerMode,
    required this.framing,
    required this.safety,
    required this.health,
    required this.broadcast,
    required this.mob,
  });

  factory VesselState.fromJson(Map<String, dynamic> j) => VesselState(
        seq: j['seq'] ?? 0,
        ts: DateTime.tryParse(j['ts'] ?? '') ?? DateTime.now(),
        capture: CaptureState.fromJson(j['capture'] ?? {}),
        triggerMode: (j['mode'] ?? {})['trigger'] ?? 'rider',
        framing: FramingState.fromJson(j['framing'] ?? {}),
        safety: SafetyState.fromJson(j['safety'] ?? {}),
        health: HealthState.fromJson(j['health'] ?? {}),
        broadcast: BroadcastState.fromJson(j['broadcast'] ?? {}),
        mob: MobEvent.fromJson(j['mob'] as Map<String, dynamic>?),
      );

  static VesselState simulated() => VesselState(
        seq: 0,
        ts: DateTime.now(),
        capture: CaptureState.simulated(),
        triggerMode: 'rider',
        framing: FramingState.simulated(),
        safety: SafetyState.simulated(),
        health: HealthState.simulated(),
        broadcast: BroadcastState.simulated(),
        mob: MobEvent.inactive,
      );
}
