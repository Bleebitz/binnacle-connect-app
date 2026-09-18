// Live view: real remote video from a local WHEP endpoint, with a
// tracking HUD painted on top from the 'telemetry' DataChannel. See
// whep_client.dart for the transport and hud_painter.dart for the paint
// logic — this screen just wires the two into a Stack and renders
// whichever WhepConnectionStatus is current.

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'hud_painter.dart';
import 'telemetry_frame.dart';
import 'whep_client.dart';

class LiveViewScreen extends StatefulWidget {
  final String whepEndpoint;

  const LiveViewScreen({super.key, required this.whepEndpoint});

  @override
  State<LiveViewScreen> createState() => _LiveViewScreenState();
}

class _LiveViewScreenState extends State<LiveViewScreen> {
  late final WhepClient _client;
  TelemetryFrame? _latestFrame;

  @override
  void initState() {
    super.initState();
    _client = WhepClient(endpoint: widget.whepEndpoint);
    _client.telemetry.listen((frame) {
      if (!mounted) return;
      setState(() => _latestFrame = frame);
    });
    _client.connect();
  }

  @override
  void dispose() {
    _client.dispose();
    super.dispose();
  }

  double _videoAspectRatio() {
    final track = _client.renderer?.videoWidth;
    final height = _client.renderer?.videoHeight;
    if (track != null && height != null && track > 0 && height > 0) {
      return track / height;
    }
    return 16 / 9;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: StreamBuilder<void>(
          stream: _client.onStatusChange,
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                _buildVideoLayer(),
                if (_client.status == WhepConnectionStatus.live)
                  HudOverlay(
                    frame: _latestFrame,
                    videoAspectRatio: _videoAspectRatio(),
                  ),
                _buildStatusBadge(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideoLayer() {
    switch (_client.status) {
      case WhepConnectionStatus.idle:
      case WhepConnectionStatus.connecting:
        return const Center(
          child: CircularProgressIndicator(color: Colors.white70),
        );
      case WhepConnectionStatus.live:
        final renderer = _client.renderer;
        if (renderer == null) {
          return const Center(
            child: Text('Live video unavailable',
                style: TextStyle(color: Colors.white70)),
          );
        }
        return RTCVideoView(renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain);
      case WhepConnectionStatus.failed:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Couldn\'t reach the live feed'
              '${_client.failureReason != null ? '\n${_client.failureReason}' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        );
    }
  }

  Widget _buildStatusBadge() {
    if (_client.status != WhepConnectionStatus.failed) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 12,
      right: 12,
      child: ElevatedButton(
        onPressed: () => _client.connect(),
        child: const Text('Retry'),
      ),
    );
  }
}
