import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../core/app_config.dart';
import '../../core/models/clip.dart';
import '../../core/services/connectivity_checker.dart';
import '../../core/services/library_local_store.dart';
import '../../core/services/media_catalog_service.dart';
import '../../core/services/media_import_service.dart';
import '../../core/services/media_upload_service.dart';
import '../../core/services/pairing_service.dart';
import '../../core/services/upload_preferences_service.dart';
import '../theme/binnacle_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_sheet.dart';
import '../widgets/media_import_sheet.dart';
import 'highlight_editor_screen.dart';

/// Clip store. Demo mode is a local, in-memory scaffold ([seedDemo]/
/// [addFromCapture]). Core mode is backed by a real fetch against the
/// Core's clip catalog ([loadFromCore]) — see media_catalog_service.dart
/// for the (unverified, no live Core exists yet) endpoint contract.
/// [importPicked] (real phone media import) works in both modes — it's
/// the user's own local file, independent of demo/Core.
class ClipRepository extends ChangeNotifier {
  final List<Clip> _clips = [];
  final LibraryLocalStore _localStore;
  final MediaUploadService _uploader;
  final UploadPreferencesService _uploadPrefs;
  final ConnectivityChecker _connectivity;
  final Map<String, StreamSubscription<UploadProgressUpdate>> _uploads = {};
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  UploadNetworkPreference _networkPreference = UploadNetworkPreference.wifiOnly;
  UploadNetworkPreference get uploadNetworkPreference => _networkPreference;

  /// Real, current-at-last-check connectivity — surfaced so the queue UI
  /// can show "waiting for Wi-Fi" vs. "waiting for any connection" rather
  /// than an unexplained "queued."
  List<ConnectivityResult> _lastConnectivity = const [ConnectivityResult.none];
  List<ConnectivityResult> get lastConnectivity => _lastConnectivity;

  ClipRepository({
    LibraryLocalStore? localStore,
    MediaUploadService? uploader,
    UploadPreferencesService? uploadPreferences,
    ConnectivityChecker? connectivity,
  })  : _localStore = localStore ?? SharedPreferencesLibraryLocalStore(),
        _uploader = uploader ?? NoOpMediaUploadService(),
        _uploadPrefs = uploadPreferences ?? UploadPreferencesService(),
        _connectivity = connectivity ?? RealConnectivityChecker();

  List<Clip> get clips => List.unmodifiable(_clips);

  bool loading = false;
  String? loadError;

  /// True while a pick/import is in flight — the "Add media" UI disables
  /// itself on this, so a duplicate tap during a slow picker/copy can't
  /// start a second concurrent import. Set via [setImporting] rather than
  /// directly so every call site (Library, Best Falls, Community) shares
  /// one real guard instead of each screen inventing its own boolean.
  bool importing = false;

  void setImporting(bool value) {
    if (importing == value) return;
    importing = value;
    notifyListeners();
  }

  /// Restores phone-imported entries persisted from a prior session — see
  /// library_local_store.dart. Call once at startup (main.dart), before
  /// any demo seed/Core fetch, so imported media shows up immediately
  /// rather than only after the next add.
  Future<void> hydrate() async {
    final restored = await _localStore.loadImported();
    if (restored.isNotEmpty) {
      _clips.insertAll(0, restored);
      notifyListeners();
    }
    _networkPreference = await _uploadPrefs.load();
    // Real, current-at-startup connectivity, then a live subscription — an
    // item left `queued` from a prior session (e.g. the app was closed
    // mid-queue) is picked up as soon as a matching connection is seen,
    // without the user needing to open the app on Wi-Fi and re-trigger
    // anything by hand.
    _lastConnectivity = await _connectivity.check();
    _connectivitySub = _connectivity.onChanged.listen(_onConnectivityChanged);
    _processQueue();
  }

  Future<void> setUploadNetworkPreference(UploadNetworkPreference preference) async {
    _networkPreference = preference;
    await _uploadPrefs.save(preference);
    notifyListeners();
    _processQueue();
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    _lastConnectivity = results;
    notifyListeners(); // queue UI's "waiting for..." text depends on this
    _processQueue();
  }

  bool get _connectivitySatisfiesPreference {
    final hasWifi = _lastConnectivity.contains(ConnectivityResult.wifi) ||
        _lastConnectivity.contains(ConnectivityResult.ethernet);
    final hasCellular = _lastConnectivity.contains(ConnectivityResult.mobile);
    return _networkPreference == UploadNetworkPreference.wifiOnly ? hasWifi : (hasWifi || hasCellular);
  }

  /// Starts a real attempt for every `queued` clip, if the current
  /// connection matches the user's Wi-Fi/cellular preference. Called on
  /// every connectivity change, on preference change, and once at
  /// startup — this IS the offline queue: items just sit in `queued`
  /// until this finds a satisfying connection, including across an app
  /// restart (queued state is persisted).
  void _processQueue() {
    if (!_uploader.isAvailable || !_connectivitySatisfiesPreference) return;
    for (final clip in List<Clip>.from(_clips)) {
      if (clip.uploadStatus == UploadStatus.queued) _beginUploadAttempt(clip.id);
    }
  }

  Future<void> _persistImported() async {
    await _localStore.saveImported(_clips.where((c) => c.localPath != null).toList());
  }

