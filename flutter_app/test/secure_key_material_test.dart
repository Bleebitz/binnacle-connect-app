// Unit tests for SecureKeyMaterial — proves a real NIST P-256 EC keypair is
// generated (not a placeholder string), persisted through
// flutter_secure_storage's test platform double, and that the public key
// derived from a restored private key matches the one generated originally.

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' show ECPublicKey;

import 'package:binnacle_connect/core/services/pairing_service.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('publicKeyPem() returns a real EC SubjectPublicKeyInfo PEM block', () async {
    final km = SecureKeyMaterial();
    final pem = await km.publicKeyPem();

    // Standard SubjectPublicKeyInfo PEM framing (RFC 5480) — the same header
    // used for any PEM public key, EC or otherwise; the curve identity lives
    // inside the DER, which the decode step below actually verifies.
    expect(pem, startsWith('-----BEGIN PUBLIC KEY-----'));
    expect(pem, contains('-----END PUBLIC KEY-----'));

    // Round-trips through basic_utils' own decoder as a genuine P-256 key —
    // not just a string that happens to look PEM-shaped.
    final decoded = CryptoUtils.ecPublicKeyFromPem(pem);
    expect(decoded.parameters?.domainName, 'prime256v1');
    expect(decoded.Q, isNotNull);
  });

  test('ensureKeypair() is idempotent — same key, not regenerated each call', () async {
    final km = SecureKeyMaterial();
    await km.ensureKeypair();
    final first = await km.publicKeyPem();
    await km.ensureKeypair();
    final second = await km.publicKeyPem();

    expect(first, second);
  });

  test('the private key persists through secure storage, not an in-memory field', () async {
    final first = SecureKeyMaterial();
    final pubFromFirst = await first.publicKeyPem();

    // A second instance, same underlying (mocked) secure storage — proves
    // this reads a persisted key rather than each instance generating its
    // own, which would break the pairing flow across app restarts.
    final second = SecureKeyMaterial();
    final pubFromSecond = await second.publicKeyPem();

    expect(pubFromSecond, pubFromFirst);
  });

  test('a restored key\'s public PEM matches the one generated on first use', () async {
    final storage = FlutterSecureStorage();
    final first = SecureKeyMaterial(storage: storage);
    await first.ensureKeypair();
    final generatedPem = await first.publicKeyPem();

    // Simulates an app restart: a fresh SecureKeyMaterial over storage that
    // already has a key written to it must derive the SAME public key from
    // the persisted private scalar, not a new one.
    final restored = SecureKeyMaterial(storage: storage);
    final restoredPem = await restored.publicKeyPem();

    expect(restoredPem, generatedPem);

    // Confirm the derivation produced a real point on the curve, not the
    // point at infinity (which a broken d*G derivation could produce).
    final ECPublicKey decoded = CryptoUtils.ecPublicKeyFromPem(restoredPem);
    expect(decoded.Q!.isInfinity, isFalse);
  });

  test('a generated public key is real EC output, not a placeholder string', () async {
    final a = SecureKeyMaterial(storage: FlutterSecureStorage());

    final pemA = await a.publicKeyPem();
    expect(pemA, isNot(contains('PLACEHOLDER')));
    final decoded = CryptoUtils.ecPublicKeyFromPem(pemA);
    expect(decoded.Q!.isInfinity, isFalse);
  });
}
