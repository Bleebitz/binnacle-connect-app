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
  });

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
      );
}
