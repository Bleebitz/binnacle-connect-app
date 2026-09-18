// Local Demo media actions for the recorded camera feed: digital zoom,
// Snapshot, and Save Highlight.
//
// SAFETY BOUNDARY. Everything in this file is a LOCAL simulation over the
// bundled recorded demo asset. Nothing here talks to a Core or Vision unit,
// nothing here claims a Core acknowledgement, and the media it produces is
// tagged with a Demo origin (see ClipOrigin). Core Mode never touches this
// file: it keeps its own `snapshot`, `save_highlight` and `nudge_zoom`
// commands, confirmed by the Core.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/clip.dart';

/// Local digital zoom for the recorded demo feed. It only changes how the
/// recorded video is presented; it never sends `nudge_zoom` to anything.
///
/// The maximum is 4.0x rather than the product's 6.0x: the recorded source is
/// 1920x1080, and beyond 4x a digital crop of it stops looking like footage.
class DemoZoom extends ValueNotifier<double> {
  static const double min = 1.0;
  static const double max = 4.0;
  static const double step = 0.5;

  DemoZoom() : super(min);

  static double clamp(double zoom) => zoom.clamp(min, max).toDouble();

  bool get canZoomIn => value < max;
  bool get canZoomOut => value > min;

  void zoomIn() => value = clamp(value + step);
  void zoomOut() => value = clamp(value - step);
  void setZoom(double zoom) => value = clamp(zoom);
  void reset() => value = min;
}

/// The window of the recorded source a Save Highlight covers, anchored on the
/// playhead and clamped to the source.
@immutable
class HighlightWindow {
  final Duration start;
  final Duration end;

  const HighlightWindow(this.start, this.end);

  Duration get length => end - start;

  /// [preRoll] before and [postRoll] after [position], clamped to
  /// `[0, sourceDuration]`. A window shorter than [minLength] (for example
  /// pressed on the very last frame) is widened toward the source rather than
  /// producing a zero-length clip.
  factory HighlightWindow.compute({
    required Duration position,
    required Duration preRoll,
    required Duration postRoll,
    required Duration sourceDuration,
    Duration minLength = const Duration(seconds: 1),
  }) {
    final total = sourceDuration.isNegative ? Duration.zero : sourceDuration;
    final at = position < Duration.zero
        ? Duration.zero
        : (position > total ? total : position);
    var start = at - preRoll;
    var end = at + postRoll;
    if (start < Duration.zero) start = Duration.zero;
    if (end > total) end = total;
    if (end - start < minLength) {
      final want = minLength > total ? total : minLength;
      start = end - want;
      if (start < Duration.zero) {
        start = Duration.zero;
        end = start + want;
      }
    }
    return HighlightWindow(start, end);
  }

