enum ClipKind { highlight, photo, fall }

/// Where phone-imported media stands relative to the (currently
/// nonexistent) cloud backend — see media_upload_service.dart. A Core-
/// sourced clip (from HttpMediaCatalogService) is never in any of the
/// non-`uploaded` states; those only apply to clips imported from this
/// phone via [ClipRepository.importFromPhone].
enum UploadStatus { onPhoneOnly, uploading, uploaded, failed }

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

  /// A real file path on this device — set only for media imported via
  /// [ClipRepository.importFromPhone] (see media_import_service.dart).
  /// Playable/persistable independent of [mediaUrl] or any backend.
  final String? localPath;
  final UploadStatus uploadStatus;

  /// 0.0-1.0 while [uploadStatus] is `uploading`; otherwise meaningless.
  final double? uploadProgress;

  /// User-entered caption set only when posted as a highlight (Community
  /// → Post a highlight) — see crew_screen.dart's postHighlight.
  final String? caption;

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
    this.localPath,
    this.uploadStatus = UploadStatus.uploaded,
    this.uploadProgress,
    this.caption,
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

  Clip copyWith({
    bool? favorite,
    String? riderId,
    UploadStatus? uploadStatus,
    double? uploadProgress,
    String? caption,
  }) =>
      Clip(
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
        localPath: localPath,
        uploadStatus: uploadStatus ?? this.uploadStatus,
        uploadProgress: uploadProgress ?? this.uploadProgress,
        caption: caption ?? this.caption,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'duration_s': duration.inSeconds,
        'thumbnail_url': thumbnailPath,
        'kind': kind.name,
        'rider_id': riderId,
        'favorite': favorite,
        'signed': signed,
        'gps_attached': gpsAttached,
        'captured_at': capturedAt.toIso8601String(),
        'media_url': mediaUrl,
        'local_path': localPath,
        'upload_status': uploadStatus.name,
        'caption': caption,
      };

  /// Restores a locally-persisted Library entry (see library_local_store.dart)
  /// — distinct from [Clip.fromJson], which parses a Core catalog response
  /// and never has a [localPath]. An upload that was mid-flight when the
  /// app last closed is restored as `failed` (with a real "Retry" action),
  /// never silently resumed as if still uploading — there is no persisted
  /// upload session to actually resume.
  factory Clip.fromLocalJson(Map<String, dynamic> j) => Clip(
        id: j['id'] as String,
        title: j['title'] as String,
        duration: Duration(seconds: (j['duration_s'] as num?)?.toInt() ?? 0),
        thumbnailPath: j['thumbnail_url'] as String?,
        kind: ClipKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => ClipKind.highlight),
        riderId: j['rider_id'] as String? ?? 'unknown',
        favorite: j['favorite'] as bool? ?? false,
        signed: j['signed'] as bool? ?? false,
        gpsAttached: j['gps_attached'] as bool? ?? false,
        capturedAt: DateTime.tryParse(j['captured_at'] as String? ?? '') ?? DateTime.now(),
        mediaUrl: j['media_url'] as String?,
        localPath: j['local_path'] as String?,
        uploadStatus: () {
          final raw = j['upload_status'] as String?;
          final status = UploadStatus.values.firstWhere((s) => s.name == raw, orElse: () => UploadStatus.onPhoneOnly);
          return status == UploadStatus.uploading ? UploadStatus.failed : status;
        }(),
        caption: j['caption'] as String?,
      );
}