  /// Real pick -> preview is handled by the caller (UI) via [importer]
  /// directly, since cancelling a preview must never touch the Library at
  /// all. This is called only once the user has confirmed. Copies the
  /// picked file into durable app storage, adds a real Clip, and enters it
  /// into the offline upload queue — `queued` if upload is available at
  /// all, `onPhoneOnly` if not (so the UI doesn't show a queue state that
  /// can never resolve). Entering the queue rather than uploading
  /// immediately is what makes "select while offline, upload when
  /// connectivity returns" work: [_processQueue] picks it up the moment a
  /// satisfying connection is seen, which may be immediately if one
  /// already exists. Throws [MediaImportException] on a real copy
  /// failure; never adds a broken/partial entry on failure.
  Future<Clip> importPicked(
    PickedMedia media, {
    required MediaImportService importer,
    String? riderId,
    ClipKind? kindOverride,
    String? titleOverride,
  }) async {
    final localPath = await importer.copyIntoAppStorage(media);
    final clip = Clip(
      id: 'phone-${DateTime.now().microsecondsSinceEpoch}',
      title: titleOverride ??
          (media.kind == ImportMediaKind.photo ? 'Photo from phone' : 'Video from phone'),
      duration: Duration.zero,
      kind: kindOverride ?? (media.kind == ImportMediaKind.photo ? ClipKind.photo : ClipKind.highlight),
      riderId: riderId ?? 'me',
      capturedAt: DateTime.now(),
      localPath: localPath,
      sizeBytes: media.sizeBytes,
      uploadStatus: _uploader.isAvailable ? UploadStatus.queued : UploadStatus.onPhoneOnly,
      signed: false,
      gpsAttached: false,
    );
    add(clip);
    await _persistImported();
    _processQueue();
    return clip;
  }

  /// The real attempt-runner: checks for a missing source file itself
  /// (a real `File.exists()` check — this is the one failure mode this
  /// repository detects locally, before ever asking [_uploader]), then
  /// starts the upload and applies progress/outcome updates as they
  /// arrive. Cancelling via [cancelUpload]/[pauseUpload] stops the
  /// underlying stream — a real unsubscribe, not just a UI-side flag — so
  /// no further progress/result is applied after cancellation. Never
  /// marks a clip `uploaded` except on a real [UploadOutcome.uploaded]
  /// from the service — that's the server-confirmation requirement, not
  /// "we sent some bytes."
  void _beginUploadAttempt(String clipId) {
    _uploads[clipId]?.cancel();
    final i = _clips.indexWhere((c) => c.id == clipId);
    if (i == -1) return;
    final localPath = _clips[i].localPath;
    if (localPath == null) return;
    if (!File(localPath).existsSync()) {
      _clips[i] = _clips[i].copyWith(uploadStatus: UploadStatus.failed, uploadProgress: null);
      _lastFailureReason[clipId] = UploadFailureReason.missingSourceFile;
      _lastFailureMessage[clipId] = 'The original file is no longer on this phone.';
      notifyListeners();
      unawaited(_persistImported());
      return;
    }
    _clips[i] = _clips[i].copyWith(uploadStatus: UploadStatus.uploading, uploadProgress: 0);
    _lastFailureReason.remove(clipId);
    _lastFailureMessage.remove(clipId);
    notifyListeners();
    _uploads[clipId] = _uploader.upload(localPath: localPath, mediaId: clipId).listen((update) {
      final idx = _clips.indexWhere((c) => c.id == clipId);
      if (idx == -1) return;
      if (update.outcome == null) {
        _clips[idx] = _clips[idx].copyWith(uploadProgress: update.fraction);
      } else {
        // Duplicate-post guard: once real server confirmation has marked
        // this clip `uploaded`, nothing re-enters the queue for it (see
        // enqueueUpload/retryUpload's early-return below) — a retry after
        // this point would need a genuinely new outcome to change status.
        _clips[idx] = _clips[idx].copyWith(
          uploadStatus: switch (update.outcome!) {
            UploadOutcome.uploaded => UploadStatus.uploaded,
            UploadOutcome.failed || UploadOutcome.unavailable || UploadOutcome.cancelled =>
              UploadStatus.failed,
          },
          uploadProgress: null,
        );
        if (update.outcome != UploadOutcome.uploaded) {
          _lastFailureReason[clipId] = update.failureReason ?? UploadFailureReason.unknown;
          _lastFailureMessage[clipId] = update.message;
        } else {
          _lastFailureReason.remove(clipId);
          _lastFailureMessage.remove(clipId);
        }
        _uploads.remove(clipId);
        unawaited(_persistImported());
      }
      notifyListeners();
    });
  }

  /// Why the given clip's upload last failed — null if it never has, or
  /// if it's since succeeded/been re-queued. Real, structured detail
  /// (see [UploadFailureReason]) rather than only a free-text message.
  final Map<String, UploadFailureReason> _lastFailureReason = {};
  final Map<String, String?> _lastFailureMessage = {};
  UploadFailureReason? failureReasonFor(String clipId) => _lastFailureReason[clipId];
  String? failureMessageFor(String clipId) => _lastFailureMessage[clipId];

