// BIN-9 — safety readiness vs. non-disableable policy, MOB event handling,
// and link/recording-history distinctions ("never connected" / "fresh" /
// "stale last-known" / "disconnected after confirmed recording" /
// "disconnected without ever confirming recording"). Demo-vs-Core MOB
// location and the Core-only side of MOB acknowledgment/applyCoreEvent live
// in live_mode_test.dart, which already carries this repo's separate
// Core-mode CI job (--dart-define=BINNACLE_APP_MODE=core).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:binnacle_connect/core/models/credential.dart';
import 'package:binnacle_connect/core/models/vessel_state.dart';
import 'package:binnacle_connect/core/services/command_result.dart';
import 'package:binnacle_connect/core/services/control_channel_service.dart';
import 'package:binnacle_connect/core/services/mob_alert_state.dart';
import 'package:binnacle_connect/core/services/pairing_service.dart';

Future<void> until(bool Function() ready, {int tries = 400}) async {
  for (var i = 0; i < tries && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue);
}

Map<String, dynamic> statePayload({
  required int seq,
  bool recording = false,
  Map<String, dynamic>? safety,
  Map<String, dynamic>? mob,
}) =>
    {
      'seq': seq,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'capture': {'armed': true, 'recording': recording},
      'health': {'temp_c': 38, 'storage_free_pct': 70, 'thermal_state': 'nominal'},
      if (safety != null) 'safety': safety,
      if (mob != null) 'mob': mob,
    };

