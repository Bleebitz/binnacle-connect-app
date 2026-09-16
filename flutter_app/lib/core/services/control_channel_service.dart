// Control channel client — implements
// Connect_Platform_and_Control_Channel_CORRECTED_v2.0_2026-09-12.
//
// TRANSPORT: HTTPS/WSS to the Core, per C-07. This class does NOT talk to
// sensors or Switch directly, and does not use MQTT — that design was
// superseded (see CORRECTION_Connect_Not_Spotter_and_Control_Channel_Conflict).
//
// CORE PRINCIPLE (§0 of the corrected doc): the Core is the state authority.
// This service never optimistically mutates VesselState locally. A command
// produces a "pending" UI state; VesselState only changes when a new state
// message arrives from the Core.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/vessel_state.dart';
import '../models/credential.dart';
import 'pairing_service.dart';
import '../app_config.dart';
import 'command_result.dart';

// Commands that MUST NEVER EXIST. Per protocol §1.2: absence, not a
// confirmation dialog. If a caller ever tries one of these, it is rejected
// in-process before anything is sent over the wire.
const Set<String> kNoDisableCommands = {
  'set_fall_detection',
  'set_mob_alert',
  'disable_safety',
};

class PendingCommand {
  final String id;
  final String command;
  final DateTime sentAt;
  PendingCommand(this.id, this.command, this.sentAt);
}

class CommandRejected implements Exception {
  final String reason;
  CommandRejected(this.reason);
  @override
  String toString() => 'CommandRejected: $reason';
}

class ControlChannelService extends ChangeNotifier {
  final Uuid _uuid = const Uuid();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _pendingSweeper;
  Timer? _retryTimer;
  Timer? _connectDeadline;
  Uri? _endpoint;
  String? _deviceId;
  int _generation = 0;
  int _retryAttempt = 0;
  int? _lastSequence;
  DeviceCredential? _attachedCredential;

  final bool demo;
  ControlChannelService({bool? demo}) : demo = demo ?? AppConfig.isDemo {
    status = this.demo ? LinkStatus.simulated : LinkStatus.offline;
    state = this.demo ? VesselState.simulated() : VesselState.fromJson({});
  }
  late LinkStatus status;
  late VesselState state;
  bool get hasCurrentState => demo || status == LinkStatus.connected;
  final Map<String, Completer<CommandResult>> _results = {};
  final Map<String, Timer> _resultTimers = {};

  Future<CommandResult> sendConfirmed(String command, Map<String, dynamic> params,
      {Duration timeout = const Duration(seconds: 5)}) {
    final id = sendCommand(command, params);
    final result = Completer<CommandResult>();
    _results[id] = result;
    _resultTimers[id] = Timer(timeout,
        () => _finish(id, const CommandResult(CommandOutcome.timedOut)));
    return result.future;
  }

  void _finish(String id, CommandResult result) {
    _pending.remove(id);
    _resultTimers.remove(id)?.cancel();
    _results.remove(id)?.complete(result);
  }

  void _failOutstanding() {
    for (final id in _results.keys.toList()) {
      _finish(id, const CommandResult(CommandOutcome.disconnected));
    }
    _pending.clear();
  }
  DateTime lastSeen = DateTime.now();
  final Map<String, PendingCommand> _pending = {};

  bool manualFramingFlagged = false; // mirrors framing.control_mode == manual

  /// Supplies the credential and role. Injected rather than owned so the
  /// pairing lifecycle stays in one place.
  PairingService? _pairing;
  void attachPairing(PairingService p) {
    final changed = _attachedCredential != p.credential;
    _pairing = p;
    _attachedCredential = p.credential;
    if (!demo && changed) {
      _closeTransport();
      status = LinkStatus.offline;
      _retryAttempt = 0;
    }
  }

  void _closeTransport() {
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _connectDeadline?.cancel();
    _pendingSweeper?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _lastSequence = null;
    _failOutstanding();
  }