  /// Real, immediate attempt-or-queue for a clip already in [UploadStatus.onPhoneOnly]
  /// or [UploadStatus.failed] — e.g. the user turned cloud upload on later,
  /// or is manually retrying. A no-op if already queued/uploading/uploaded
  /// (duplicate-enqueue guard) — this is what "prevent duplicate uploads"
  /// means at the repository level, not just a disabled button.
  void enqueueUpload(String clipId) {
    final i = _clips.indexWhere((c) => c.id == clipId);
    if (i == -1) return;
    final status = _clips[i].uploadStatus;
    if (status == UploadStatus.queued || status == UploadStatus.uploading || status == UploadStatus.uploaded) {
      return;
    }
    _clips[i] = _clips[i].copyWith(uploadStatus: UploadStatus.queued, uploadProgress: null);
    notifyListeners();
    unawaited(_persistImported());
    _processQueue();
  }

  /// User-requested retry — same real re-entry into the queue as
  /// [enqueueUpload], named for what the Retry button in the UI means.
  void retryUpload(String clipId) => enqueueUpload(clipId);

  /// User-requested resume for a [UploadStatus.paused] clip — re-enters
  /// the queue exactly like [enqueueUpload]; [_processQueue] starts it
  /// immediately if the connection already satisfies the preference.
  void resumeUpload(String clipId) => enqueueUpload(clipId);

  /// Pauses a real in-flight or queued upload — a genuine unsubscribe
  /// from the upload stream (any real network activity stops), not a
  /// UI-only flag; distinct from [cancelUpload], which the UI reserves
  /// for "give up," since a paused item stays ready to [resumeUpload].
  void pauseUpload(String clipId) {
    _uploads.remove(clipId)?.cancel();
    final i = _clips.indexWhere((c) => c.id == clipId);
    if (i == -1) return;
    if (_clips[i].uploadStatus != UploadStatus.uploading && _clips[i].uploadStatus != UploadStatus.queued) return;
    _clips[i] = _clips[i].copyWith(uploadStatus: UploadStatus.paused, uploadProgress: null);
    notifyListeners();
    unawaited(_persistImported());
  }

  void cancelUpload(String clipId) {
    _uploads.remove(clipId)?.cancel();
    final i = _clips.indexWhere((c) => c.id == clipId);
    if (i == -1) return;
    // Cancelling the upload never touches the original file (localPath) —
    // it only stops the upload attempt. The clip stays in the Library as
    // on-phone-only media.
    _clips[i] = _clips[i].copyWith(uploadStatus: UploadStatus.onPhoneOnly, uploadProgress: null);
    _lastFailureReason.remove(clipId);
    _lastFailureMessage.remove(clipId);
    notifyListeners();
    unawaited(_persistImported());
  }

