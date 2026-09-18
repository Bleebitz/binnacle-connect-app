// Minimal WHEP (WebRTC-HTTP Egress Protocol) client: POSTs a real SDP
// offer to a local WHEP endpoint, applies the returned SDP answer, and
// exposes the resulting remote video track + a 'telemetry' DataChannel.
// This talks to a local media server (e.g. MediaMTX) directly over HTTP —
// it is a different transport from webrtc_service.dart's control-channel
// signaling (WebRtcService/RtcVideoRenderer talk to the Core over the
// authenticated WSS control channel instead), so it deliberately doesn't
// reuse that class; the two are for different peers.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import 'telemetry_frame.dart';

enum WhepConnectionStatus { idle, connecting, live, failed }

class WhepClient {
  /// Full URL of the WHEP endpoint, e.g. `http://192.168.1.50:8889/vision/whep`.
  final String endpoint;
  final Duration negotiationTimeout;
  final http.Client _http;

  WhepClient({
    required this.endpoint,
    this.negotiationTimeout = const Duration(seconds: 10),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  RTCPeerConnection? _pc;
  RTCVideoRenderer? _renderer;
  RTCDataChannel? _telemetryChannel;

  /// The WHEP "resource" URL returned via the `Location` header on a
  /// successful POST — DELETE-ing it is how a WHEP session is torn down
  /// server-side. Null until a session is established.
  Uri? _resourceUrl;

  WhepConnectionStatus status = WhepConnectionStatus.idle;
  String? failureReason;

  RTCVideoRenderer? get renderer => _renderer;

  final _statusController = StreamController<void>.broadcast();
  Stream<void> get onStatusChange => _statusController.stream;

  final _telemetryController = StreamController<TelemetryFrame>.broadcast();
  Stream<TelemetryFrame> get telemetry => _telemetryController.stream;

  /// Incremented on every telemetry DataChannel message that failed to
  /// parse into a [TelemetryFrame] — a dropped/corrupt packet is expected
  /// on a best-effort channel, not fatal, but callers may want to surface
  /// a "signal degraded" indicator once this climbs.
  int droppedPacketCount = 0;

  void _setStatus(WhepConnectionStatus s, {String? reason}) {
    status = s;
    failureReason = reason;
    if (!_statusController.isClosed) _statusController.add(null);
  }

  Future<void> connect() async {
    if (status == WhepConnectionStatus.connecting ||
        status == WhepConnectionStatus.live) {
      return;
    }
    _setStatus(WhepConnectionStatus.connecting);
    try {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      _renderer = renderer;

      final pc = await createPeerConnection({
        'iceServers': <Map<String, dynamic>>[],
        'sdpSemantics': 'unified-plan',
      });
      _pc = pc;

      final trackArrived = Completer<void>();
      pc.onTrack = (RTCTrackEvent event) {
        if (event.track.kind == 'video' && event.streams.isNotEmpty) {
          renderer.srcObject = event.streams.first;
          if (!trackArrived.isCompleted) trackArrived.complete();
        }
      };

      // The media server drives the 'telemetry' channel — this client only
      // listens, it never creates its own competing channel of the same
      // name.
      pc.onDataChannel = (RTCDataChannel channel) {
        if (channel.label != 'telemetry') return;
        _attachTelemetryChannel(channel);
      };

      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _waitForIceGatheringComplete(pc);

      final localSdp = (await pc.getLocalDescription())?.sdp;
      if (localSdp == null) {
        throw StateError('Local SDP offer was empty');
      }

      final response = await _http
          .post(
            Uri.parse(endpoint),
            headers: const {'Content-Type': 'application/sdp'},
            body: localSdp,
          )
          .timeout(negotiationTimeout);

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw StateError(
            'WHEP endpoint rejected offer: HTTP ${response.statusCode}');
      }
      final location = response.headers['location'];
      if (location != null) {
        _resourceUrl = Uri.parse(endpoint).resolve(location);
      }

      final answerSdp = response.body;
      if (answerSdp.trim().isEmpty) {
        throw StateError('WHEP endpoint returned an empty SDP answer');
      }
      await pc.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));

      await trackArrived.future.timeout(
        negotiationTimeout,
        onTimeout: () => throw TimeoutException(
            'No remote video track within ${negotiationTimeout.inSeconds}s'),
      );

      _setStatus(WhepConnectionStatus.live);
    } catch (e) {
      _setStatus(WhepConnectionStatus.failed, reason: e.toString());
      await _teardownPeerConnection();
    }
  }

  Future<void> _waitForIceGatheringComplete(RTCPeerConnection pc) async {
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final completer = Completer<void>();
    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        completer.complete();
      }
    };
    await completer.future.timeout(
      negotiationTimeout,
      onTimeout: () {
        // Non-trickle WHEP needs a complete candidate set, but a slow/absent
        // local network shouldn't hang the whole negotiation forever —
        // proceed with whatever candidates gathered so far.
      },
    );
  }

  void _attachTelemetryChannel(RTCDataChannel channel) {
    _telemetryChannel = channel;
    // onMessage is a callback slot, not a Stream — wrap the whole body in
    // try/catch since a single malformed/binary packet on this
    // best-effort channel must never throw out of the channel's own
    // native callback.
    channel.onMessage = (RTCDataChannelMessage message) {
      try {
        if (message.isBinary) {
          droppedPacketCount++;
          return;
        }
        final parsed = jsonDecode(message.text);
        if (parsed is! Map<String, dynamic>) {
          droppedPacketCount++;
          return;
        }
        final frame = TelemetryFrame.tryParse(parsed);
        if (frame == null) {
          droppedPacketCount++;
          return;
        }
        if (!_telemetryController.isClosed) _telemetryController.add(frame);
      } catch (_) {
        droppedPacketCount++;
      }
    };
  }

  Future<void> _teardownPeerConnection() async {
    _telemetryChannel?.onMessage = null;
    await _telemetryChannel?.close();
    _telemetryChannel = null;
    await _pc?.close();
    _pc = null;
    await _renderer?.dispose();
    _renderer = null;
  }

  Future<void> disconnect() async {
    final resource = _resourceUrl;
    _resourceUrl = null;
    await _teardownPeerConnection();
    if (resource != null) {
      try {
        await _http.delete(resource).timeout(negotiationTimeout);
      } catch (_) {
        // Best-effort session teardown on the server — the local
        // PeerConnection is already closed either way.
      }
    }
    _setStatus(WhepConnectionStatus.idle);
  }

  void dispose() {
    disconnect();
    _telemetryController.close();
    _statusController.close();
    _http.close();
  }
}
