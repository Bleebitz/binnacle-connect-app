enum ClipKind { highlight, photo, fall }

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
  /// point here. Null for demo-seeded clips (there is no media server in
  /// demo mode) and for a Core clip whose media hasn't finished uploading
  /// yet; either way, null means "nothing to actually play," never a
  /// fabricated stand-in.
  final String? mediaUrl;

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
  });

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
        capturedAt: DateTime.tryParse(j['captured_at'] as String? ?? '') ?? DateTime.now(),
        mediaUrl: j['media_url'] as String?,
      );

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
      );
}
