// Pairing flow.
// Per Connect_Device_Pairing_and_Authorization_Design_v0.1 §2 and §4.3a.
//
// ROOT OF TRUST IS PHYSICAL ACCESS TO THE BOAT. A credential is only ever
// issued while the Core has an open pairing window, which requires either a
// physical button press on the unit or an already-paired OWNER opening one.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' show ECPrivateKey, ECPublicKey;

import '../app_config.dart';
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
/// PRODUCTION NOTE: [PlaceholderKeyMaterial] is NOT cryptographically secure
/// and exists for tests only. [SecureKeyMaterial] is the real implementation:
/// a genuine EC (P-256) keypair via `basic_utils`/`pointycastle`, private key
/// persisted through the same Keychain/Keystore-backed storage as credentials
/// (see [SecureCredentialStore]). This class exists so the CSR flow is
/// already wired (§4.3a): the keypair is generated at pairing even though
/// Phase 1 does not use it.
///
/// WHAT THIS DOES NOT DO: the private key is generated in Dart and only
/// encrypted at rest by the OS keystore — it is NOT hardware-bound the way a
/// true iOS Secure Enclave / Android StrongBox key is (non-extractable,
/// never exists outside the secure element). That requires native platform
/// channel code per-platform and is out of scope here. This is a real step
/// up from the placeholder (an actual asymmetric keypair, not a random
/// string), not the final hardware-backed implementation §4.3a describes.
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

/// Real keypair generation: a genuine NIST P-256 EC key via
/// `basic_utils`/`pointycastle`, not a placeholder string. The private key is
/// generated once, PEM-encoded, and persisted through [FlutterSecureStorage]
/// (iOS Keychain / Android EncryptedSharedPreferences) so it survives app
/// restarts without ever touching plain storage or crossing the network —
/// only the public key is ever sent to the Core, in [PairingService.pair].
class SecureKeyMaterial implements KeyMaterial {
  static const _privateKeyKey = 'binnacle_device_private_key_v1';
  final FlutterSecureStorage _storage;

  ECPrivateKey? _private;
  String? _publicPem;

  SecureKeyMaterial({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  @override
  Future<void> ensureKeypair() async {
    if (_private != null) return;

    final existing = await _storage.read(key: _privateKeyKey);
    if (existing != null) {
      _private = CryptoUtils.ecPrivateKeyFromPem(existing);
      _publicPem = CryptoUtils.encodeEcPublicKeyToPem(_publicFromPrivate(_private!));
      return;
    }

    final pair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    _private = pair.privateKey as ECPrivateKey;
    final public = pair.publicKey as ECPublicKey;
    _publicPem = CryptoUtils.encodeEcPublicKeyToPem(public);

    await _storage.write(
      key: _privateKeyKey,
      value: CryptoUtils.encodeEcPrivateKeyToPem(_private!),
    );
  }

  @override
  Future<String> publicKeyPem() async {
    await ensureKeypair();
    return _publicPem!;
  }

  // basic_utils' PEM decode only returns the private scalar; re-derive Q
  // (the public point) from it so a restored key can still report its
  // public PEM without needing it stored separately.
  ECPublicKey _publicFromPrivate(ECPrivateKey private) {
    final q = private.parameters!.G * private.d;
    return ECPublicKey(q, private.parameters);
  }
}

/// Persists the issued credential. NOT SharedPreferences, which is readable
/// on a rooted device — [SecureCredentialStore] below is the real
/// implementation, backed by iOS Keychain / Android Keystore via
/// flutter_secure_storage. [InMemoryCredentialStore] remains for tests,
/// where a real platform keystore isn't available.
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

/// Real credential persistence — iOS Keychain / Android Keystore via
/// flutter_secure_storage, not plain SharedPreferences (readable on a
/// rooted device, or trivially by any other app given a backup extraction).
/// The bearer token is the actual secret; everything else is stored
/// alongside it in one JSON blob rather than N separate keys, since the
/// credential is always read/written as a unit anyway.
class SecureCredentialStore implements CredentialStore {
  static const _key = 'binnacle_device_credential_v1';
  final FlutterSecureStorage _storage;

  SecureCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  @override
  Future<DeviceCredential?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return DeviceCredential.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      // Corrupt/unreadable entry — fail closed to unpaired rather than
      // crash on launch. A real device would need this attention anyway.
      return null;
    }
  }

  @override
  Future<void> save(DeviceCredential c) async {
    await _storage.write(key: _key, value: jsonEncode(c.toStorageJson()));
  }

  @override
  Future<void> clear() async => _storage.delete(key: _key);
}

/// Talks to the Core's pairing endpoint. Abstracted the same way
/// [KeyMaterial] and [CredentialStore] are, so PairingService never
/// hardcodes which transport it uses — demo mode gets [NoOpPairingTransport]
/// (never touches the network), core mode gets [HttpPairingTransport] (a
/// real HTTPS request). See [PairingService]'s constructor for the split.
abstract class PairingTransport {
  Future<PairingResult> pair(PairingTarget target, Map<String, dynamic> request);
}

