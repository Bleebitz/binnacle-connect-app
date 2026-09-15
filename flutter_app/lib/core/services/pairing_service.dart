// Pairing flow.
// Per Connect_Device_Pairing_and_Authorization_Design_v0.1 §2 and §4.3a.
//
// ROOT OF TRUST IS PHYSICAL ACCESS TO THE BOAT. A credential is only ever
// issued while the Core has an open pairing window, which requires either a
// physical button press on the unit or an already-paired OWNER opening one.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

import '../models/credential.dart';

/// Parsed contents of the QR label on the Vision unit.
/// binnacle://pair?d=<device_id>&h=<core_host>&f=<cert_fingerprint>
///
/// NOTE: this deliberately contains NO CREDENTIAL (§2.1). Photographing the
/// sticker on someone's boat grants nothing — a pairing window must also be
/// open on the Core.
class PairingTarget {
  final String deviceId;
  final String coreHost;
  final String? certFingerprint;

  const PairingTarget({
    required this.deviceId,
    required this.coreHost,
    this.certFingerprint,
  });

  static PairingTarget? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    if (uri.scheme != 'binnacle' || uri.host != 'pair') return null;
    final d = uri.queryParameters['d'];
    final h = uri.queryParameters['h'];
    if (d == null || d.isEmpty || h == null || h.isEmpty) return null;
    return PairingTarget(
      deviceId: d,
      coreHost: h,
      certFingerprint: uri.queryParameters['f'],
    );
  }
}

/// Outcome of asking the Core to pair.
enum PairingOutcome {
  success,
  windowClosed,      // no pairing window open — press the button on the unit
  refused,           // Core actively refused (e.g. revoked device re-trying)
  unreachable,
  alreadyPaired,
}

class PairingResult {
  final PairingOutcome outcome;
  final DeviceCredential? credential;

  /// TRUE when the Core reported it had no previous owner. Drives the
  /// unclaimed-unit warning required by §2.4 — this must be surfaced to the
  /// user, not silently accepted.
  final bool unitWasUnclaimed;

  final String? message;

  const PairingResult({
    required this.outcome,
    this.credential,
    this.unitWasUnclaimed = false,
    this.message,
  });
}

/// Abstraction over secure key material so the app never handles raw crypto
/// directly and Phase 2 (mTLS) can swap the implementation.
///
/// PRODUCTION NOTE: the placeholder below is NOT cryptographically secure and
/// must be replaced before any real pairing. Use a platform keystore-backed
/// implementation — iOS Secure Enclave / Android Keystore — so the private key
/// is generated in hardware and never becomes extractable. This class exists
/// now so the CSR flow is already wired (§4.3a): the keypair is generated at
/// pairing even though Phase 1 does not use it.
abstract class KeyMaterial {
  Future<String> publicKeyPem();
  Future<void> ensureKeypair();
}

class PlaceholderKeyMaterial implements KeyMaterial {
  String? _pub;

  @override
  Future<void> ensureKeypair() async {
    if (_pub != null) return;
    // DEV PLACEHOLDER ONLY — not a real key. Replace before shipping.
    final r = Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    _pub = 'PLACEHOLDER-PUBKEY-${base64Url.encode(bytes)}';
    debugPrint('PairingService: PLACEHOLDER keypair generated — replace with '
        'a platform keystore implementation before real pairing.');
  }

  @override
  Future<String> publicKeyPem() async {
    await ensureKeypair();
    return _pub!;
  }
}

/// Persists the issued credential. Production implementation must use
/// flutter_secure_storage (iOS Keychain / Android Keystore) — NOT
/// SharedPreferences, which is readable on a rooted device.
abstract class CredentialStore {
  Future<DeviceCredential?> load();
  Future<void> save(DeviceCredential c);
  Future<void> clear();
}

class InMemoryCredentialStore implements CredentialStore {
  DeviceCredential? _c;
  @override
  Future<DeviceCredential?> load() async => _c;
  @override
  Future<void> save(DeviceCredential c) async => _c = c;
  @override
  Future<void> clear() async => _c = null;
}

class PairingService extends ChangeNotifier {
  final KeyMaterial keyMaterial;
  final CredentialStore store;

  DeviceCredential? credential;
  bool busy = false;

  PairingService({KeyMaterial? keyMaterial, CredentialStore? store})
      : keyMaterial = keyMaterial ?? PlaceholderKeyMaterial(),
        store = store ?? InMemoryCredentialStore();

  DeviceRole get role => credential?.role ?? DeviceRole.spectator; // fail closed
  bool get isPaired => credential != null && !credential!.isExpired;

  Future<void> restore() async {
    credential = await store.load();
    notifyListeners();
  }

  /// Requests a credential from the Core.
  ///
  /// The keypair is generated here EVEN THOUGH PHASE 1 DOES NOT USE IT (§4.3a).
  /// Sending the public key now means that when mTLS arrives, every paired
  /// device already has a key on file and no device needs to re-pair.
  Future<PairingResult> pair(PairingTarget target, {String? displayName}) async {
    busy = true;
    notifyListeners();
    try {
      await keyMaterial.ensureKeypair();
      final pub = await keyMaterial.publicKeyPem();

      final request = {
        'device_id': target.deviceId,
        'display_name': displayName ?? 'Phone',
        'public_key': pub,          // unused in Phase 1, stored by the Core
        'auth_method': 'bearer',    // §4.3c — Core can support both in transition
        'client_version': '0.1.0',
      };

      final result = await _transport(target, request);
      if (result.outcome == PairingOutcome.success && result.credential != null) {
        credential = result.credential;
        await store.save(result.credential!);
      }
      return result;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Placeholder transport. Real implementation POSTs to the Core's pairing
  /// endpoint over TLS, pinned to target.certFingerprint from the QR.
  Future<PairingResult> _transport(PairingTarget target, Map<String, dynamic> request) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return const PairingResult(
      outcome: PairingOutcome.windowClosed,
      message: 'No Core to pair with. Press the pairing button on the Vision '
          'unit, or have an owner open a pairing window.',
    );
  }

  Future<void> unpair() async {
    credential = null;
    await store.clear();
    notifyListeners();
  }

  /// DEMO ONLY. Fabricates a pairing outcome without a real Core, so the
  /// unclaimed-unit warning flow (§2.4) can actually be exercised in this
  /// scaffold. A real build must delete this method — there is no
  /// corresponding server-side concept and it must never ship.
  Future<PairingResult> debugSimulatePairing({
    required bool unclaimed,
    required DeviceRole role,
  }) async {
    busy = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 400));

    final cred = DeviceCredential(
      credentialId: 'demo-${DateTime.now().millisecondsSinceEpoch}',
      deviceId: 'vision-0001-demo',
      coreHost: 'core.local',
      role: role,
      authMethod: 'bearer',
      issuedAt: DateTime.now(),
      bearerToken: 'DEMO-NOT-A-REAL-TOKEN',
    );

    // Issued immediately so the dialog's "Stop" path has something concrete
    // to unpair — matching what a real Core would have already done by the
    // time this warning is shown.
    credential = cred;
    await store.save(cred);

    busy = false;
    notifyListeners();

    return PairingResult(
      outcome: PairingOutcome.success,
      credential: cred,
      unitWasUnclaimed: unclaimed,
      message: unclaimed ? 'This unit reported no previous owner.' : null,
    );
  }
}
