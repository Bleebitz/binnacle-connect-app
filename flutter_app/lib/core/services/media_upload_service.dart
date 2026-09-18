// Cloud upload boundary for phone-imported media. UNLIKE
// media_catalog_service.dart or connect_startup's pairing transport,
// there is no documented endpoint contract to even attempt here yet:
// BIN-41 (upload policy) and BIN-48 (S3/CloudFront/MediaConvert storage
// architecture) are both still Todo, and the provider/shape isn't
// decided. Guessing an endpoint and "trying" it would produce a
// misleading timeout that looks like an infra problem rather than what
// it actually is — a feature that hasn't been built. So this reports
// unavailable honestly rather than attempting a fabricated call.
//
// This IS the real extension point: once BIN-41/48 land on a concrete
// contract, a new implementation of this interface replaces
// NoOpMediaUploadService, and the rest of the app (ClipRepository, the
// Library UI's upload-status chips/progress/retry) needs no changes —
// they already drive off this interface, not a concrete transport.

import 'dart:async';

enum UploadOutcome { uploaded, failed, unavailable, cancelled }

class UploadProgressUpdate {
  final double? fraction; // 0.0-1.0, null while indeterminate
  final UploadOutcome? outcome; // non-null only on the terminal event
  final String? message;
  const UploadProgressUpdate({this.fraction, this.outcome, this.message});
}

abstract class MediaUploadService {
  /// Emits progress updates, ending with exactly one terminal event whose
  /// `outcome` is non-null. Cancelling the returned subscription must stop
  /// any real network activity — callers use this for the retry/cancel UI.
  Stream<UploadProgressUpdate> upload({required String localPath, required String mediaId});

  /// Whether this implementation can ever succeed — the Library UI uses
  /// this to decide whether to even offer "Upload" vs. showing "Cloud
  /// upload unavailable" up front.
  bool get isAvailable;
}

/// The only implementation shipped today. No Core/cloud endpoint for
/// media upload has an approved, documented contract yet (BIN-41/BIN-48
/// are both Todo) — this always and immediately reports `unavailable`,
/// never a fabricated progress bar or a fake success.
class NoOpMediaUploadService implements MediaUploadService {
  @override
  bool get isAvailable => false;

  @override
  Stream<UploadProgressUpdate> upload({required String localPath, required String mediaId}) {
    return Stream.value(const UploadProgressUpdate(
      outcome: UploadOutcome.unavailable,
      message: 'Cloud upload isn\'t available yet — this media stays on this phone only.',
    ));
  }
}
