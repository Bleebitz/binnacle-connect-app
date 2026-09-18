enum ClipKind { highlight, photo, fall }

/// Where phone-imported media stands relative to the (currently
/// nonexistent) cloud backend — see media_upload_service.dart. A Core-
/// sourced clip (from HttpMediaCatalogService) is never in any of the
/// non-`uploaded` states; those only apply to clips imported from this
/// phone via [ClipRepository.importPicked].
///
/// `queued`/`paused` back the offline upload queue (see
/// upload_queue_service.dart): `queued` means "waiting for a connection
/// that matches the user's Wi-Fi/cellular preference," `paused` means
/// "the user explicitly paused this one," and `uploading` means an
/// attempt is actually in flight right now.
enum UploadStatus { onPhoneOnly, queued, uploading, paused, uploaded, failed }

/// Non-destructive edit parameters produced by the highlight editor (see
/// highlight_editor_screen.dart). Stored as metadata on a *separate* Clip
/// (never mutates the source clip) and applied at playback time — trim by
/// seeking/stopping the real VideoPlayerController at these bounds, crop
/// by a real Transform/ClipRect sized to [aspect] at render time. This is
/// NOT a re-encoded standalone video file: doing that for real would mean
/// either a GPL-licensed FFmpeg build (a real commercial-licensing
/// problem for a closed-source app) or non-trivial native
/// MediaMuxer/AVAssetExportSession platform code, neither of which is in
/// this pass's scope. Stated here, not glossed over: the "edited copy" is
/// a real, distinct, genuinely trimmed/cropped-at-playback Clip, not yet a
/// standalone exported file you could upload or share independently of
/// this app.
enum CropAspect { original, portrait, landscape, square }

class EditDefinition {
  final String sourceClipId;
  final Duration trimStart;
  final Duration trimEnd;
  final CropAspect aspect;
  /// Offset of the crop window's center, as a fraction of the source
  /// frame in each axis, in [-0.5, 0.5] — lets the user recenter the crop
  /// rather than always cropping from the middle.
  final double cropOffsetX;
  final double cropOffsetY;
  final Duration coverFrameAt;

  const EditDefinition({
    required this.sourceClipId,
    required this.trimStart,
    required this.trimEnd,
    required this.aspect,
    this.cropOffsetX = 0,
    this.cropOffsetY = 0,
    required this.coverFrameAt,
  });

  Map<String, dynamic> toJson() => {
        'source_clip_id': sourceClipId,
        'trim_start_ms': trimStart.inMilliseconds,
        'trim_end_ms': trimEnd.inMilliseconds,
        'aspect': aspect.name,
        'crop_offset_x': cropOffsetX,
        'crop_offset_y': cropOffsetY,
        'cover_frame_at_ms': coverFrameAt.inMilliseconds,
      };

  static EditDefinition? tryFromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final sourceId = j['source_clip_id'];
    if (sourceId is! String) return null;
    return EditDefinition(
      sourceClipId: sourceId,
      trimStart: Duration(milliseconds: (j['trim_start_ms'] as num?)?.toInt() ?? 0),
      trimEnd: Duration(milliseconds: (j['trim_end_ms'] as num?)?.toInt() ?? 0),
      aspect: CropAspect.values.firstWhere((a) => a.name == j['aspect'], orElse: () => CropAspect.original),
      cropOffsetX: (j['crop_offset_x'] as num?)?.toDouble() ?? 0,
      cropOffsetY: (j['crop_offset_y'] as num?)?.toDouble() ?? 0,
      coverFrameAt: Duration(milliseconds: (j['cover_frame_at_ms'] as num?)?.toInt() ?? 0),
    );
  }
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
  /// point here. Null for demo-seeded clips (there is no media server in
  /// demo mode) and for a Core clip whose media hasn't finished uploading
  /// yet; either way, null means "nothing to actually play," never a
  /// fabricated stand-in.
  final String? mediaUrl;

  /// A real file path on this device — set only for media imported via
  /// [ClipRepository.importPicked] (see media_import_service.dart).
  /// Playable/persistable independent of [mediaUrl] or any backend.
  final String? localPath;
  final UploadStatus uploadStatus;

  /// 0.0-1.0 while [uploadStatus] is `uploading`; otherwise meaningless.
  final double? uploadProgress;

  /// Real, measured size of the file at [localPath] — captured once at
  /// import time (see media_import_service.dart's PickedMedia.sizeBytes),
  /// not estimated, so the upload queue can show a real byte count.
  final int? sizeBytes;

  /// User-entered caption set only when posted as a highlight (Community
  /// → Post a highlight) — see crew_screen.dart's postHighlight.
  final String? caption;

  /// Manually-assigned Crew session id, or null for "Unassigned" — see
  /// session organization in crew_screen.dart. Distinct from any future
  /// machine-identified grouping: this is only ever set by an explicit
  /// user action, never inferred.
  final String? sessionId;

  /// Non-null only for a Clip produced by the highlight editor — see
  /// [EditDefinition]'s doc comment for exactly what "edited" means here.
  final EditDefinition? editDefinition;

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
    this.sizeBytes,
    this.caption,
    this.sessionId,
    this.editDefinition,
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
    String? sessionId,
    bool clearSessionId = false,
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
        sizeBytes: sizeBytes,
        caption: caption ?? this.caption,
        sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
        editDefinition: editDefinition,
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
        'size_bytes': sizeBytes,
        'caption': caption,
        'session_id': sessionId,
        'edit_definition': editDefinition?.toJson(),
      };

  /// Restores a locally-persisted Library entry (see library_local_store.dart)
  /// — distinct from [Clip.fromJson], which parses a Core catalog response
  /// and never has a [localPath]. An upload that was mid-flight when the
  /// app last closed is restored as `queued` (with a real automatic retry
  /// once a matching connection is seen — see upload_queue_service.dart),
  /// never silently resumed as if still uploading — there is no persisted
  /// upload session to actually resume, and no interrupted-transfer resume
  /// capability exists on the (nonexistent) backend to resume against.
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
        sizeBytes: (j['size_bytes'] as num?)?.toInt(),
        uploadStatus: () {
          final raw = j['upload_status'] as String?;
          final status = UploadStatus.values.firstWhere((s) => s.name == raw, orElse: () => UploadStatus.onPhoneOnly);
          return (status == UploadStatus.uploading) ? UploadStatus.queued : status;
        }(),
        caption: j['caption'] as String?,
        sessionId: j['session_id'] as String?,
        editDefinition: EditDefinition.tryFromJson(j['edit_definition'] as Map<String, dynamic>?),
      );
}