/// Demo mode's transport: reports the same honest "no window open" outcome
/// every real unpaired attempt would eventually hit, without ever opening a
/// socket — consistent with ControlChannelService staying
/// LinkStatus.simulated in demo mode instead of attempting wss://core.local.
class NoOpPairingTransport implements PairingTransport {
  @override
  Future<PairingResult> pair(PairingTarget target, Map<String, dynamic> request) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return const PairingResult(
      outcome: PairingOutcome.windowClosed,
      message: 'No Core to pair with — this build is running in demo mode. '
          'Press the pairing button on the Vision unit, or have an owner '
          'open a pairing window, once connected to a real Core.',
    );
  }
}

/// Real pairing transport: an actual HTTPS POST to the Core, with real
/// timeout/connection-error handling — not a fabricated response.
///
/// ENDPOINT CONTRACT, stated honestly: POST https://<coreHost>/spotter/
/// {deviceId}/pair, mirroring the /spotter/{deviceId}/ws path already used
/// by ControlChannelService's WSS connection for consistency. The exact
/// path and status-code mapping below are this client's best-effort
/// assumption, not something verified against a live Core — there isn't
/// one to verify against yet (see README's "No connection to real hardware
/// exists yet"). What's real here is the client behavior: a genuine
/// network round-trip, a bounded timeout, and status codes mapped to
/// PairingOutcome instead of everything collapsing into "it didn't work."
class HttpPairingTransport implements PairingTransport {
  final http.Client _client;
  final Duration timeout;

  HttpPairingTransport({http.Client? client, this.timeout = const Duration(seconds: 10)})
      : _client = client ?? http.Client();

  @override
  Future<PairingResult> pair(PairingTarget target, Map<String, dynamic> request) async {
    final uri = Uri(
      scheme: 'https',
      host: target.coreHost,
      path: '/spotter/${target.deviceId}/pair',
    );

    http.Response response;
    try {
      response = await _client
          .post(uri, headers: const {'content-type': 'application/json'}, body: jsonEncode(request))
          .timeout(timeout);
    } on TimeoutException {
      return const PairingResult(
        outcome: PairingOutcome.unreachable,
        message: 'Timed out reaching the Core. Check the boat Wi-Fi.',
      );
    } catch (_) {
      // Covers http.ClientException (connection refused, DNS failure,
      // certificate mismatch, ...) — every case collapses to "unreachable"
      // for the user, but doesn't crash the pairing flow.
      return const PairingResult(
        outcome: PairingOutcome.unreachable,
        message: 'Could not reach the Core. Check the boat Wi-Fi.',
      );
    }

    switch (response.statusCode) {
      case 200:
      case 201:
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          return PairingResult(
            outcome: PairingOutcome.success,
            credential: DeviceCredential.fromJson(body),
            unitWasUnclaimed: body['unit_was_unclaimed'] == true,
            message: body['message'] as String?,
          );
        } on FormatException {
          return const PairingResult(
            outcome: PairingOutcome.refused,
            message: 'The Core sent back a response this app could not understand.',
          );
        }
      case 404:
      case 425: // "too early" — no pairing window open yet
        return const PairingResult(
          outcome: PairingOutcome.windowClosed,
          message: 'No pairing window is open. Press the pairing button on '
              'the Vision unit, or ask the owner to open one from their app.',
        );
      case 403:
        return const PairingResult(outcome: PairingOutcome.refused);
      case 409:
        return const PairingResult(outcome: PairingOutcome.alreadyPaired);
      default:
        return PairingResult(
          outcome: PairingOutcome.refused,
          message: 'The Core returned an unexpected status (${response.statusCode}).',
        );
    }
  }
}

class PairingService extends ChangeNotifier {
  final KeyMaterial keyMaterial;
  final CredentialStore store;
  final PairingTransport transport;

  DeviceCredential? credential;
  bool busy = false;

  PairingService({KeyMaterial? keyMaterial, CredentialStore? store, PairingTransport? transport})
      : keyMaterial = keyMaterial ?? (AppConfig.isDemo ? PlaceholderKeyMaterial() : SecureKeyMaterial()),
        // Real persistence in both modes — demo credentials are fabricated
        // but still need to survive an app restart for the pairing UI to be
        // usable; InMemoryCredentialStore is a test-only double, not
        // something main.dart should ever get by default.
        store = store ?? SecureCredentialStore(),
        // Demo mode must never attempt a real network request, same rule as
        // ControlChannelService's connect() gating in main.dart — see
        // app_config.dart. NoOpPairingTransport always reports windowClosed
        // honestly instead of hanging or fabricating success.
        transport = transport ?? (AppConfig.isDemo ? NoOpPairingTransport() : HttpPairingTransport());

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

      final result = await transport.pair(target, request);
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