  @override
  bool operator ==(Object other) =>
      other is HighlightWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// "m:ss" for titles and labels.
String formatDemoTime(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

class FrameExtractionException implements Exception {
  final String message;
  FrameExtractionException(this.message);
  @override
  String toString() => message;
}

class ExtractedFrame {
  final String path;
  final int width;
  final int height;
  const ExtractedFrame(
      {required this.path, required this.width, required this.height});
}

/// Pulls a real frame out of the bundled recorded asset.
abstract class FrameExtractor {
  /// Decodes the frame at [position] of [assetPath] and writes it as a JPEG to
  /// [outputPath]. Throws [FrameExtractionException] on any failure.
  Future<ExtractedFrame> extractFrame({
    required String assetPath,
    required Duration position,
    required String outputPath,
  });

  /// Publishes [path] to the phone's gallery through Android scoped storage
  /// (MediaStore), which needs no storage permission. Returns the content URI,
  /// or null where that is not available.
  Future<String?> exportToGallery(
      {required String path, required String displayName});
}

/// Android implementation: `MediaMetadataRetriever` on the bundled asset and
/// a MediaStore insert (see MainActivity.kt). No FFmpeg and no broad-storage
/// permission.
class PlatformFrameExtractor implements FrameExtractor {
  static const _channel = MethodChannel('binnacle/demo_media');

  @override
  Future<ExtractedFrame> extractFrame({
    required String assetPath,
    required Duration position,
    required String outputPath,
  }) async {
    try {
      final r =
          await _channel.invokeMapMethod<String, Object?>('extractFrame', {
        'assetPath': assetPath,
        'positionMs': position.inMilliseconds,
        'outputPath': outputPath,
      });
      if (r == null)
        throw FrameExtractionException('No result from the frame extractor');
      return ExtractedFrame(
        path: outputPath,
        width: (r['width'] as num?)?.toInt() ?? 0,
        height: (r['height'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException catch (e) {
      throw FrameExtractionException(
          e.message ?? 'Frame extraction failed (${e.code})');
    } on MissingPluginException {
      throw FrameExtractionException(
          'Frame extraction is not available on this platform');
    }
  }

  @override
  Future<String?> exportToGallery(
      {required String path, required String displayName}) async {
    try {
      return await _channel.invokeMethod<String>('exportImage', {
        'path': path,
        'displayName': displayName,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

class DemoSnapshotResult {
  final Clip clip;

  /// MediaStore URI when the image was also published to the phone's gallery.
  final String? galleryUri;
  const DemoSnapshotResult(this.clip, this.galleryUri);
}

/// Builds real Demo media from the recorded feed. It only produces [Clip]s;
/// adding them to the Library is the caller's job.
class DemoMediaCapture {
  final FrameExtractor extractor;
  final Future<Directory> Function() _mediaDirectory;
  final DateTime Function() _now;

  DemoMediaCapture({
    required this.extractor,
    Future<Directory> Function()? mediaDirectory,
    DateTime Function()? now,
  })  : _mediaDirectory = mediaDirectory ?? _defaultMediaDirectory,
        _now = now ?? DateTime.now;

  static Future<Directory> _defaultMediaDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/demo_media').create(recursive: true);
  }

  /// A real image of the recorded source at [position].
  Future<DemoSnapshotResult> snapshot({
    required String assetPath,
    required Duration position,
    String riderId = 'levi',
  }) async {
    final now = _now();
    final stamp = now.microsecondsSinceEpoch;
    final dir = await _mediaDirectory();
    final path = '${dir.path}/snapshot_$stamp.jpg';
    final frame = await extractor.extractFrame(
      assetPath: assetPath,
      position: position,
      outputPath: path,
    );
    final file = File(frame.path);
    if (!file.existsSync() || file.lengthSync() == 0) {
      // Never report a save that did not produce a usable image.
      if (file.existsSync()) file.deleteSync();
      throw FrameExtractionException(
          'The frame was extracted but the image file is empty');
    }
    final galleryUri = await extractor.exportToGallery(
      path: frame.path,
      displayName: 'Binnacle_Demo_$stamp.jpg',
    );
    return DemoSnapshotResult(
      Clip(
        id: 'demo-snap-$stamp',
        title: 'Snapshot — ${formatDemoTime(position)}',
        duration: Duration.zero,
        thumbnailPath: frame.path,
        kind: ClipKind.photo,
        riderId: riderId,
        signed: false,
        gpsAttached: false,
        capturedAt: now,
        origin: ClipOrigin.demoLocalCapture,
        localPath: frame.path,
      ),
      galleryUri,
    );
  }

  /// A highlight that is only a reference into the bundled source: no video is
  /// copied. The thumbnail is a real frame from the capture point and is
  /// best-effort; the highlight is valid without it.
  Future<Clip> highlight({
    required String assetPath,
    required Duration position,
    required Duration sourceDuration,
    required Duration preRoll,
    required Duration postRoll,
    String riderId = 'levi',
  }) async {
    final window = HighlightWindow.compute(
      position: position,
      preRoll: preRoll,
      postRoll: postRoll,
      sourceDuration: sourceDuration,
    );
    if (window.length <= Duration.zero) {
      throw FrameExtractionException(
          'There is no footage to save at this point');
    }
    final now = _now();
    final stamp = now.microsecondsSinceEpoch;
    String? thumb;
    try {
      final dir = await _mediaDirectory();
      final frame = await extractor.extractFrame(
        assetPath: assetPath,
        position: position,
        outputPath: '${dir.path}/highlight_${stamp}_thumb.jpg',
      );
      final f = File(frame.path);
      if (f.existsSync() && f.lengthSync() > 0) thumb = frame.path;
    } on FrameExtractionException {
      thumb = null;
    }
    return Clip(
      id: 'demo-hl-$stamp',
      title:
          'Highlight — ${formatDemoTime(window.start)}–${formatDemoTime(window.end)}',
      duration: window.length,
      thumbnailPath: thumb,
      kind: ClipKind.highlight,
      riderId: riderId,
      signed: false,
      gpsAttached: false,
      capturedAt: now,
      origin: ClipOrigin.demoSegment,
      segment: MediaSegment(
          assetPath: assetPath, start: window.start, end: window.end),
    );
  }
}

/// Persists Demo-origin clips (metadata only; images are files in app storage
/// and highlights are references into the bundled asset).
abstract class DemoLibraryStore {
  Future<List<Clip>> load();
  Future<void> save(List<Clip> clips);
}

class SharedPrefsDemoLibraryStore implements DemoLibraryStore {
  static const _key = 'demo_library_v1';

  @override
  Future<List<Clip>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (Clip.tryFromLocalJson(item) case final clip?) clip,
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<Clip> clips) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode([for (final c in clips) c.toLocalJson()]));
  }
}