  void _lostConnection(int generation) {
    if (_disposed || generation != _generation) return;
    _closeTransport();
    _setStatus(LinkStatus.offline);
    if (!isPaired || _endpoint == null || _deviceId == null) return;
    final seconds = 1 << _retryAttempt.clamp(0, 5);
    _retryAttempt++;
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      if (!_disposed && isPaired) {
        connect(deviceId: _deviceId!, endpoint: _endpoint!);
      }
    });
  }

  DeviceRole get role => _pairing?.role ?? DeviceRole.spectator; // fail closed
  bool get isPaired => _pairing?.isPaired ?? false;

  /// UX affordance only — the Core re-checks every command. Use this to
  /// disable controls, never as the security boundary (see credential.dart).
  bool canSend(String command) => RolePolicy.can(role, command);
  bool canBroadcast(String mode) => RolePolicy.canBroadcast(role, mode);

  /// Connect to wss://<host>/spotter/{deviceId}/ws — the actual endpoint
  /// shape is a placeholder pending the real Core API contract; this
  /// establishes the client-side pattern (auth token, reconnect, LWT-style
  /// availability) so swapping in the real URL is a one-line change.
  Future<void> connect({required String deviceId, required Uri endpoint, String? authToken}) async {
    if (demo) throw StateError('Demo cannot open a Core socket');
    if (!isPaired) throw CommandRejected('not_paired');
    if (_pairing!.credential!.deviceId != deviceId ||
        (endpoint.host != _pairing!.credential!.coreHost &&
         !(endpoint.host == '127.0.0.1' && _pairing!.credential!.coreHost == 'localhost'))) {
      throw CommandRejected('credential_target_mismatch');
    }
    if (endpoint.scheme != 'wss' &&
        !(endpoint.scheme == 'ws' && (endpoint.host == '127.0.0.1' || endpoint.host == 'localhost'))) {
      throw CommandRejected('secure_transport_required');
    }
    if (_disposed) throw StateError('Control channel disposed');
    if (_channel != null && _endpoint == endpoint && _deviceId == deviceId) return;
    _closeTransport();
    _endpoint = endpoint;
    _deviceId = deviceId;
    final generation = _generation;
    status = LinkStatus.connecting;
    notifyListeners();
    try {
      // Credential from pairing takes precedence over any explicitly passed
      // token. auth_method is sent from day one so a Core can support bearer
      // and mTLS during transition, and an old client fails cleanly (§4.3c).
      final cred = _pairing?.credential;
      final token = cred?.bearerToken ?? authToken;
      _channel = WebSocketChannel.connect(
        endpoint.replace(queryParameters: {
          'device_id': deviceId,
          'auth_method': cred?.authMethod ?? 'bearer',
          if (cred != null) 'credential_id': cred.credentialId,
          if (token != null) 'token': token,
        }),
      );
      _subscription = _channel!.stream.listen(
        (raw) { if (generation == _generation) _onMessage(raw); },
        onDone: () => _lostConnection(generation),
        onError: (_) => _lostConnection(generation),
      );
      _connectDeadline = Timer(const Duration(seconds: 10), () => _lostConnection(generation));
      _pendingSweeper = Timer.periodic(const Duration(seconds: 1), (_) => _sweepPending());
    } catch (_) {
      _lostConnection(generation);
    }
  }

  void _onMessage(dynamic raw) {
    if (_disposed) return;
    try {
      final Map<String, dynamic> j = jsonDecode(raw as String);
      final topic = j['topic'] as String?;
      if (topic == 'state') {
        final payload = j['payload'];
        if (payload is! Map<String, dynamic> ||
            payload['seq'] is! int ||
            payload['ts'] is! String ||
            DateTime.tryParse(payload['ts']) == null ||
            payload['capture'] is! Map ||
            payload['health'] is! Map ||
            payload['health']['temp_c'] is! num ||
            payload['health']['storage_free_pct'] is! int ||
            payload['health']['thermal_state'] is! String) {
          return;
        }
        final seq = payload['seq'] as int;
        if (_lastSequence != null && seq <= _lastSequence!) return;
        state = VesselState.fromJson(j['payload']);
        _lastSequence = seq;
        _connectDeadline?.cancel();
        _retryAttempt = 0;
        manualFramingFlagged = state.framing.isManual;
        lastSeen = DateTime.now();
        _setStatus(LinkStatus.connected);
      } else if (topic == 'ack') {
        final id = j['payload']['id'] as String?;
        if (id != null && j['payload']['ok'] is bool) {
          _finish(id, CommandResult(j['payload']['ok'] == true
              ? CommandOutcome.acknowledged : CommandOutcome.rejected));
        }
        notifyListeners();
      }
    } catch (_) {
      debugPrint('ControlChannelService: malformed message ignored');
    }
  }

  void _setStatus(LinkStatus s) {
    if (_disposed) return;
    status = s;
    if (s == LinkStatus.offline || s == LinkStatus.stale) _failOutstanding();
    notifyListeners();
  }

  void _sweepPending() {
    if (!isPaired) {
      _closeTransport();
      _setStatus(LinkStatus.offline);
      return;
    }
    final now = DateTime.now();
    final timedOut = _pending.values
        .where((p) => now.difference(p.sentAt) > const Duration(seconds: 2))
        .toList();
    for (final p in timedOut) {
      if (!_results.containsKey(p.id)) _pending.remove(p.id);
    }
    // On prolonged silence from the Core, degrade the displayed link status.
    // Per §1.1 / §4.3: the Core keeps recording regardless — the UI must say
    // so, never imply capture stopped.
    final silentFor = now.difference(lastSeen);
    if (status == LinkStatus.connected && silentFor > const Duration(seconds: 15)) {
      _setStatus(LinkStatus.stale);
    } else if (status == LinkStatus.stale && silentFor > const Duration(seconds: 45)) {
      _lostConnection(_generation);
    }
    if (timedOut.isNotEmpty) notifyListeners();
  }

  bool get isOffline => status == LinkStatus.offline;

  /// Sends a command. Returns the command id on success.
  /// Throws [CommandRejected] for any command in [kNoDisableCommands] —
  /// this is enforced here, in the client, not only on the Core, so a
  /// caller can never even construct the wire message.
  String sendCommand(String command, Map<String, dynamic> params, {String? actor}) {
    if (kNoDisableCommands.contains(command)) {
      throw CommandRejected('safety_not_disableable');
    }
    // Role gate. A spectator's allowed set is EMPTY by design (§3), so this
    // rejects every command from a spectator. This is a UX affordance, not
    // the security boundary — the Core re-checks every command independently.
    if (!RolePolicy.can(role, command)) {
      throw CommandRejected('role_not_permitted:${role.wire}');
    }
    final id = 'c-${_uuid.v4().substring(0, 8)}';
    final envelope = {
      'id': id,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'actor': actor ?? 'unknown',
      'command': command,
      'params': params,
    };
    if (demo && status == LinkStatus.simulated) {
      // No real Core to talk to yet — simulate an ack so the UI is testable
      // end to end without hardware. This branch is the only place that
      // fabricates state; it must be removed once a real device pairs.
      Future.delayed(const Duration(milliseconds: 150), () {
        _finish(id, const CommandResult(CommandOutcome.acknowledged));
        if (!_disposed) notifyListeners();
      });
      _pending[id] = PendingCommand(id, command, DateTime.now());
      notifyListeners();
      return id;
    }
    if (_channel == null || status != LinkStatus.connected || !isPaired) {
      throw CommandRejected('link_offline');
    }
    _pending[id] = PendingCommand(id, command, DateTime.now());
    _channel!.sink.add(jsonEncode({'topic': 'cmd', 'payload': envelope}));
    notifyListeners();
    return id;
  }

  bool isPending(String command) => _pending.values.any((p) => p.command == command);

  // ---- Convenience wrappers over sendCommand for the vocabulary in
  // Connect_Platform_and_Control_Channel_CORRECTED_v2.0 §6. Note there is
  // no arm/disarm ambiguity with safety: these toggle CAPTURE, not the
  // always-on fall/MOB detection.
  void arm({String? actor}) => sendCommand('arm', {}, actor: actor);
  void disarm({String? actor}) => sendCommand('disarm', {}, actor: actor);
  void saveHighlight({int? preS, int? postS, String? actor}) =>
      sendCommand('save_highlight', {'pre_s': preS, 'post_s': postS}, actor: actor);
  void snapshot({String? actor}) => sendCommand('snapshot', {}, actor: actor);
  void setTriggerMode(String mode, {String? actor}) =>
      sendCommand('set_trigger_mode', {'mode': mode}, actor: actor);
  void loadPreset(String preset, {String? actor}) =>
      sendCommand('load_preset', {'preset': preset}, actor: actor);

  /// Manual zoom implies control_mode=manual per §1.3 — it HOLDS until
  /// setControlMode('ai') is explicitly called. No timeout, no auto-resume.
  void nudgeZoom(double delta, {String? actor}) =>
      sendCommand('nudge_zoom', {'delta': delta}, actor: actor);
  void setControlMode(String mode, {String? actor}) =>
      sendCommand('set_control_mode', {'mode': mode}, actor: actor);

  void acknowledgeMob({String? actor}) => sendCommand('acknowledge_mob', {}, actor: actor);

  /// Broadcast. mode "boat" is crew-allowed; mode "public" is OWNER ONLY —
  /// this single restriction is what closes the exposure identified in
  /// Connect_Platform_and_Control_Channel_CORRECTED_v2.0 §8 (§3.1).
  void startBroadcast(String mode, {String? actor}) {
    if (!RolePolicy.canBroadcast(role, mode)) {
      throw CommandRejected('role_not_permitted_for_broadcast:${role.wire}/$mode');
    }
    sendCommand(mode == 'public' ? 'start_broadcast_public' : 'start_broadcast_boat',
        {'mode': mode}, actor: actor);
  }

  void stopBroadcast({String? actor}) => sendCommand('stop_broadcast', {}, actor: actor);

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    _closeTransport();
    super.dispose();
  }
}