  @override
  void dispose() {
    for (final sub in _uploads.values) {
      sub.cancel();
    }
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// True once a real load has been attempted (success or failure) — the
  /// idempotency guard for the trigger in main.dart, so a legitimately
  /// empty catalog doesn't get re-fetched forever. [retryLoadFromCore]
  /// clears it for an explicit retry.
  bool attemptedLoad = false;

  /// Fetches the real clip catalog from the Core. Replaces the whole list
  /// rather than merging — the Core is the state authority for what clips
  /// exist, same principle ControlChannelService applies to vessel state.
  ///
  /// Demo/core safety lives in which [MediaCatalogService] the caller
  /// passes (NoOpMediaCatalogService vs HttpMediaCatalogService), the same
  /// pattern PairingService uses for its transport/key-material — not an
  /// internal mode check here, so this stays testable without a
  /// compile-time dart-define.
  Future<void> loadFromCore(MediaCatalogService service, String deviceId,
      {required String bearerToken}) async {
    loading = true;
    loadError = null;
    notifyListeners();
    final result = await service.fetchClips(deviceId, bearerToken: bearerToken);
    loading = false;
    attemptedLoad = true;
    if (result.outcome == CatalogOutcome.success) {
      _clips
        ..clear()
        ..addAll(result.clips);
    } else {
      loadError = result.message ?? result.outcome.name;
    }
    notifyListeners();
  }

  void retryLoadFromCore(MediaCatalogService service, String deviceId,
          {required String bearerToken}) =>
      Future(() {
        attemptedLoad = false;
        loadFromCore(service, deviceId, bearerToken: bearerToken);
      });

  void add(Clip c) {
    _clips.insert(0, c);
    notifyListeners();
  }

  /// Adds a Clip produced by the highlight editor (see
  /// highlight_editor_screen.dart) — persisted like any other
  /// phone-local clip since it has a real [Clip.localPath].
  void addEditedClip(Clip c) {
    add(c);
    unawaited(_persistImported());
  }

  /// Deletes only the local file + local-library entry for a
  /// phone-imported clip — see storage_screen.dart. Distinct from any
  /// future "delete from cloud" action: this never touches a remote
  /// object (there is no cloud backend to touch), and never runs on a
  /// Core/demo-seeded clip (no localPath, nothing local to remove).
  void deleteLocalCopy(String clipId) {
    final i = _clips.indexWhere((c) => c.id == clipId);
    if (i == -1) return;
    final path = _clips[i].localPath;
    if (path == null) return; // nothing local to delete
    _uploads.remove(clipId)?.cancel();
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    _clips.removeAt(i);
    _lastFailureReason.remove(clipId);
    _lastFailureMessage.remove(clipId);
    notifyListeners();
    unawaited(_persistImported());
  }

  void toggleFavorite(String id) {
    final i = _clips.indexWhere((c) => c.id == id);
    if (i == -1) return;
    _clips[i] = _clips[i].copyWith(favorite: !_clips[i].favorite);
    notifyListeners();
  }

  void assignRider(String clipId, String riderId) {
    final i = _clips.indexWhere((c) => c.id == clipId);
    if (i == -1) return;
    _clips[i] = _clips[i].copyWith(riderId: riderId);
    notifyListeners();
  }

  /// Set when Community's Post a highlight flow publishes this clip —
  /// see post_highlight_sheet.dart and crew_screen.dart's postHighlight.
  void setCaption(String clipId, String caption) {
    final i = _clips.indexWhere((c) => c.id == clipId);
    if (i == -1) return;
    _clips[i] = _clips[i].copyWith(caption: caption);
    if (_clips[i].localPath != null) unawaited(_persistImported());
    notifyListeners();
  }

  int _seq = 0;

  /// Demo-only seed data so the Library has something to show without
  /// requiring a live capture first — nothing in the real capture flow
  /// populates this repository yet (Capture screen's snapshot/highlight
  /// buttons only send commands over the control channel; wiring the two
  /// together is real Core/Vision work, not a UI concern). See
  /// [addFromCapture] for the demo-only bridge that makes the button presses
  /// visible here in the meantime.
  void seedDemo() {
    if (!AppConfig.isDemo) throw StateError('Demo media is unavailable in Core mode');
    if (_clips.isNotEmpty) return;
    final now = DateTime.now();
    _clips.addAll([
      Clip(
        id: 'seed-${_seq++}',
        title: 'Backside 180 into flats',
        duration: const Duration(seconds: 14),
        kind: ClipKind.highlight,
        riderId: 'levi',
        favorite: true,
        capturedAt: now.subtract(const Duration(minutes: 9)),
        // Real GoPro development footage (VER-01), bundled as a Flutter
        // asset — genuinely playable in demo mode, not a dead URL. Still
        // demo data: this is not Core-backed media (see Clip.mediaUrl's
        // doc comment) and mediaUrl for a real clip only ever comes from
        // HttpMediaCatalogService's real Core fetch.
        mediaUrl: 'assets/demo/gopro_dev_footage.mp4',
      ),
      Clip(
        id: 'seed-${_seq++}',
        title: 'Morning glass, first pass',
        duration: const Duration(seconds: 22),
        kind: ClipKind.highlight,
        riderId: 'levi',
        capturedAt: now.subtract(const Duration(minutes: 26)),
      ),
      Clip(
        id: 'seed-${_seq++}',
        title: 'Snapshot — wide shot',
        duration: Duration.zero,
        kind: ClipKind.photo,
        riderId: 'levi',
        capturedAt: now.subtract(const Duration(hours: 1, minutes: 4)),
      ),
      Clip(
        id: 'seed-${_seq++}',
        title: 'Catch — MOB auto-clip',
        duration: const Duration(seconds: 9),
        kind: ClipKind.fall,
        riderId: 'levi',
        capturedAt: now.subtract(const Duration(hours: 1, minutes: 40)),
      ),
      Clip(
        id: 'seed-${_seq++}',
        title: 'Toeside carve, full send',
        duration: const Duration(seconds: 18),
        kind: ClipKind.highlight,
        riderId: 'mika',
        capturedAt: now.subtract(const Duration(days: 1, hours: 2)),
      ),
    ]);
    notifyListeners();
  }

  /// Demo-only bridge from the Capture screen's snapshot/highlight buttons
  /// to something visible here — see [seedDemo] docs above for why this
  /// exists instead of a real Core-backed clip feed.
  void addFromCapture({required ClipKind kind, required String preset}) {
    if (!AppConfig.isDemo) throw StateError('Demo media is unavailable in Core mode');
    add(Clip(
      id: 'live-${_seq++}',
      title: kind == ClipKind.photo ? 'Snapshot — $preset' : 'Highlight — $preset',
      duration: kind == ClipKind.photo ? Duration.zero : const Duration(seconds: 12),
      kind: kind,
      riderId: 'levi',
      capturedAt: DateTime.now(),
    ));
  }

}

/// A small fixed palette rather than per-clip random colors, so cards read
/// as one designed system instead of noise — each clip picks one
/// deterministically from its id, so it doesn't jump around on rebuild.
const _cardPalettes = [
  [Color(0xFF123A4A), Color(0xFF0B222E)],
  [Color(0xFF1C2F4A), Color(0xFF0E1A2E)],
  [Color(0xFF2A3A2C), Color(0xFF14201A)],
];

List<Color> _paletteFor(String id) => _cardPalettes[id.hashCode.abs() % _cardPalettes.length];

class LibraryScreen extends StatefulWidget {
  final ClipRepository repository;
  const LibraryScreen({super.key, required this.repository});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  ClipKind? _filter;
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Perpetual animation — must respect reduce-motion / test settings the
    // same way SimulatedWakeView does, or WidgetTester.pumpAndSettle() hangs
    // forever (every screen stays mounted under the root Stack; see
    // main.dart's _RootShell).
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _sheen.stop();
    } else if (!_sheen.isAnimating) {
      _sheen.repeat();
    }
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        final all = widget.repository.clips;
        final clips = all.where((c) => _filter == null || c.kind == _filter).toList();
        final hero = _filter == null && all.isNotEmpty ? all.first : null;
        final rest = hero == null ? clips : clips.where((c) => c.id != hero.id).toList();

