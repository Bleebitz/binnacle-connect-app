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

  DemoZoom() : super(min) {
    // Remember the last magnified level so a double-tap can toggle 1x <-> it.
    addListener(() {
      if (value > min) _lastMagnified = value;
    });
  }

  double _lastMagnified = 2.0;

  /// The most recent zoom above 1x (2.0x until the user has zoomed).
  double get lastMagnified => _lastMagnified;

  static double clamp(double zoom) => zoom.clamp(min, max).toDouble();

  bool get canZoomIn => value < max;
  bool get canZoomOut => value > min;

  void zoomIn() => value = clamp(value + step);
  void zoomOut() => value = clamp(value - step);
  void setZoom(double zoom) => value = clamp(zoom);
  void reset() => value = min;

  /// Double-tap behaviour: from a magnified level return to 1x; from 1x go back
  /// to the last magnified level (not a hard-coded 2x once the user has one).
  void toggleReset() => value = value > min ? min : clamp(_lastMagnified);
}

/// Landscape view modes. In Recorded Demo these only change which overlays the
/// UI shows; no ePTZ framing is performed by a recorded video.
enum DemoViewMode { raw, trackFollow, manual }

/// Rider Lock for the recorded Demo: the operator's local confirmation that the
/// boxed target is the intended rider. It is Demo presentation state only and
/// never an authoritative Track or Core lock. There is exactly one annotated
/// target in the controlled footage, so this is simply locked or not locked.
class DemoRiderLock extends ValueNotifier<String?> {
  DemoRiderLock() : super(null);

  bool get isLocked => value != null;

  bool isLockedOn(String targetId) => value == targetId;

  void lock(String targetId) => value = targetId;

  void clear() => value = null;
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

/// What a cleanup pass did. Only [failed] means Binnacle-owned bytes may still
/// be on disk; [refused] paths were never ours to delete.
class DemoCleanupResult {
  final List<String> deleted;
  final List<String> alreadyMissing;
  final List<String> refused;
  final List<String> failed;
  const DemoCleanupResult({
    this.deleted = const [],
    this.alreadyMissing = const [],
    this.refused = const [],
    this.failed = const [],
  });
}

/// The one place that knows which files Binnacle owns for Demo media (the
/// `demo_media` directory under the app documents directory) and the only code
/// allowed to delete them.
///
/// It refuses everything else: paths outside that directory, `..` traversal,
/// the directory itself, symlinks, sibling directories that merely share a
/// prefix, and non-files. Persisted metadata is untrusted input, so a corrupt
/// or malicious `localPath` can never turn into an arbitrary file delete. The
/// bundled recorded Demo asset is a Flutter asset key, not a file path, and is
/// therefore never deletable here.
///
/// Deleting the phone-Gallery copy of a Snapshot (a MediaStore row) is
/// deliberately out of scope; see docs/evidence/CONNECT_DEMO_CAMERA_ACCEPTANCE.md.
class DemoMediaStorage {
  final Future<Directory> Function() _directory;

  DemoMediaStorage({Future<Directory> Function()? directory})
      : _directory = directory ?? defaultDirectory;

  static Future<Directory> defaultDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/demo_media').create(recursive: true);
  }

  static String _canonical(String path, {required bool isDirectory}) {
    var p = File(path).absolute.path;
    try {
      final type = FileSystemEntity.typeSync(p, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        p = isDirectory
            ? Directory(p).resolveSymbolicLinksSync()
            : File(p).parent.resolveSymbolicLinksSync() +
                Platform.pathSeparator +
                p.split(RegExp(r'[\\/]')).last;
      }
    } catch (_) {
      // Fall through to the lexically normalized form.
    }
    return Uri.file(p, windows: Platform.isWindows)
        .normalizePath()
        .toFilePath(windows: Platform.isWindows);
  }

  /// True only for a regular file strictly inside the owned directory.
  Future<bool> isOwned(String? path) async {
    if (path == null || path.trim().isEmpty) return false;
    final dir = await _directory();
    final root = _canonical(dir.path, isDirectory: true);
    final rootWithSep =
        root.endsWith(Platform.pathSeparator) ? root : root + Platform.pathSeparator;
    final candidate = _canonical(path, isDirectory: false);
    return candidate.length > rootWithSep.length &&
        candidate.startsWith(rootWithSep);
  }

  /// Deletes the owned files among [paths] (deduplicated: a Snapshot's
  /// `localPath` and `thumbnailPath` are usually the same JPEG). Never throws;
  /// the outcome is reported per path.
  Future<DemoCleanupResult> deleteOwned(Iterable<String?> paths) async {
    final unique = <String>{
      for (final p in paths)
        if (p != null && p.trim().isNotEmpty) p,
    };
    final deleted = <String>[];
    final missing = <String>[];
    final refused = <String>[];
    final failed = <String>[];
    for (final path in unique) {
      try {
        if (!await isOwned(path)) {
          refused.add(path);
          continue;
        }
        final type = FileSystemEntity.typeSync(path, followLinks: false);
        if (type == FileSystemEntityType.notFound) {
          missing.add(path);
        } else if (type != FileSystemEntityType.file) {
          refused.add(path); // a directory or a symlink is never ours to remove
        } else {
          File(path).deleteSync();
          deleted.add(path);
        }
      } catch (_) {
        failed.add(path);
      }
    }
    return DemoCleanupResult(
        deleted: deleted, alreadyMissing: missing, refused: refused, failed: failed);
  }
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
