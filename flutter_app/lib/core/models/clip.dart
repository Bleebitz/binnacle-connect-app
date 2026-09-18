enum ClipKind { highlight, photo, fall }

/// Where a clip's media actually comes from. Kept separate from [Clip.mediaUrl]
/// on purpose: `mediaUrl` is only ever a Core-hosted URL, and demo/local media
/// must never be dressed up as one.
enum ClipOrigin {
  /// Core/Vision media (the only origin a Core JSON payload can produce).
  core,

  /// A start/end reference into the bundled recorded demo asset. No video is
  /// copied; playback seeks to [MediaSegment.start] and stops at
  /// [MediaSegment.end].
  demoSegment,

  /// A file written to app-owned storage by a local Demo action (for example
  /// a frame extracted from the recorded demo feed).
  demoLocalCapture,
}

/// A slice of a bundled asset: the controlled source plus offsets.
class MediaSegment {
  final String assetPath;
  final Duration start;
  final Duration end;

  const MediaSegment({
    required this.assetPath,
    required this.start,
    required this.end,
  });

  Duration get length => end - start;

  Map<String, dynamic> toJson() => {
        'asset_path': assetPath,
        'start_ms': start.inMilliseconds,
        'end_ms': end.inMilliseconds,
      };

  static MediaSegment? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final asset = raw['asset_path'];
    final start = raw['start_ms'];
    final end = raw['end_ms'];
    if (asset is! String || start is! num || end is! num) return null;
    if (end <= start) return null;
    return MediaSegment(
      assetPath: asset,
      start: Duration(milliseconds: start.toInt()),
      end: Duration(milliseconds: end.toInt()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaSegment &&
      other.assetPath == assetPath &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(assetPath, start, end);
}

class Clip {
  final String id;
  final String title;
  final Duration duration;
  final String? thumbnailPath; // local cache path or network URL
  final ClipKind kind;
  final String riderId;
  final bool favorite;
  final bool signed; // signed on Vision at capture — see F-44, provenance only
  final bool gpsAttached;
  final DateTime capturedAt;

  /// The Core's real media URL for this clip — playback/download/share all
  /// point here. Null for demo/local clips (there is no media server in
  /// demo mode) and for a Core clip whose media hasn't finished uploading
  /// yet; either way, null means "nothing to actually play," never a
  /// fabricated stand-in.
  final String? mediaUrl;

  /// Provenance of the media. Defaults to [ClipOrigin.core] so existing Core
  /// JSON parsing is unchanged.
  final ClipOrigin origin;

  /// For [ClipOrigin.demoSegment]: the slice of the bundled demo asset to
  /// play. Null otherwise.
  final MediaSegment? segment;

  /// For [ClipOrigin.demoLocalCapture]: absolute path of the real image file
  /// in app-owned storage. Null otherwise.
  final String? localPath;

  const Clip({
    required this.id,
    required this.title,
    required this.duration,
    this.thumbnailPath,
    required this.kind,
    required this.riderId,
    this.favorite = false,
    this.signed = true,
    this.gpsAttached = true,
    required this.capturedAt,
    this.mediaUrl,
    this.origin = ClipOrigin.core,
    this.segment,
    this.localPath,
  });

  /// True for anything produced by the recorded Demo rather than Core/Vision.
  bool get isDemoOrigin => origin != ClipOrigin.core;

  /// Core JSON only. It never reads demo fields, so a Core payload can never
  /// produce demo-origin media.
  factory Clip.fromJson(Map<String, dynamic> j) => Clip(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Untitled clip',
        duration: Duration(seconds: (j['duration_s'] as num?)?.toInt() ?? 0),
        thumbnailPath: j['thumbnail_url'] as String?,
        kind: ClipKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => ClipKind.highlight,
        ),
        riderId: j['rider_id'] as String? ?? 'unknown',
        favorite: j['favorite'] as bool? ?? false,
        signed: j['signed'] as bool? ?? false,
        gpsAttached: j['gps_attached'] as bool? ?? false,
        capturedAt: DateTime.tryParse(j['captured_at'] as String? ?? '') ??
            DateTime.now(),
        mediaUrl: j['media_url'] as String?,
      );

  /// Local persistence format for Demo-origin clips only. Deliberately a
  /// separate format from the Core wire JSON.
  Map<String, dynamic> toLocalJson() => {
        'id': id,
        'title': title,
        'duration_ms': duration.inMilliseconds,
        'thumbnail_path': thumbnailPath,
        'kind': kind.name,
        'rider_id': riderId,
        'favorite': favorite,
        'captured_at': capturedAt.toIso8601String(),
        'origin': origin.name,
        'segment': segment?.toJson(),
        'local_path': localPath,
      };

  /// Returns null for anything that is not a well-formed Demo-origin record,
  /// so a corrupt or foreign entry is dropped instead of crashing or being
  /// shown as media.
  static Clip? tryFromLocalJson(Object? raw) {
    if (raw is! Map) return null;
    final originName = raw['origin'];
    final origin = ClipOrigin.values.where((o) => o.name == originName);
    if (origin.isEmpty || origin.first == ClipOrigin.core) return null;
    final id = raw['id'];
    final kindName = raw['kind'];
    final kind = ClipKind.values.where((k) => k.name == kindName);
    if (id is! String || kind.isEmpty) return null;
    final segment = MediaSegment.tryFromJson(raw['segment']);
    final localPath = raw['local_path'] as String?;
    if (origin.first == ClipOrigin.demoSegment && segment == null) return null;
    if (origin.first == ClipOrigin.demoLocalCapture && localPath == null) {
      return null;
    }
    return Clip(
      id: id,
      title: raw['title'] as String? ?? 'Demo clip',
      duration:
          Duration(milliseconds: (raw['duration_ms'] as num?)?.toInt() ?? 0),
      thumbnailPath: raw['thumbnail_path'] as String?,
      kind: kind.first,
      riderId: raw['rider_id'] as String? ?? 'levi',
      favorite: raw['favorite'] as bool? ?? false,
      signed: false,
      gpsAttached: false,
      capturedAt: DateTime.tryParse(raw['captured_at'] as String? ?? '') ??
          DateTime.now(),
      origin: origin.first,
      segment: segment,
      localPath: localPath,
    );
  }

  Clip copyWith({bool? favorite, String? riderId}) => Clip(
        id: id,
        title: title,
        duration: duration,
        thumbnailPath: thumbnailPath,
        kind: kind,
        riderId: riderId ?? this.riderId,
        favorite: favorite ?? this.favorite,
        signed: signed,
        gpsAttached: gpsAttached,
        capturedAt: capturedAt,
        mediaUrl: mediaUrl,
        origin: origin,
        segment: segment,
        localPath: localPath,
      );
}