        return Scaffold(
          // Disabled (not spinning) while an import is in flight — most of
          // that time is the user deciding at the preview dialog, not
          // continuous work, so an indeterminate spinner on the FAB itself
          // would misrepresent an indefinite wait as ongoing progress. The
          // brief real copy step shows its own spinner in a dialog (see
          // media_import_sheet.dart's _showImporting).
          floatingActionButton: FloatingActionButton.extended(
            // Explicit unique tag: every bottom-nav tab's screen stays
            // mounted simultaneously (see main.dart's _RootShell), so two
            // FABs with the default shared hero tag collide even though
            // only one is ever visible at a time.
            heroTag: 'library-add-media-fab',
            onPressed: widget.repository.importing ? null : () => _openAddMedia(context),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add media'),
          ),
          body: SafeArea(
            child: clips.isEmpty
                ? Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Library', style: Theme.of(context).textTheme.titleLarge),
                          ],
                        ),
                      ),
                      _FilterRow(current: _filter, onChanged: (f) => setState(() => _filter = f)),
                      Expanded(
                        child: !AppConfig.isDemo && widget.repository.loading
                            ? const Center(child: CircularProgressIndicator())
                            : !AppConfig.isDemo && widget.repository.loadError != null
                                ? _CatalogErrorState(
                                    message: widget.repository.loadError!,
                                    onRetry: () => widget.repository.retryLoadFromCore(
                                      HttpMediaCatalogService(),
                                      context.read<PairingService>().credential!.deviceId,
                                      bearerToken:
                                          context.read<PairingService>().credential!.bearerToken!,
                                    ),
                                  )
                                : const _EmptyState(),
                      ),
                    ],
                  )
                : CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
                        sliver: SliverToBoxAdapter(
                          child: Text('Library', style: Theme.of(context).textTheme.titleLarge),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _FilterRow(current: _filter, onChanged: (f) => setState(() => _filter = f)),
                      ),
                      if (hero != null)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
                          sliver: SliverToBoxAdapter(
                            child: AnimatedBuilder(
                              animation: _sheen,
                              builder: (_, __) => _HeroClipCard(
                                clip: hero,
                                sheenT: _sheen.value,
                                onTap: () => _openClip(context, hero),
                                onFavorite: () => widget.repository.toggleFavorite(hero.id),
                              ),
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.92,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => AnimatedBuilder(
                              animation: _sheen,
                              builder: (_, __) => _ClipCard(
                                clip: rest[i],
                                sheenT: _sheen.value,
                                phase: i * 0.37,
                                onTap: () => _openClip(context, rest[i]),
                                onFavorite: () => widget.repository.toggleFavorite(rest[i].id),
                              ),
                            ),
                            childCount: rest.length,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Future<void> _openAddMedia(BuildContext context) async {
    final kind = await showModalBottomSheet<ImportMediaKind>(
      context: context,
      backgroundColor: BinnacleColors.navy,
      builder: (sheetContext) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_outlined, color: BinnacleColors.tealBright),
            title: const Text('Choose a photo'),
            onTap: () => Navigator.of(sheetContext).pop(ImportMediaKind.photo),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined, color: BinnacleColors.tealBright),
            title: const Text('Choose a video'),
            onTap: () => Navigator.of(sheetContext).pop(ImportMediaKind.video),
          ),
        ]),
      ),
    );
    if (kind == null || !context.mounted) return;
    await pickAndImportMedia(context, kind: kind);
  }

  void _openClip(BuildContext context, Clip clip) {
    showGlassBottomSheet(
      context: context,
      builder: (_) => _ClipDetailSheet(clip: clip, repository: widget.repository),
    );
  }
}

/// Real playback (when the clip has a real Core media URL), download (opens
/// the media URL — the OS/browser handles the actual save), and share (the
/// real media link via share_plus) — replacing what used to be a purely
/// decorative play icon and a favorite button as the only real action.
class _ClipDetailSheet extends StatefulWidget {
  final Clip clip;
  final ClipRepository repository;
  const _ClipDetailSheet({required this.clip, required this.repository});

  @override
  State<_ClipDetailSheet> createState() => _ClipDetailSheetState();
}

class _ClipDetailSheetState extends State<_ClipDetailSheet> {
  VideoPlayerController? _player;
  String? _playerError;

  /// Looks up the live clip from the repository rather than trusting the
  /// snapshot passed at open time — an in-flight upload's progress
  /// (copyWith'd onto a new Clip instance on every update, see
  /// ClipRepository.startUpload) must be reflected live while this sheet
  /// stays open, not frozen at whatever it looked like on open.
  Clip get clip => widget.repository.clips
      .firstWhere((c) => c.id == widget.clip.id, orElse: () => widget.clip);

  bool get _hasRealMedia => clip.mediaUrl != null && clip.kind != ClipKind.photo;

