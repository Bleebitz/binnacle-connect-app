// Unit tests for HttpPairingTransport — the real Core pairing transport
// (see pairing_service.dart's module comment for the endpoint contract).
// These exercise actual HTTP request construction and response parsing via
// an injected http.Client (http/testing.dart's MockClient), which is
// exactly the seam HttpPairingTransport was built with for this purpose —
// there's no real Core to test against, but the client-side logic (URL/body
// construction, status-code mapping, timeout handling) is fully real and
// fully testable without one.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:binnacle_connect/core/models/credential.dart';
import 'package:binnacle_connect/core/services/pairing_service.dart';

void main() {
  const target = PairingTarget(deviceId: 'vision-0001', coreHost: 'core.example');
  const request = {'device_id': 'vision-0001', 'display_name': 'Test Phone'};

  test('sends a real HTTPS POST to /spotter/{deviceId}/pair with the JSON body', () async {
    http.Request? captured;
    final transport = HttpPairingTransport(
      client: MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'credential_id': 'cred-1',
            'device_id': 'vision-0001',
            'core_host': 'core.example',
            'role': 'owner',
            'issued_at': DateTime.now().toIso8601String(),
            'token': 'secret-token',
          }),
          200,
        );
      }),
    );

    final result = await transport.pair(target, request);

    expect(captured, isNotNull);
    expect(captured!.url.scheme, 'https');
    expect(captured!.url.host, 'core.example');
    expect(captured!.url.path, '/spotter/vision-0001/pair');
    expect(jsonDecode(captured!.body), request);

    expect(result.outcome, PairingOutcome.success);
    expect(result.credential?.credentialId, 'cred-1');
    expect(result.credential?.bearerToken, 'secret-token');
    expect(result.credential?.role, DeviceRole.owner);
  });

  test('maps unit_was_unclaimed through from the response body', () async {
    final transport = HttpPairingTransport(
      client: MockClient((req) async => http.Response(
            jsonEncode({
              'credential_id': 'cred-2',
              'device_id': 'vision-0001',
              'core_host': 'core.example',
              'role': 'owner',
              'issued_at': DateTime.now().toIso8601String(),
              'unit_was_unclaimed': true,
            }),
            200,
          )),
    );

    final result = await transport.pair(target, request);
    expect(result.unitWasUnclaimed, isTrue);
  });

  test('maps 404 (no pairing window) to windowClosed', () async {
    final transport = HttpPairingTransport(
      client: MockClient((req) async => http.Response('', 404)),
    );
    final result = await transport.pair(target, request);
    expect(result.outcome, PairingOutcome.windowClosed);
  });

  test('maps 403 to refused', () async {
    final transport = HttpPairingTransport(
      client: MockClient((req) async => http.Response('', 403)),
    );
    final result = await transport.pair(target, request);
    expect(result.outcome, PairingOutcome.refused);
  });

  test('maps 409 to alreadyPaired', () async {
    final transport = HttpPairingTransport(
      client: MockClient((req) async => http.Response('', 409)),
    );
    final result = await transport.pair(target, request);
    expect(result.outcome, PairingOutcome.alreadyPaired);
  });

  test('a real timeout maps to unreachable, not an uncaught exception', () async {
    final transport = HttpPairingTransport(
      timeout: const Duration(milliseconds: 50),
      client: MockClient((req) async {
        await Future.delayed(const Duration(seconds: 5));
        return http.Response('', 200);
      }),
    );
    final result = await transport.pair(target, request);
    expect(result.outcome, PairingOutcome.unreachable);
  });

  test('a connection error maps to unreachable, not an uncaught exception', () async {
    final transport = HttpPairingTransport(
      client: MockClient((req) async => throw http.ClientException('connection refused')),
    );
    final result = await transport.pair(target, request);
    expect(result.outcome, PairingOutcome.unreachable);
  });

  test('an unparseable 200 body is treated as refused, not a crash', () async {
    final transport = HttpPairingTransport(
      client: MockClient((req) async => http.Response('not json', 200)),
    );
    final result = await transport.pair(target, request);
    expect(result.outcome, PairingOutcome.refused);
  });
}
