// Unit tests for ControlChannelService's WebRTC signaling — the real,
// testable half of real WebRTC support (see webrtc_service.dart's module
// comment for why offer/answer/ICE ride this same authenticated socket
// rather than a second connection, and why RTCPeerConnection itself isn't
// exercised here: it needs the native flutter_webrtc plugin, which has no
// platform channel under `flutter test`'s bare Dart VM — these tests cover
// everything around that boundary with a real local WebSocket server,
// the same way pairing_transport_test.dart covers HttpPairingTransport
// without a live Core to hit.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:binnacle_connect/core/models/credential.dart';
import 'package:binnacle_connect/core/models/vessel_state.dart';
import 'package:binnacle_connect/core/services/control_channel_service.dart';
import 'package:binnacle_connect/core/services/pairing_service.dart';

void main() {
  test('sendWebRtcSignal throws CommandRejected when not connected', () {
    final control = ControlChannelService(demo: false);
    expect(() => control.sendWebRtcSignal('webrtc_offer', {'sdp': 'x'}),
        throwsA(isA<CommandRejected>()));
    control.dispose();
  });

  test('a real offer frame is sent over the wire, and a real answer frame arrives back',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final firstFrame = Completer<Map<String, dynamic>>();
    WebSocket? peer;
    final pairing = PairingService(store: InMemoryCredentialStore());
    pairing.credential = DeviceCredential(credentialId: 'cred-1', deviceId: 'test',
        coreHost: 'localhost', role: DeviceRole.owner, issuedAt: DateTime.now(),
        bearerToken: 'test');
    final control = ControlChannelService(demo: false)..attachPairing(pairing);

    server.listen((request) async {
      peer = await WebSocketTransformer.upgrade(request);
      peer!.listen((raw) {
        final frame = jsonDecode(raw as String) as Map<String, dynamic>;
        // Skip the auth frame (see control_channel_service's AUTH note) —
        // this test is about signaling frames specifically.
        if (frame['topic'] == 'webrtc_offer' && !firstFrame.isCompleted) {
          firstFrame.complete(frame);
        }
      });
      peer!.add(jsonEncode({'topic': 'state', 'payload': {
        'seq': 1, 'ts': DateTime.now().toUtc().toIso8601String(),
        'capture': {'armed': true},
        'health': {'temp_c': 38, 'storage_free_pct': 70, 'thermal_state': 'nominal'},
      }}));
    });

    try {
      await control.connect(deviceId: 'test', endpoint: Uri.parse('ws://127.0.0.1:${server.port}'));
      for (var i = 0; i < 100 && control.status != LinkStatus.connected; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(control.status, LinkStatus.connected);

      final receivedAnswers = <Map<String, dynamic>>[];
      final sub = control.webrtcSignals.listen(receivedAnswers.add);

      control.sendWebRtcSignal('webrtc_offer', {
        'device_id': 'test',
        'sdp': 'v=0 fake-offer-sdp',
        'type': 'offer',
      });

      final offerFrame = await firstFrame.future.timeout(const Duration(seconds: 2));
      expect(offerFrame['topic'], 'webrtc_offer');
      expect(offerFrame['payload']['sdp'], 'v=0 fake-offer-sdp');
      expect(offerFrame['payload']['type'], 'offer');

      // Server sends back a real 'webrtc_answer' frame — proves the client
      // actually surfaces it through webrtcSignals, not just constructs
      // outgoing frames.
      peer!.add(jsonEncode({'topic': 'webrtc_answer', 'payload': {
        'sdp': 'v=0 fake-answer-sdp', 'type': 'answer',
      }}));
      for (var i = 0; i < 100 && receivedAnswers.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(receivedAnswers, hasLength(1));
      expect(receivedAnswers.first['topic'], 'webrtc_answer');
      expect(receivedAnswers.first['payload']['sdp'], 'v=0 fake-answer-sdp');

      await sub.cancel();
    } finally {
      control.dispose();
      pairing.dispose();
      await peer?.close();
      await server.close(force: true);
    }
  });

  test('a malformed webrtc frame (non-Map payload) is dropped, not crashed on', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    WebSocket? peer;
    final pairing = PairingService(store: InMemoryCredentialStore());
    pairing.credential = DeviceCredential(credentialId: 'cred-1', deviceId: 'test',
        coreHost: 'localhost', role: DeviceRole.owner, issuedAt: DateTime.now(),
        bearerToken: 'test');
    final control = ControlChannelService(demo: false)..attachPairing(pairing);

    server.listen((request) async {
      peer = await WebSocketTransformer.upgrade(request);
      peer!.add(jsonEncode({'topic': 'state', 'payload': {
        'seq': 1, 'ts': DateTime.now().toUtc().toIso8601String(),
        'capture': {'armed': true},
        'health': {'temp_c': 38, 'storage_free_pct': 70, 'thermal_state': 'nominal'},
      }}));
    });

    try {
      await control.connect(deviceId: 'test', endpoint: Uri.parse('ws://127.0.0.1:${server.port}'));
      for (var i = 0; i < 100 && control.status != LinkStatus.connected; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final received = <Map<String, dynamic>>[];
      final sub = control.webrtcSignals.listen(received.add);

      peer!.add(jsonEncode({'topic': 'webrtc_answer', 'payload': 'not-a-map'}));
      peer!.add(jsonEncode({'topic': 'webrtc_answer', 'payload': {'sdp': 'ok'}}));
      for (var i = 0; i < 100 && received.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // Only the well-formed frame comes through — the malformed one never
      // reaches a listener (and never threw inside _onMessage either, or
      // this test would have failed via an unhandled exception).
      expect(received, hasLength(1));
      expect(received.first['payload']['sdp'], 'ok');

      await sub.cancel();
    } finally {
      control.dispose();
      pairing.dispose();
      await peer?.close();
      await server.close(force: true);
    }
  });
}