  /// A real file on this device — from [ClipRepository.importPicked] —
  /// distinct from [_hasRealMedia] (a Core-hosted URL). Independent of any
  /// backend: playable whether or not upload is available.
  bool get _hasLocalVideo => clip.localPath != null && clip.kind != ClipKind.photo;
  bool get _hasLocalPhoto => clip.localPath != null && clip.kind == ClipKind.photo;

  /// Download/share only make sense for a real Core-hosted link — a bundled
  /// demo asset (a local `assets/...` path, see seedDemo()) is genuinely
  /// playable but isn't a URL `url_launcher`/`share_plus` can do anything
  /// useful with.
  bool get _isRemoteMedia => _hasRealMedia && !clip.mediaUrl!.startsWith('assets/');

  @override
  void initState() {
    super.initState();
    // Repaints this sheet while it's open for a live upload progress/
    // outcome update — the sheet isn't inside the Library screen's own
    // AnimatedBuilder(animation: repository), it's a separate route.
    widget.repository.addListener(_onRepositoryChanged);
  }

  void _onRepositoryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.repository.removeListener(_onRepositoryChanged);
    _player?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final localPath = clip.localPath;
    final url = clip.mediaUrl;
    late final VideoPlayerController controller;
    if (localPath != null && clip.kind != ClipKind.photo) {
      controller = VideoPlayerController.file(File(localPath));
    } else if (url != null) {
      // A bundled demo asset (see seedDemo()) is a local path, not an
      // http(s) URL — a real Core-backed clip's mediaUrl always comes from
      // HttpMediaCatalogService and is always http(s).
      controller = url.startsWith('assets/')
          ? VideoPlayerController.asset(url)
          : VideoPlayerController.networkUrl(Uri.parse(url));
    } else {
      return;
    }
    setState(() => _player = controller);
    try {
      await controller.initialize();
      final edit = clip.editDefinition;
      if (edit != null) {
        // Real trim enforcement at playback — see clip.dart's
        // EditDefinition doc comment for why this isn't a re-encoded
        // file. A periodic listener stops playback at trimEnd rather
        // than letting it run into footage the user chose to cut.
        await controller.seekTo(edit.trimStart);
        controller.addListener(_stopAtTrimEnd);
      }
      await controller.play();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _playerError = 'Could not play this clip: $e');
    }
  }

  void _stopAtTrimEnd() {
    final player = _player;
    final edit = clip.editDefinition;
    if (player == null || edit == null) return;
    if (player.value.position >= edit.trimEnd) {
      player.pause();
      player.seekTo(edit.trimStart);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      // Scrollable rather than a fixed-height Column: the upload-status
      // row (retry/cancel) is new content that can push total height past
      // the sheet's available space on a short viewport — scrolling avoids
      // a real overflow rather than trusting every combination of clip
      // state to fit unscrolled.
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_player != null && _player!.value.isInitialized)
            AspectRatio(
              aspectRatio: _player!.value.aspectRatio,
              child: VideoPlayer(_player!),
            )
          else if (_hasLocalPhoto)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(File(clip.localPath!), height: 180, fit: BoxFit.cover),
            )
          else if (_hasRealMedia || _hasLocalVideo)
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _player == null ? _play : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(_player == null ? 'Play' : 'Loading…'),
              ),
            ),
          if (_playerError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_playerError!, style: const TextStyle(color: BinnacleColors.amber, fontSize: 12)),
            ),
          const SizedBox(height: 10),
          Text(clip.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text('${clip.duration.inSeconds}s · captured ${clip.capturedAt}', style: BinnacleTheme.mono(size: 11)),
          const SizedBox(height: 10),
          if (clip.signed && clip.gpsAttached)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: BinnacleColors.tealBright.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: BinnacleColors.tealBright.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.verified_outlined, size: 14, color: BinnacleColors.tealBright),
                const SizedBox(width: 6),
                Text('Signed on Vision · GPS attached', style: BinnacleTheme.mono(size: 10, color: BinnacleColors.tealBright)),
              ]),
            ),
          if (clip.localPath != null)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Imported from this phone — plays locally; not downloadable or '
                'shareable as a link unless cloud upload is available.',
                style: TextStyle(color: BinnacleColors.slate, fontSize: 12),
              ),
            )
          else if (!_hasRealMedia)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                AppConfig.isDemo
                    ? 'Demo clip — no real media to download or share.'
                    : 'No media available for this clip yet.',
                style: const TextStyle(color: BinnacleColors.slate, fontSize: 12),
              ),
            )
          else if (!_isRemoteMedia)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Bundled demo footage — plays locally; not downloadable or shareable as a link.',
                style: TextStyle(color: BinnacleColors.slate, fontSize: 12),
              ),
            ),
          if (clip.localPath != null) ...[
            const SizedBox(height: 10),
            _UploadStatusRow(clip: clip, repository: widget.repository),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => widget.repository.toggleFavorite(clip.id),
                icon: Icon(clip.favorite ? Icons.favorite : Icons.favorite_border),
                label: Text(clip.favorite ? 'Favorited' : 'Favorite'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Download',
              onPressed: !_isRemoteMedia
                  ? null
                  : () => launchUrl(Uri.parse(clip.mediaUrl!), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.download_outlined),
            ),
            IconButton(
              tooltip: 'Share',
              onPressed: !_isRemoteMedia
                  ? null
                  : () => Share.share(clip.mediaUrl!, subject: clip.title),
              icon: const Icon(Icons.ios_share),
            ),
          ]),
          // Editing needs a real local video file — never offered for a
          // photo or a Core/demo clip with no localPath (nothing to open
          // as a VideoPlayerController.file source).
          if (_hasLocalVideo) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final edited = await Navigator.of(context).push<Clip>(
                    MaterialPageRoute(builder: (_) => HighlightEditorScreen(sourceClip: clip)),
                  );
                  if (edited != null && context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.content_cut),
                label: const Text('Edit highlight'),
              ),
            ),
          ],
        ],
        ),
      ),
    );
  }
}

