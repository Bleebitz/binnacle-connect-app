import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:binnacle_connect/core/models/credential.dart';
import 'package:binnacle_connect/core/models/vessel_state.dart';
import 'package:binnacle_connect/core/services/control_channel_service.dart';
import 'package:binnacle_connect/core/services/command_result.dart';
import 'package:binnacle_connect/core/services/pairing_service.dart';

void main() {
  test('Socket reconnects without replaying commands; unpair stops retry', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final peers = <WebSocket>[];
    var commands = 0;
    // In-memory store: this test exercises socket/reconnect behavior, not
    // credential persistence — PairingService now defaults to
    // SecureCredentialStore (a real Keychain/Keystore-backed plugin), whose
    // platform channel isn't mocked in this plain `test()` (no
    // TestWidgetsFlutterBinding), so it must be overridden explicitly here.
    final pairing = PairingService(store: InMemoryCredentialStore());
    pairing.credential = DeviceCredential(credentialId: 'test', deviceId: 'test',
        coreHost: 'localhost', role: DeviceRole.owner, issuedAt: DateTime.now(), bearerToken: 'test');
    final control = ControlChannelService(demo: false)..attachPairing(pairing);
    server.listen((request) async {
      final peer = await WebSocketTransformer.upgrade(request);
      peers.add(peer);
      // Only 'cmd' frames count as commands — the very first frame on each
      // connection is now a real 'auth' frame (see control_channel_service's
      // AUTH note: the bearer token moved out of the URL and onto the wire
      // as the first message), which must not be mistaken for a replayed
      // command.
      peer.listen((raw) {
        if (jsonDecode(raw as String)['topic'] == 'cmd') commands++;
      });
      peer.add(jsonEncode({'topic': 'state', 'payload': {
        'seq': 1, 'ts': DateTime.now().toUtc().toIso8601String(),
        'capture': {'armed': true},
        'health': {'temp_c': 38, 'storage_free_pct': 70, 'thermal_state': 'nominal'},
      }}));
    });
    Future<void> until(bool Function() ready) async {
      for (var i = 0; i < 300 && !ready(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(ready(), isTrue);
    }
    try {
      final endpoint = Uri.parse('ws://127.0.0.1:${server.port}');
      await control.connect(deviceId: 'test', endpoint: endpoint);
      await until(() => control.status == LinkStatus.connected);
      final command = control.sendConfirmed('snapshot', {});
      await until(() => commands == 1);
      await peers.first.close();
      expect((await command).outcome, CommandOutcome.disconnected);
      await until(() => peers.length == 2 && control.status == LinkStatus.connected);
      expect(commands, 1);
      await control.connect(deviceId: 'test', endpoint: endpoint);
      expect(peers.length, 2);
      await pairing.unpair();
      control.attachPairing(pairing);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(control.status, LinkStatus.offline);
      expect(peers.length, 2);
    } finally {
      control.dispose();
      pairing.dispose();
      for (final peer in peers) { await peer.close(); }
      await server.close(force: true);
    }
  });

  test('Bearer token is sent as the first frame, never in the connection URL', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Uri? capturedRequestUri;
    final firstFrame = Completer<Map<String, dynamic>>();
    final pairing = PairingService(store: InMemoryCredentialStore());
    pairing.credential = DeviceCredential(credentialId: 'cred-7', deviceId: 'test',
        coreHost: 'localhost', role: DeviceRole.owner, issuedAt: DateTime.now(),
        bearerToken: 'super-secret-do-not-log-me');
    final control = ControlChannelService(demo: false)..attachPairing(pairing);
    server.listen((request) async {
      capturedRequestUri = request.uri;
      final peer = await WebSocketTransformer.upgrade(request);
      peer.listen((raw) {
        if (!firstFrame.isCompleted) {
          firstFrame.complete(jsonDecode(raw as String) as Map<String, dynamic>);
        }
      });
    });
    try {
      await control.connect(deviceId: 'test', endpoint: Uri.parse('ws://127.0.0.1:${server.port}'));
      final frame = await firstFrame.future.timeout(const Duration(seconds: 2));

      // The handshake URL — what a proxy or server access log would
      // actually record — must not contain the secret.
      expect(capturedRequestUri!.queryParameters.containsKey('token'), isFalse);
      expect(capturedRequestUri!.queryParameters.containsKey('credential_id'), isFalse);
      expect(capturedRequestUri.toString(), isNot(contains('super-secret-do-not-log-me')));

      // The token only ever appears in the first frame sent over the
      // already-encrypted (wss) socket.
      expect(frame['topic'], 'auth');
      expect(frame['payload']['token'], 'super-secret-do-not-log-me');
      expect(frame['payload']['credential_id'], 'cred-7');
    } finally {
      control.dispose();
      pairing.dispose();
      await server.close(force: true);
    }
  });

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
      final pairing = PairingService(store: InMemoryCredentialStore());
      pairing.credential = DeviceCredential(credentialId: 'test', deviceId: 'test',
          coreHost: 'localhost', role: DeviceRole.owner, issuedAt: DateTime.now(),
          bearerToken: 'test-only');
      final control = ControlChannelService(demo: false)..attachPairing(pairing);
      server.listen((request) async {
        peer = await WebSocketTransformer.upgrade(request);
        peer!.listen((raw) {
          final frame = jsonDecode(raw as String);
          // The first frame on the wire is now 'auth' (see control_channel_
          // service's AUTH note) — this harness only reacts to 'cmd' frames,
          // same as a real Core would dispatch by topic rather than assume
          // every message is a command.
          if (frame['topic'] != 'cmd') return;
          final command = frame['payload'];
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
