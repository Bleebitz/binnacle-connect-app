// Credential and role model.
// Per Connect_Device_Pairing_and_Authorization_Design_v0.1 §3 and §4.
//
// IMPORTANT: role checks in this app are a UX AFFORDANCE, not a security
// boundary. The Core is the authority and re-checks every command. A modified
// client can bypass anything here — which is exactly why §3 requires
// enforcement on the Core "never only in the app UI".

enum DeviceRole { spectator, crew, owner }

extension DeviceRoleX on DeviceRole {
  String get wire => name;

  static DeviceRole fromWire(String? s) => switch (s) {
        'owner' => DeviceRole.owner,
        'crew' => DeviceRole.crew,
        _ => DeviceRole.spectator, // fail closed: unknown role gets least privilege
      };

  String get label => switch (this) {
        DeviceRole.owner => 'Owner',
        DeviceRole.crew => 'Crew',
        DeviceRole.spectator => 'Spectator',
      };

  String get description => switch (this) {
        DeviceRole.owner => 'Full control, including public broadcast, pairing and revoking devices.',
        DeviceRole.crew => 'Capture control. Cannot start a public broadcast or pair devices.',
        DeviceRole.spectator => 'View only. Receives safety alerts. Sends no commands.',
      };
}

/// Commands each role may send. The Core holds the authoritative copy of this
/// table — this mirror exists so the UI can disable controls rather than let a
/// user tap something that will be rejected.
class RolePolicy {
  // Spectator sends NOTHING. Not a reduced set — an empty set (§3).
  static const Set<String> _spectator = {};

  static const Set<String> _crew = {
    'arm',
    'disarm',
    'save_highlight',
    'snapshot',
    'set_trigger_mode',
    'set_gps_trigger_speed',
    'load_preset',
    'nudge_zoom',
    'set_zoom',
    'set_control_mode',
    'set_auto_framing',
    'set_ai_auto_detect',
    'set_sensitivity',
    'set_hand_signals',
    'set_aspect_ratio',
    'set_video_resolution',
    'set_photo_resolution',
    'set_pre_roll',
    'set_post_roll',
    // Available to crew deliberately — requiring the owner's specific phone to
    // acknowledge a live man-overboard event would be dangerous (§3.3).
    'acknowledge_mob',
    'set_escalation_delay',
    'set_audible_alarm',
    // On-boat broadcast only. Public is owner-gated below.
    'start_broadcast_boat',
    'stop_broadcast',
    'set_broadcast_notice',
  };

  static const Set<String> _ownerOnly = {
    // THE restriction that closes the exposure in the protocol doc §8 (§3.1).
    'start_broadcast_public',
    'open_pairing_window',
    'assign_role',
    'revoke_device',
    'factory_reset',
    'set_audio_recording',
    'set_rider_identification',
  };

  static Set<String> allowedFor(DeviceRole role) => switch (role) {
        DeviceRole.spectator => _spectator,
        DeviceRole.crew => _crew,
        DeviceRole.owner => {..._crew, ..._ownerOnly},
      };

  static bool can(DeviceRole role, String command) =>
      allowedFor(role).contains(command);

  /// start_broadcast carries its privilege in a parameter, not the command
  /// name, so it needs special handling — mode:"public" is owner-only even
  /// though mode:"boat" is crew-allowed.
  static bool canBroadcast(DeviceRole role, String mode) =>
      mode == 'public' ? role == DeviceRole.owner : can(role, 'start_broadcast_boat');
}

/// A credential issued by the Core at pairing.
/// Phase 1 is a bearer token; Phase 2 is mTLS. Everything outside this class
/// references [credentialId], never the secret, so the credential TYPE can
/// change without touching state, logs, or the revocation list (§4.3b).
class DeviceCredential {
  final String credentialId;   // opaque, safe to log
  final String deviceId;
  final String coreHost;
  final String? certFingerprint;
  final DeviceRole role;
  final String authMethod;     // "bearer" now, "mtls" later (§4.3c)
  final DateTime issuedAt;
  final DateTime? expiresAt;   // guest credentials may be session-scoped (§5)

  /// The bearer secret. NEVER logged, never placed in state objects, never
  /// included in toJsonSafe(). Phase 2 removes this field entirely.
  final String? bearerToken;

  const DeviceCredential({
    required this.credentialId,
    required this.deviceId,
    required this.coreHost,
    this.certFingerprint,
    required this.role,
    this.authMethod = 'bearer',
    required this.issuedAt,
    this.expiresAt,
    this.bearerToken,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Safe representation for logs and diagnostics — deliberately omits the
  /// secret. If you need to print a credential, print this.
  Map<String, dynamic> toJsonSafe() => {
        'credential_id': credentialId,
        'device_id': deviceId,
        'core_host': coreHost,
        'role': role.wire,
        'auth_method': authMethod,
        'issued_at': issuedAt.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        // bearerToken intentionally absent
      };

  factory DeviceCredential.fromJson(Map<String, dynamic> j) => DeviceCredential(
        credentialId: j['credential_id'],
        deviceId: j['device_id'],
        coreHost: j['core_host'],
        certFingerprint: j['cert_fingerprint'],
        role: DeviceRoleX.fromWire(j['role']),
        authMethod: j['auth_method'] ?? 'bearer',
        issuedAt: DateTime.tryParse(j['issued_at'] ?? '') ?? DateTime.now(),
        expiresAt: j['expires_at'] != null ? DateTime.tryParse(j['expires_at']) : null,
        bearerToken: j['token'],
      );
}

/// A device as listed in the owner's paired-device list (§5).
class PairedDevice {
  final String credentialId;
  final String displayName;
  final DeviceRole role;
  final DateTime pairedAt;
  final DateTime? lastSeen;
  final bool isThisDevice;

  const PairedDevice({
    required this.credentialId,
    required this.displayName,
    required this.role,
    required this.pairedAt,
    this.lastSeen,
    this.isThisDevice = false,
  });

  factory PairedDevice.fromJson(Map<String, dynamic> j) => PairedDevice(
        credentialId: j['credential_id'],
        displayName: j['display_name'] ?? 'Unnamed device',
        role: DeviceRoleX.fromWire(j['role']),
        pairedAt: DateTime.tryParse(j['paired_at'] ?? '') ?? DateTime.now(),
        lastSeen: j['last_seen'] != null ? DateTime.tryParse(j['last_seen']) : null,
        isThisDevice: j['is_this_device'] ?? false,
      );
}