/// Real pause/resume/cancel/retry controls for a phone-imported clip's
/// place in the offline upload queue — see ClipRepository's
/// enqueueUpload/pauseUpload/resumeUpload/retryUpload/cancelUpload. Since
/// the shipped NoOpMediaUploadService reports `isAvailable == false`,
/// these controls stay honestly absent in production until a real
/// backend exists — see media_upload_service.dart.
class _UploadStatusRow extends StatelessWidget {
  final Clip clip;
  final ClipRepository repository;
  const _UploadStatusRow({required this.clip, required this.repository});

  @override
  Widget build(BuildContext context) {
    final uploader = context.read<MediaUploadService>();
    if (!uploader.isAvailable && clip.uploadStatus == UploadStatus.onPhoneOnly) {
      return const Text(
        'Cloud upload isn\'t available yet — this stays on this phone only.',
        style: TextStyle(color: BinnacleColors.slateDim, fontSize: 11.5),
      );
    }
    final failureMessage = repository.failureMessageFor(clip.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _UploadStatusBadge(clip: clip),
        const Spacer(),
        if (clip.uploadStatus == UploadStatus.queued || clip.uploadStatus == UploadStatus.uploading)
          TextButton(
            onPressed: () => repository.pauseUpload(clip.id),
            child: const Text('Pause'),
          ),
        if (clip.uploadStatus == UploadStatus.paused)
          TextButton(
            onPressed: () => repository.resumeUpload(clip.id),
            child: const Text('Resume'),
          ),
        if (clip.uploadStatus == UploadStatus.queued ||
            clip.uploadStatus == UploadStatus.uploading ||
            clip.uploadStatus == UploadStatus.paused)
          TextButton(
            onPressed: () => repository.cancelUpload(clip.id),
            child: const Text('Cancel'),
          ),
        if (clip.uploadStatus == UploadStatus.failed)
          TextButton(
            onPressed: () => repository.retryUpload(clip.id),
            child: const Text('Retry'),
          ),
        if (clip.uploadStatus == UploadStatus.onPhoneOnly && uploader.isAvailable)
          TextButton(
            onPressed: () => repository.enqueueUpload(clip.id),
            child: const Text('Upload'),
          ),
      ]),
      if (clip.uploadStatus == UploadStatus.failed && failureMessage != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(failureMessage, style: const TextStyle(color: BinnacleColors.orange, fontSize: 11.5)),
        ),
      if (clip.uploadStatus == UploadStatus.queued && !repository._connectivitySatisfiesPreference)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            repository.uploadNetworkPreference == UploadNetworkPreference.wifiOnly
                ? 'Waiting for Wi-Fi (set to cellular in Settings if you want to upload now).'
                : 'Waiting for a connection.',
            style: const TextStyle(color: BinnacleColors.slateDim, fontSize: 11.5),
          ),
        ),
    ]);
  }
}

class _FilterRow extends StatelessWidget {
  final ClipKind? current;
  final void Function(ClipKind?) onChanged;
  const _FilterRow({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, ClipKind? k) {
      final on = current == k;
      return Padding(
        padding: const EdgeInsets.only(right: 7),
        child: GestureDetector(
          onTap: () => onChanged(k),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: on ? BinnacleColors.teal.withValues(alpha: 0.1) : BinnacleColors.navy,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: on ? BinnacleColors.teal : BinnacleColors.offWhite.withValues(alpha: 0.09)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: on ? BinnacleColors.tealBright : BinnacleColors.slate,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          chip('All', null),
          chip('Highlights', ClipKind.highlight),
          chip('Photos', ClipKind.photo),
          chip('Falls', ClipKind.fall),
        ]),
      ),
    );
  }
}

/// Moving diagonal highlight over a card's gradient — the cheapest possible
/// stand-in for a looping cinemagraph thumbnail (no video asset, one shared
/// AnimationController for the whole grid). [phase] staggers cards so they
/// don't all glint in lockstep.
class _Sheen extends StatelessWidget {
  final double t;
  final double phase;
  const _Sheen({required this.t, this.phase = 0});

  @override
  Widget build(BuildContext context) {
    final p = (t + phase) % 1.0;
    final pos = -0.6 + p * 2.2;
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(pos - 0.5, -1),
            end: Alignment(pos + 0.5, 1),
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.05),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0.35, 0.5, 0.65],
          ),
        ),
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  final ClipKind kind;
  const _KindBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (kind) {
      ClipKind.fall => ('MOB', BinnacleColors.orange),
      ClipKind.photo => ('PHOTO', BinnacleColors.tealBright),
      ClipKind.highlight => ('CLIP', BinnacleColors.amber),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: BinnacleTheme.mono(size: 8.5, color: BinnacleColors.navyDeep, weight: FontWeight.w700)),
    );
  }
}

