// Unit tests for SecureCredentialStore — round-trips a DeviceCredential
// (bearer token included) through flutter_secure_storage's test platform
// double (FlutterSecureStorage.setMockInitialValues), which exercises the
// real read/write/delete + JSON (de)serialization path this class adds on
// top of the plugin, not just that the types line up.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:binnacle_connect/core/models/credential.dart';
import 'package:binnacle_connect/core/services/pairing_service.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  DeviceCredential sample() => DeviceCredential(
        credentialId: 'cred-1',
        deviceId: 'vision-0001',
        coreHost: 'core.example',
        certFingerprint: 'ab:cd:ef',
        role: DeviceRole.crew,
        issuedAt: DateTime(2026, 1, 1),
        bearerToken: 'super-secret-token',
      );

  test('load() returns null when nothing has been saved yet', () async {
    final store = SecureCredentialStore();
    expect(await store.load(), isNull);
  });

  test('save() then load() round-trips every field, including the bearer token', () async {
    final store = SecureCredentialStore();
    final original = sample();

    await store.save(original);
    final loaded = await store.load();

    expect(loaded, isNotNull);
    expect(loaded!.credentialId, original.credentialId);
    expect(loaded.deviceId, original.deviceId);
    expect(loaded.coreHost, original.coreHost);
    expect(loaded.certFingerprint, original.certFingerprint);
    expect(loaded.role, original.role);
    expect(loaded.issuedAt, original.issuedAt);
    // The one field toJsonSafe() deliberately omits — proves this store
    // uses toStorageJson(), not the log-safe representation.
    expect(loaded.bearerToken, 'super-secret-token');
  });

  test('clear() removes the credential', () async {
    final store = SecureCredentialStore();
    await store.save(sample());
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('a second store instance reads what the first one wrote', () async {
    // Proves persistence goes through the platform storage, not an
    // in-memory field on the store object itself.
    await SecureCredentialStore().save(sample());
    final loaded = await SecureCredentialStore().load();
    expect(loaded?.credentialId, 'cred-1');
  });
}
