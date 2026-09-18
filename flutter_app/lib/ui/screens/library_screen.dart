import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../core/app_config.dart';
import '../../core/models/clip.dart';
import '../../core/services/library_local_store.dart';
import '../../core/services/media_catalog_service.dart';
import '../../core/services/media_import_service.dart';
import '../../core/services/media_upload_service.dart';
import '../../core/services/pairing_service.dart';
import '../theme/binnacle_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_sheet.dart';

/// Clip store. Demo mode is a local, in-memory scaffold ([seedDemo]/
/// [addFromCapture]/[importFallClip]). Core mode is backed by a real fetch
/// against the Core's clip catalog ([loadFromCore]) — see
/// media_catalog_service.dart for the (unverified, no live Core exists yet)
/// endpoint contract.
class ClipRepository extends ChangeNotifier {
  final List<Clip> _clips = [];
  final LibraryLocalStore _localStore;
  final Map<String, StreamSubscription<UploadProgressUpdate>> _uploads = {};

  ClipRepository({LibraryLocalStore? localStore})
      : _localStore = localStore ?? SharedPreferencesLibraryLocalStore();

  List<Clip> get clips => List.unmodifiable(_clips);

  bool loading = false;
  String? loadError;

  /// True while a pick/import is in flight — the "Add media" UI disables
  /// itself on this, so a duplicate tap during a slow picker/copy can't
  /// start a second concurrent import.
  bool importing = false;

  /// Restores phone-imported entries persisted from a prior session — see
  /// library_local_store.dart. Call once at startup (main.dart), before
  /// any demo seed/Core fetch, so imported media shows up immediately
  /// rather than only after the next add.
  Future<void> hydrate() async {
    final restored = await _localStore.loadImported();
    if (restored.isEmpty) return;
    _clips.insertAll(0, restored);
    notifyListeners();
  }

  Future<void> _persistImported() async {
    await _localStore.saveImported(_clips.where((c) => c.localPath != null).toList());
  }

  /// Real pick -> preview is handled by the caller (UI) via [importer]
  /// directly, since cancelling a preview must never touch the Library at
  /// all. This is called only once the user has confirmed. Copies the
  /// picked file into durable app storage, adds a real Clip in
  /// [UploadStatus.onPhoneOnly], persists it, and — only if [uploader] is
  /// available — kicks off a real upload with progress/cancel/retry.
  /// Throws [MediaImportException] on a real copy failure; never adds a
  /// broken/partial entry on failure.
  Future<Clip> importPicked(
    PickedMedia media, {
    required MediaImportService importer,
    required MediaUploadService uploader,
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
      uploadStatus: UploadStatus.onPhoneOnly,
      signed: false,
      gpsAttached: false,
    );
    add(clip);
    await _persistImported();
    if (uploader.isAvailable) startUpload(clip.id, uploader);
    return clip;
  }

  /// Starts (or retries) a real upload for an already-imported clip.
  /// Cancelling via [cancelUpload] stops the underlying stream — a real
  /// unsubscribe, not just a UI-side flag — so no further progress/result
  /// for that upload is applied after cancellation.
  void startUpload(String clipId, MediaUploadService uploader) {
    _uploads[clipId]?.cancel();
    final i = _clips.indexWhere((c) => c.id == clipId);
    if (i == -1) return;
    _clips[i] = _clips[i].copyWith(uploadStatus: UploadStatus.uploading, uploadProgress: 0);
    notifyListeners();
    final localPath = _clips[i].localPath!;
    _uploads[clipId] = uploader.upload(localPath: localPath, mediaId: clipId).listen((update) {
      final idx = _clips.indexWhere((c) => c.id == clipId);
      if (idx == -1) return;
      if (update.outcome == null) {
        _clips[idx] = _clips[idx].copyWith(uploadProgress: update.fraction);
      } else {
        _clips[idx] = _clips[idx].copyWith(
          uploadStatus: switch (update.outcome!) {
            UploadOutcome.uploaded => UploadStatus.uploaded,
            UploadOutcome.failed || UploadOutcome.unavailable || UploadOutcome.cancelled =>
              UploadStatus.failed,
          },
          uploadProgress: null,
        );
        _uploads.remove(clipId);
        unawaited(_persistImported());
      }
      notifyListeners();
    });
  }

  void cancelUpload(String clipId) {
    _uploads.remove(clipId)?.cancel();
    final i = _clips.indexWhere((c) => c.id == clipId);
    if (i == -1) return;
    _clips[i] = _clips[i].copyWith(uploadStatus: UploadStatus.failed, uploadProgress: null);
    notifyListeners();
    unawaited(_persistImported());
  }

  @override
  void dispose() {
    for (final sub in _uploads.values) {
      sub.cancel();
    }
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

  bool get _hasRealMedia => widget.clip.mediaUrl != null && widget.clip.kind != ClipKind.photo;

  /// Download/share only make sense for a real Core-hosted link — a bundled
  /// demo asset (a local `assets/...` path, see seedDemo()) is genuinely
  /// playable but isn't a URL `url_launcher`/`share_plus` can do anything
  /// useful with.
  bool get _isRemoteMedia => _hasRealMedia && !widget.clip.mediaUrl!.startsWith('assets/');

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final url = widget.clip.mediaUrl;
    if (url == null) return;
    // A bundled demo asset (see seedDemo()) is a local path, not an http(s)
    // URL — a real Core-backed clip's mediaUrl always comes from
    // HttpMediaCatalogService and is always http(s).
    final controller = url.startsWith('assets/')
        ? VideoPlayerController.asset(url)
        : VideoPlayerController.networkUrl(Uri.parse(url));
    setState(() => _player = controller);
    try {
      await controller.initialize();
      await controller.play();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _playerError = 'Could not play this clip: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_player != null && _player!.value.isInitialized)
            AspectRatio(
              aspectRatio: _player!.value.aspectRatio,
              child: VideoPlayer(_player!),
            )
          else if (_hasRealMedia)
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
          if (!_hasRealMedia)
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
        ],
      ),
    );
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