/// Shown only for phone-imported media ([Clip.localPath] set) — a Core-
/// fetched or demo-seeded clip never shows an upload state at all, since
/// it was never something this app itself uploaded.
class _UploadStatusBadge extends StatelessWidget {
  final Clip clip;
  const _UploadStatusBadge({required this.clip});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (clip.uploadStatus) {
      UploadStatus.onPhoneOnly => ('ON THIS PHONE', BinnacleColors.slateLight),
      UploadStatus.queued => ('QUEUED', BinnacleColors.amber),
      UploadStatus.uploading =>
        ('UPLOADING ${((clip.uploadProgress ?? 0) * 100).round()}%', BinnacleColors.tealBright),
      UploadStatus.paused => ('PAUSED', BinnacleColors.slateLight),
      UploadStatus.uploaded => ('UPLOADED', BinnacleColors.tealBright),
      UploadStatus.failed => ('UPLOAD FAILED', BinnacleColors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: BinnacleColors.navyDeep.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: BinnacleTheme.mono(size: 8, color: color, weight: FontWeight.w700)),
    );
  }
}

/// The most recent clip gets a full-width, larger "now playing" treatment —
/// the same instinct as a video app's "continue watching" hero, instead of
/// treating every clip as an identically-sized grid tile.
class _HeroClipCard extends StatelessWidget {
  final Clip clip;
  final double sheenT;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  const _HeroClipCard({required this.clip, required this.sheenT, required this.onTap, required this.onFavorite});

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(clip.id);
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: palette),
                ),
              ),
              _Sheen(t: sheenT),
              const Center(
                child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 46),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Row(children: [
                  _KindBadge(kind: clip.kind),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: BinnacleColors.navyDeep.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('LATEST', style: BinnacleTheme.mono(size: 8.5, color: BinnacleColors.tealBright, weight: FontWeight.w700)),
                  ),
                  if (clip.localPath != null) ...[
                    const SizedBox(width: 6),
                    _UploadStatusBadge(clip: clip),
                  ],
                ]),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: _FavoriteButton(favorite: clip.favorite, onTap: onFavorite),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 26, 14, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, BinnacleColors.navyDeep.withValues(alpha: 0.88)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(clip.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white)),
                      const SizedBox(height: 3),
                      Text(
                        clip.duration == Duration.zero ? _timeAgo(clip.capturedAt) : '${clip.duration.inSeconds}s · ${_timeAgo(clip.capturedAt)}',
                        style: BinnacleTheme.mono(size: 10.5, color: BinnacleColors.slate),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClipCard extends StatelessWidget {
  final Clip clip;
  final double sheenT;
  final double phase;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  const _ClipCard({
    required this.clip,
    required this.sheenT,
    required this.phase,
    required this.onTap,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor(clip.id);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: palette),
              ),
            ),
            _Sheen(t: sheenT, phase: phase),
            if (clip.kind != ClipKind.photo)
              const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white54, size: 30)),
            Positioned(top: 6, left: 6, child: _KindBadge(kind: clip.kind)),
            if (clip.localPath != null)
              Positioned(bottom: 34, left: 6, child: _UploadStatusBadge(clip: clip)),
            Positioned(top: 4, right: 4, child: _FavoriteButton(favorite: clip.favorite, onTap: onFavorite, small: true)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(9, 18, 9, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, BinnacleColors.navyDeep.withValues(alpha: 0.9)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(clip.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                      clip.duration == Duration.zero ? _timeAgo(clip.capturedAt) : '${clip.duration.inSeconds}s',
                      style: BinnacleTheme.mono(size: 9, color: BinnacleColors.slate),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  final bool favorite;
  final VoidCallback onTap;
  final bool small;
  const _FavoriteButton({required this.favorite, required this.onTap, this.small = false});

  @override
  Widget build(BuildContext context) {
    final size = small ? 24.0 : 30.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BinnacleColors.navyDeep.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
          child: Icon(
            favorite ? Icons.favorite : Icons.favorite_border,
            key: ValueKey(favorite),
            size: small ? 13 : 16,
            color: favorite ? BinnacleColors.orange : Colors.white70,
          ),
        ),
      ),
    );
  }
}

String _timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const BinnacleEmptyState(
        icon: Icons.video_camera_back_outlined,
        title: 'No clips yet',
        subtitle: 'Hit the water and press Save Highlight —\nyour best pass shows up here first.',
        accent: BinnacleColors.tealBright,
      );
}

/// A real fetch against the Core's clip catalog failed — shown instead of
/// the "no clips yet" empty state, which would otherwise misrepresent a
/// failed load as a genuinely empty Library.
class _CatalogErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _CatalogErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: BinnacleColors.amber, size: 40),
              const SizedBox(height: 12),
              const Text("Couldn't load clips from Core",
                  style: TextStyle(fontFamily: 'Space Grotesk', fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: BinnacleColors.slate)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}
