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
class SafetyState {
  final bool fallDetection;
  final bool mobAlert;
  final bool locked; // true => UI must render these read-only
  final int escalationSeconds;
  final bool audibleAlarm;

  const SafetyState({
    required this.fallDetection,
    required this.mobAlert,
    required this.locked,
    required this.escalationSeconds,
    required this.audibleAlarm,
  });

  factory SafetyState.fromJson(Map<String, dynamic> j) => SafetyState(
        fallDetection: true, // always true regardless of payload — see §1.2
        mobAlert: true,
        locked: true,
        escalationSeconds: j['escalation_s'] ?? 20,
        audibleAlarm: j['audible_alarm'] ?? true,
      );

  static SafetyState simulated() => const SafetyState(
        fallDetection: true,
        mobAlert: true,
        locked: true,
        escalationSeconds: 20,
        audibleAlarm: true,
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

class VesselState {
  final int seq;
  final DateTime ts;
  final CaptureState capture;
  final String triggerMode; // rider | gps | swimmer | onboard
  final FramingState framing;
  final SafetyState safety;
  final HealthState health;
  final BroadcastState broadcast;

  const VesselState({
    required this.seq,
    required this.ts,
    required this.capture,
    required this.triggerMode,
    required this.framing,
    required this.safety,
    required this.health,
    required this.broadcast,
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
      );
}
