// Real, lossless video trim via Android's platform MediaExtractor/
// MediaMuxer (see MainActivity.kt) — no GPL/FFmpeg. Produces a NEW mp4
// containing only the selected range; the source file is never modified.
//
// Limits, stated plainly: cuts snap to the nearest preceding keyframe (a
// lossless trim can't start mid-GOP), so the exported start may be up to
// one GOP earlier than chosen. Crop/framing is NOT baked into the file
// (that needs a re-encode); it stays an EditDefinition applied at
// playback. Android only — other platforms report unavailable.

import 'dart:io';

import 'package:flutter/services.dart';

enum TrimFailure { insufficientSpace, missingSource, unsupported, busy, unknown }

class TrimException implements Exception {
  final TrimFailure reason;
  final String message;
  TrimException(this.reason, this.message);
  @override
  String toString() => message;
}

abstract class VideoTrimService {
  bool get isAvailable;

  /// Returns true when exported, false when cancelled. Throws [TrimException].
  Future<bool> trim({
    required String source,
    required String output,
    required Duration start,
    required Duration end,
    void Function(double progress)? onProgress,
  });

  Future<void> cancel();
}

class PlatformVideoTrimService implements VideoTrimService {
  static const _channel = MethodChannel('binnacle/video_trim');
  void Function(double)? _onProgress;

  PlatformVideoTrimService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') _onProgress?.call((call.arguments as num).toDouble());
    });
  }

  @override
  bool get isAvailable => Platform.isAndroid;

  @override
  Future<bool> trim({
    required String source,
    required String output,
    required Duration start,
    required Duration end,
    void Function(double progress)? onProgress,
  }) async {
    _onProgress = onProgress;
    try {
      final r = await _channel.invokeMethod<String>('trim', {
        'source': source,
        'output': output,
        'startUs': start.inMicroseconds,
        'endUs': end.inMicroseconds,
      });
      return r == 'ok';
    } on PlatformException catch (e) {
      throw TrimException(
        switch (e.code) {
          'insufficient_space' => TrimFailure.insufficientSpace,
          'missing_source' => TrimFailure.missingSource,
          'unsupported' => TrimFailure.unsupported,
          'busy' => TrimFailure.busy,
          _ => TrimFailure.unknown,
        },
        e.message ?? 'Export failed',
      );
    } finally {
      _onProgress = null;
    }
  }

  @override
  Future<void> cancel() async => _channel.invokeMethod('cancel');
}