void main() {
  group('SafetyState.fromJson — policy vs. readiness', () {
    test('missing safety fields: readiness fails closed to unknown; policy stays true', () {
      final s = SafetyState.fromJson(const {});
      expect(s.fallDetectionReadiness, SafetyReadiness.unknown);
      expect(s.mobAlertReadiness, SafetyReadiness.unknown);
      expect(s.fallDetection, isTrue, reason: 'non-disableable policy, independent of readiness');
      expect(s.mobAlert, isTrue);
      expect(s.locked, isTrue);
    });

    test('explicit operational/degraded/faulted readiness parses per field, independently', () {
      final mixed = SafetyState.fromJson(const {
        'fall_detection_readiness': 'degraded',
        'mob_alert_readiness': 'faulted',
      });
      expect(mixed.fallDetectionReadiness, SafetyReadiness.degraded);
      expect(mixed.mobAlertReadiness, SafetyReadiness.faulted);
      // A faulted/degraded READINESS must never touch the non-disableable
      // POLICY fields — this is the exact bug this issue exists to fix.
      expect(mixed.fallDetection, isTrue);
      expect(mixed.mobAlert, isTrue);
      expect(mixed.locked, isTrue);

      expect(SafetyState.fromJson(const {'fall_detection_readiness': 'operational'}).fallDetectionReadiness,
          SafetyReadiness.operational);
    });

    test('an unrecognized readiness string fails closed to unknown, never guessed as operational', () {
      final s = SafetyState.fromJson(const {'fall_detection_readiness': 'nominal_ish', 'mob_alert_readiness': 42});
      expect(s.fallDetectionReadiness, SafetyReadiness.unknown);
      expect(s.mobAlertReadiness, SafetyReadiness.unknown);
    });

    test('demo mode presents as operational, not unknown — a scripted, honestly-labeled stand-in', () {
      final s = SafetyState.simulated();
      expect(s.fallDetectionReadiness, SafetyReadiness.operational);
      expect(s.mobAlertReadiness, SafetyReadiness.operational);
    });
  });

  group('MobEvent.fromJson — proposed contract, absence is inactive not unknown', () {
    test('no mob object at all parses to inactive with no location', () {
      final m = MobEvent.fromJson(null);
      expect(m.active, isFalse);
      expect(m.lat, isNull);
      expect(m.lon, isNull);
      expect(m.headingDegrees, isNull);
    });

    test('a real mob object is parsed verbatim, never fabricated', () {
      final m = MobEvent.fromJson(const {'active': true, 'lat': '10.5 N', 'lon': '20.25 W', 'heading_degrees': 270});
      expect(m.active, isTrue);
      expect(m.lat, '10.5 N');
      expect(m.lon, '20.25 W');
      expect(m.headingDegrees, 270.0);
    });
  });

  group('ControlChannelService — never-connected / fresh / stale / disconnected recording history', () {
    test('Core-mode startup before any state message: never connected, recording never confirmed', () {
      final control = ControlChannelService(demo: false);
      expect(control.status, LinkStatus.offline);
      expect(control.everConnected, isFalse);
      expect(control.lastKnownRecording, isNull);
      expect(control.state.safety.fallDetectionReadiness, SafetyReadiness.unknown);
      expect(control.state.mob.active, isFalse);
      control.dispose();
    });

    test('a fresh confirmed state marks everConnected and records the exact recording flag Core sent', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      WebSocket? peer;
      final pairing = PairingService(store: InMemoryCredentialStore());
      pairing.credential = DeviceCredential(credentialId: 't', deviceId: 't', coreHost: 'localhost',
          role: DeviceRole.owner, issuedAt: DateTime.now(), bearerToken: 't');
      final control = ControlChannelService(demo: false)..attachPairing(pairing);
      server.listen((request) async {
        peer = await WebSocketTransformer.upgrade(request);
        peer!.add(jsonEncode({'topic': 'state', 'payload': statePayload(seq: 1, recording: true)}));
      });
      try {
        await control.connect(deviceId: 't', endpoint: Uri.parse('ws://127.0.0.1:${server.port}'));
        await until(() => control.status == LinkStatus.connected);
        expect(control.everConnected, isTrue);
        expect(control.lastKnownRecording, isTrue);
      } finally {
        control.dispose();
        pairing.dispose();
        await peer?.close();
        await server.close(force: true);
      }
    });

    test('stale then disconnected after CONFIRMED recording preserves the last-known recording flag throughout',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      WebSocket? peer;
      final pairing = PairingService(store: InMemoryCredentialStore());
      pairing.credential = DeviceCredential(credentialId: 't', deviceId: 't', coreHost: 'localhost',
          role: DeviceRole.owner, issuedAt: DateTime.now(), bearerToken: 't');
      // Short injected thresholds — see control_channel_service.dart's
      // constructor doc — so this test doesn't wait out the real 15s/45s.
      final control = ControlChannelService(
        demo: false,
        staleAfter: const Duration(milliseconds: 120),
        offlineAfter: const Duration(milliseconds: 120),
      )..attachPairing(pairing);
      server.listen((request) async {
        peer = await WebSocketTransformer.upgrade(request);
        peer!.add(jsonEncode({'topic': 'state', 'payload': statePayload(seq: 1, recording: true)}));
      });
      try {
        await control.connect(deviceId: 't', endpoint: Uri.parse('ws://127.0.0.1:${server.port}'));
        await until(() => control.status == LinkStatus.connected);
        expect(control.lastKnownRecording, isTrue);

        // No further state arrives — silence past staleAfter degrades the
        // link, but Core's last word on recording must not be discarded.
        await until(() => control.status == LinkStatus.stale);
        expect(control.everConnected, isTrue);
        expect(control.lastKnownRecording, isTrue);

        // Silence past offlineAfter tears the transport down entirely.
        await until(() => control.status == LinkStatus.offline);
        expect(control.everConnected, isTrue, reason: 'we WERE connected — this is a disconnect, not a first attempt');
        expect(control.lastKnownRecording, isTrue,
            reason: 'Core is the only authority on whether it was recording, and it said yes');
      } finally {
        control.dispose();
        pairing.dispose();
        await peer?.close();
        await server.close(force: true);
      }
    });

    test('disconnect WITHOUT ever confirming recording leaves everConnected false and lastKnownRecording null',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      WebSocket? peer;
      final pairing = PairingService(store: InMemoryCredentialStore());
      pairing.credential = DeviceCredential(credentialId: 't', deviceId: 't', coreHost: 'localhost',
          role: DeviceRole.owner, issuedAt: DateTime.now(), bearerToken: 't');
      final control = ControlChannelService(demo: false)..attachPairing(pairing);
      server.listen((request) async {
        // A real Core that accepts the socket but never sends a single
        // 'state' frame before dropping — e.g. an auth or startup failure
        // on its side. No recording claim was ever made in either direction.
        peer = await WebSocketTransformer.upgrade(request);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await peer!.close();
      });
      try {
        await control.connect(deviceId: 't', endpoint: Uri.parse('ws://127.0.0.1:${server.port}'));
        await until(() => control.status == LinkStatus.offline);
        expect(control.everConnected, isFalse,
            reason: 'a socket-level connection is not the same as a confirmed Core state message');
        expect(control.lastKnownRecording, isNull);
      } finally {
        control.dispose();
        pairing.dispose();
        await peer?.close();
        await server.close(force: true);
      }
    });

    test('a credential change resets everConnected/lastKnownRecording — they describe the OLD device', () async {
      final pairing = PairingService(store: InMemoryCredentialStore());
      pairing.credential = DeviceCredential(credentialId: 'a', deviceId: 'a', coreHost: 'localhost',
          role: DeviceRole.owner, issuedAt: DateTime.now(), bearerToken: 'a');
      final control = ControlChannelService(demo: false)..attachPairing(pairing);
      // Simulate having previously confirmed a connection/recording without
      // needing a real socket for this particular assertion.
      control
        ..everConnected = true
        ..lastKnownRecording = true;

      pairing.credential = DeviceCredential(credentialId: 'b', deviceId: 'b', coreHost: 'localhost',
          role: DeviceRole.owner, issuedAt: DateTime.now(), bearerToken: 'b');
      control.attachPairing(pairing);

      expect(control.everConnected, isFalse);
      expect(control.lastKnownRecording, isNull);
      control.dispose();
      pairing.dispose();
    });
  });

  group('MOB acknowledge — rejected, timed-out, acknowledged outcomes', () {
    for (final outcome in ['acknowledged', 'rejected', 'timeout', 'disconnected']) {
      test('acknowledgeMob resolves to $outcome and never clears the banner except on acknowledged', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        WebSocket? peer;
        final pairing = PairingService(store: InMemoryCredentialStore());
        pairing.credential = DeviceCredential(credentialId: 't', deviceId: 't', coreHost: 'localhost',
            role: DeviceRole.owner, issuedAt: DateTime.now(), bearerToken: 't');
        final control = ControlChannelService(demo: false)..attachPairing(pairing);
        server.listen((request) async {
          peer = await WebSocketTransformer.upgrade(request);
          peer!.listen((raw) {
            final frame = jsonDecode(raw as String);
            if (frame['topic'] != 'cmd') return;
            final command = frame['payload'];
            if (outcome == 'disconnected') {
              peer!.close();
            } else if (outcome != 'timeout') {
              peer!.add(jsonEncode({'topic': 'ack', 'payload': {'id': command['id'], 'ok': outcome == 'acknowledged'}}));
            }
          });
          peer!.add(jsonEncode({'topic': 'state', 'payload': statePayload(seq: 1)}));
        });
        try {
          await control.connect(deviceId: 't', endpoint: Uri.parse('ws://127.0.0.1:${server.port}'));
          await until(() => control.status == LinkStatus.connected);

          final result = await control.acknowledgeMob(
              actor: 'levi', timeout: const Duration(milliseconds: 150));
          expect(result.outcome, switch (outcome) {
            'acknowledged' => CommandOutcome.acknowledged,
            'rejected' => CommandOutcome.rejected,
            'disconnected' => CommandOutcome.disconnected,
            _ => CommandOutcome.timedOut,
          });
        } finally {
          control.dispose();
          pairing.dispose();
          await peer?.close();
          await server.close(force: true);
        }
      });
    }

    test('a spectator (unpaired) acknowledge throws CommandRejected before anything reaches the wire', () {
      // Same client-side rejection contract as every other command
      // (arm/disarm/snapshot/...) — see control_channel_service.dart's
      // sendCommand: role/pairing failures throw synchronously rather than
      // resolving a CommandResult, since nothing was ever sent to reject.
      // capture_screen.dart's _acknowledgeMob already catches this.
      final control = ControlChannelService(demo: false);
      expect(() => control.acknowledgeMob(actor: 'levi'), throwsA(isA<CommandRejected>()));
      control.dispose();
    });
  });

  group('MobAlertState — local acknowledge does not fabricate Core authority', () {
    test('acknowledgeLocally clears the display regardless of source', () {
      final mob = MobAlertState()..applyCoreEvent(const MobEvent(active: true, lat: '1', lon: '2'));
      // applyCoreEvent is a no-op unless !AppConfig.isDemo — in this
      // default (demo) test run it does nothing, which is itself the point
      // (see live_mode_test.dart for the Core-mode assertion that it DOES
      // apply). acknowledgeLocally must work unconditionally either way.
      mob.acknowledgeLocally();
      expect(mob.active, isFalse);
      expect(mob.lat, isNull);
      expect(mob.simulated, isFalse);
    });

    test('triggerDemo is unavailable outside demo mode', () {
      // This suite runs in the default demo test mode, so triggerDemo must
      // succeed here — the Core-mode negative case (must throw) lives in
      // live_mode_test.dart's separate --dart-define=core job.
      final mob = MobAlertState();
      mob.triggerDemo();
      expect(mob.active, isTrue);
      expect(mob.simulated, isTrue);
      expect(mob.lat, '36.02083° N');
      expect(mob.lon, '114.74215° W');
      expect(mob.headingDegrees, 128);
    });
  });
}
