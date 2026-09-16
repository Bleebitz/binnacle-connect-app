import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:binnacle_connect/core/models/credential.dart';
import 'package:binnacle_connect/core/models/vessel_state.dart';
import 'package:binnacle_connect/core/services/control_channel_service.dart';
import 'package:binnacle_connect/core/services/command_result.dart';
import 'package:binnacle_connect/core/services/pairing_service.dart';

void main() {
  test('Core starts offline and rejects commands before pairing', () {
    final control = ControlChannelService(demo: false);
    expect(control.status, LinkStatus.offline);
    expect(control.hasCurrentState, isFalse);
    expect(control.state.capture.armed, isFalse);
    expect(() => control.snapshot(), throwsA(isA<CommandRejected>()));
    control.dispose();
  });

  test('Demo refuses network connection', () async {
    final control = ControlChannelService(demo: true);
    await expectLater(control.connect(deviceId: 'test', endpoint: Uri.parse('ws://localhost')),
        throwsStateError);
    control.dispose();
  });

  for (final outcome in ['success', 'reject', 'missing', 'timeout', 'disconnect']) {
    test('Capture outcome: $outcome', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      WebSocket? peer;
      final pairing = PairingService();
      pairing.credential = DeviceCredential(credentialId: 'test', deviceId: 'test',
          coreHost: 'localhost', role: DeviceRole.owner, issuedAt: DateTime.now(),
          bearerToken: 'test-only');
      final control = ControlChannelService(demo: false)..attachPairing(pairing);
      server.listen((request) async {
        peer = await WebSocketTransformer.upgrade(request);
        peer!.listen((raw) {
          final command = jsonDecode(raw as String)['payload'];
          if (outcome == 'disconnect') {
            peer!.close();
          } else if (outcome != 'timeout') {
            peer!.add(jsonEncode({'topic': 'ack', 'payload': {
              'id': command['id'],
              if (outcome != 'missing') 'ok': outcome == 'success',
            }}));
          }
        });
        peer!.add(jsonEncode({'topic': 'state', 'payload': {
          'seq': 1, 'ts': DateTime.now().toUtc().toIso8601String(),
          'capture': {'armed': true},
          'health': {'temp_c': 38, 'storage_free_pct': 70, 'thermal_state': 'nominal'},
        }}));
      });
      try {
        await control.connect(deviceId: 'test',
            endpoint: Uri.parse('ws://127.0.0.1:${server.port}'));
        for (var i = 0; i < 100 && !control.hasCurrentState; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(control.status, LinkStatus.connected);
        final pending = control.sendConfirmed('snapshot', {}, timeout: const Duration(milliseconds: 100));
        expect(control.isPending('snapshot'), isTrue);
        final result = await pending;
        expect(result.outcome, switch (outcome) {
          'success' => CommandOutcome.acknowledged,
          'reject' => CommandOutcome.rejected,
          'disconnect' => CommandOutcome.disconnected,
          _ => CommandOutcome.timedOut,
        });
        expect(control.isPending('snapshot'), isFalse);
        expect(control.state.capture.recording, isFalse);
      } finally {
        control.dispose();
        pairing.dispose();
        await peer?.close();
        await server.close(force: true);
      }
    });
  }
}
