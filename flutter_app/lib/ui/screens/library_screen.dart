import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../core/app_config.dart';
import '../../core/models/clip.dart';
import '../../core/services/camera_media_source.dart'
    show DemoRecordedCameraSource;
import '../../core/services/demo_media.dart';
import '../../core/services/media_catalog_service.dart';
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
  /// Persists Demo-origin clips across restarts. Null (the default, and always
  /// in Core Mode) means nothing is persisted here: Core clips come from the
  /// Core, never from local storage.
  final DemoLibraryStore? _demoStore;

  ClipRepository({DemoLibraryStore? demoStore}) : _demoStore = demoStore;

  final List<Clip> _clips = [];
  List<Clip> get clips => List.unmodifiable(_clips);

  bool loading = false;
  String? loadError;

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
    if (_clips[i].isDemoOrigin) _persistDemo();
  }

  /// Demo-origin clips worth persisting: those the user created locally. The
  /// seeded showcase clips are regenerated each launch, never stored.
  List<Clip> get _persistableDemoClips =>
      _clips.where((c) => c.isDemoOrigin && !c.id.startsWith('seed-')).toList();

  Future<void> _persistDemo() async {
    final store = _demoStore;
    if (store == null) return;
    try {
      await store.save(_persistableDemoClips);
    } catch (e) {
      debugPrint('Demo Library save failed: $e');
    }
  }

  /// Restores locally created Demo media. A snapshot whose image file has
  /// disappeared is dropped rather than shown as a broken card.
  Future<void> hydrateDemo() async {
    final store = _demoStore;
    if (store == null) return;
    if (!AppConfig.isDemo) return;
    final saved = await store.load();
    final restored = <Clip>[
      for (final c in saved)
        if (c.origin != ClipOrigin.demoLocalCapture ||
            (c.localPath != null && File(c.localPath!).existsSync()))
          c,
    ]..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    final known = _clips.map((c) => c.id).toSet();
    _clips.insertAll(0, restored.where((c) => !known.contains(c.id)));
    notifyListeners();
  }

  /// A Library item another screen (the Live console's Snapshot thumbnail) asked
  /// to open. The Library screen consumes it once it is showing.
  String? pendingOpenClipId;

  void requestOpen(String clipId) {
    pendingOpenClipId = clipId;
    notifyListeners();
  }

  /// Returns and clears the pending request if that clip exists.
  Clip? takePendingOpen() {
    final id = pendingOpenClipId;
    if (id == null) return null;
    pendingOpenClipId = null;
    for (final c in _clips) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Adds Demo media created locally by a Demo action, and persists it. Only
  /// valid in Demo Mode; Core media never enters the Library this way.
  Future<void> addDemoLocalClip(Clip clip) async {
    if (!AppConfig.isDemo) {
      throw StateError('Demo media is unavailable in Core mode');
    }
    if (!clip.isDemoOrigin) {
      throw ArgumentError('Only Demo-origin clips can be added here');
    }
    add(clip);
    await _persistDemo();
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
    if (!AppConfig.isDemo)
      throw StateError('Demo media is unavailable in Core mode');
    if (_clips.isNotEmpty) return;
    final now = DateTime.now();
    _clips.addAll([
      Clip(
        id: 'seed-${_seq++}',
        title: 'Wakesurf session — full pass',
        duration: const Duration(seconds: 130),
        kind: ClipKind.highlight,
        riderId: 'levi',
        favorite: true,
        capturedAt: now.subtract(const Duration(minutes: 9)),
        // Real GoPro development footage (VER-01), bundled as a Flutter
        // asset — genuinely playable in demo mode, not a dead URL. Still
        // demo data: this is not Core-backed media (see Clip.mediaUrl's
        // doc comment) and mediaUrl for a real clip only ever comes from
        // HttpMediaCatalogService's real Core fetch.
        origin: ClipOrigin.demoSegment,
        segment: MediaSegment(
          assetPath: DemoRecordedCameraSource.defaultAssetPath,
          start: Duration.zero,
          end: Duration(seconds: 130),
        ),
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
    if (!AppConfig.isDemo)
      throw StateError('Demo media is unavailable in Core mode');
    add(Clip(
      id: 'live-${_seq++}',
      title:
          kind == ClipKind.photo ? 'Snapshot — $preset' : 'Highlight — $preset',
      duration:
          kind == ClipKind.photo ? Duration.zero : const Duration(seconds: 12),
      kind: kind,
      riderId: 'levi',
      capturedAt: DateTime.now(),
    ));
  }

  /// Demo-only stand-in for "pick a fall video off Vision's storage or the
  /// phone's camera roll" — there's no real device/gallery picker
  /// integration yet. This is deliberately the ONLY way Best Falls gets new
  /// footage to submit from (besides picking an existing clip already in
  /// the Library): real evidence, not a typed name and a self-ticked
  /// checkbox. Returns the created clip so the caller can submit it
  /// immediately.
  Clip importFallClip() {
    if (!AppConfig.isDemo)
      throw StateError('Demo media is unavailable in Core mode');
    final clip = Clip(
      id: 'import-${_seq++}',
      title: 'Imported fall clip',
      duration: const Duration(seconds: 11),
      kind: ClipKind.fall,
      riderId: 'levi',
      capturedAt: DateTime.now(),
    );
    add(clip);
    return clip;
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

List<Color> _paletteFor(String id) =>
    _cardPalettes[id.hashCode.abs() % _cardPalettes.length];

class LibraryScreen extends StatefulWidget {
  final ClipRepository repository;
  const LibraryScreen({super.key, required this.repository});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
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
        final pending = widget.repository.takePendingOpen();
        if (pending != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openClip(context, pending);
          });
        }
        final clips =
            all.where((c) => _filter == null || c.kind == _filter).toList();
        final hero = _filter == null && all.isNotEmpty ? all.first : null;
        final rest =
            hero == null ? clips : clips.where((c) => c.id != hero.id).toList();

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
                            Text('Library',
                                style: Theme.of(context).textTheme.titleLarge),
                          ],
                        ),
                      ),
                      _FilterRow(
                          current: _filter,
                          onChanged: (f) => setState(() => _filter = f)),
                      Expanded(
                        child: !AppConfig.isDemo && widget.repository.loading
                            ? const Center(child: CircularProgressIndicator())
                            : !AppConfig.isDemo &&
                                    widget.repository.loadError != null
                                ? _CatalogErrorState(
                                    message: widget.repository.loadError!,
                                    onRetry: () =>
                                        widget.repository.retryLoadFromCore(
                                      HttpMediaCatalogService(),
                                      context
                                          .read<PairingService>()
                                          .credential!
                                          .deviceId,
                                      bearerToken: context
                                          .read<PairingService>()
                                          .credential!
                                          .bearerToken!,
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
                          child: Text('Library',
                              style: Theme.of(context).textTheme.titleLarge),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _FilterRow(
                            current: _filter,
                            onChanged: (f) => setState(() => _filter = f)),
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
                                onFavorite: () =>
                                    widget.repository.toggleFavorite(hero.id),
                              ),
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
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
                                onFavorite: () => widget.repository
                                    .toggleFavorite(rest[i].id),
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
      builder: (_) =>
          _ClipDetailSheet(clip: clip, repository: widget.repository),
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
  bool _segmentFinished = false;

  MediaSegment? get _segment => widget.clip.segment;

  bool get _hasRealMedia =>
      (widget.clip.mediaUrl != null || _segment != null) &&
      widget.clip.kind != ClipKind.photo;

  /// Download/share only make sense for a real Core-hosted link. A demo
  /// segment or local image is genuinely playable/viewable but has no URL.
  bool get _isRemoteMedia => widget.clip.mediaUrl != null;

  @override
  void dispose() {
    _player?.removeListener(_enforceSegmentEnd);
    _player?.dispose();
    super.dispose();
  }

  /// A demo highlight is a reference into the bundled source, so playback must
  /// stop at the saved end point instead of running to the end of the source.
  void _enforceSegmentEnd() {
    final seg = _segment;
    final player = _player;
    if (seg == null || player == null || !player.value.isInitialized) return;
    if (player.value.position >= seg.end && !_segmentFinished) {
      _segmentFinished = true;
      player.pause();
      player.seekTo(seg.start);
    }
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayback() async {
    final player = _player;
    if (player == null || !player.value.isInitialized) return;
    if (player.value.isPlaying) {
      await player.pause();
    } else {
      final seg = _segment;
      if (seg != null && _segmentFinished) {
        _segmentFinished = false;
        await player.seekTo(seg.start);
      }
      await player.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _play() async {
    final seg = _segment;
    final url = widget.clip.mediaUrl;
    if (seg == null && url == null) return;
    // A demo segment plays the bundled asset from its saved start point; a
    // real Core-backed clip's mediaUrl always comes from HttpMediaCatalogService
    // and is always http(s).
    final controller = seg != null
        ? VideoPlayerController.asset(seg.assetPath)
        : VideoPlayerController.networkUrl(Uri.parse(url!));
    setState(() => _player = controller);
    try {
      await controller.initialize();
      if (seg != null) {
        await controller.seekTo(seg.start);
        controller.addListener(_enforceSegmentEnd);
      }
      await controller.play();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted)
        setState(() => _playerError = 'Could not play this clip: $e');
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
          if (clip.localPath != null && File(clip.localPath!).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(File(clip.localPath!),
                  fit: BoxFit.contain, gaplessPlayback: true),
            ),
          if (_player != null && _player!.value.isInitialized) ...[
            AspectRatio(
              aspectRatio: _player!.value.aspectRatio,
              child: VideoPlayer(_player!),
            ),
            if (_segment != null)
              _SegmentControls(
                segment: _segment!,
                position: _player!.value.position,
                playing: _player!.value.isPlaying,
                onToggle: _togglePlayback,
              ),
          ] else if (_hasRealMedia)
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
              child: Text(_playerError!,
                  style: const TextStyle(
                      color: BinnacleColors.amber, fontSize: 12)),
            ),
          const SizedBox(height: 10),
          Text(clip.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text('${clip.duration.inSeconds}s · captured ${clip.capturedAt}',
              style: BinnacleTheme.mono(size: 11)),
          const SizedBox(height: 10),
          if (clip.isDemoOrigin)
            _DemoProvenance(clip: clip)
          else if (clip.signed && clip.gpsAttached)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: BinnacleColors.tealBright.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: BinnacleColors.tealBright.withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.verified_outlined,
                    size: 14, color: BinnacleColors.tealBright),
                const SizedBox(width: 6),
                Text('Signed on Vision · GPS attached',
                    style: BinnacleTheme.mono(
                        size: 10, color: BinnacleColors.tealBright)),
              ]),
            ),
          if (clip.localPath != null)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Real frame from the recorded demo feed, saved on this phone.',
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
                style:
                    const TextStyle(color: BinnacleColors.slate, fontSize: 12),
              ),
            )
          else if (!_isRemoteMedia)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Recorded demo footage — plays locally from the bundled demo asset; not downloadable or shareable as a link.',
                style: TextStyle(color: BinnacleColors.slate, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => widget.repository.toggleFavorite(clip.id),
                icon: Icon(
                    clip.favorite ? Icons.favorite : Icons.favorite_border),
                label: Text(clip.favorite ? 'Favorited' : 'Favorite'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Download',
              onPressed: !_isRemoteMedia
                  ? null
                  : () => launchUrl(Uri.parse(clip.mediaUrl!),
                      mode: LaunchMode.externalApplication),
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
              color: on
                  ? BinnacleColors.teal.withValues(alpha: 0.1)
                  : BinnacleColors.navy,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: on
                      ? BinnacleColors.teal
                      : BinnacleColors.offWhite.withValues(alpha: 0.09)),
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

/// Path of a real local image for this clip, or null. Synchronous existence
/// check so a missing file falls back to the gradient instead of a broken card.
String? _localImagePath(Clip c) {
  final path = c.localPath ?? c.thumbnailPath;
  if (path == null || path.startsWith('http')) return null;
  return File(path).existsSync() ? path : null;
}

/// The clip's real image (a captured frame) under the card chrome.
class _ClipArtwork extends StatelessWidget {
  final Clip clip;
  const _ClipArtwork({required this.clip});

  @override
  Widget build(BuildContext context) {
    final path = _localImagePath(clip);
    if (path == null) return const SizedBox.shrink();
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}

/// Marks media that came from the recorded Demo, never from Core/Vision.
class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: BinnacleColors.navyDeep.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(6),
          border:
              Border.all(color: BinnacleColors.amber.withValues(alpha: 0.8)),
        ),
        child: Text('DEMO',
            style: BinnacleTheme.mono(
                size: 8.5,
                color: BinnacleColors.amber,
                weight: FontWeight.w700)),
      );
}

class _DemoProvenance extends StatelessWidget {
  final Clip clip;
  const _DemoProvenance({required this.clip});

  @override
  Widget build(BuildContext context) {
    final seg = clip.segment;
    final where = seg == null
        ? 'frame of the recorded demo feed'
        : 'segment ${formatDemoTime(seg.start)}–${formatDemoTime(seg.end)} of the recorded demo feed';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: BinnacleColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BinnacleColors.amber.withValues(alpha: 0.5)),
      ),
      child: Text(
        'DEMO — $where. Simulated locally; not captured by Core or Vision.',
        style: BinnacleTheme.mono(size: 10, color: BinnacleColors.amber),
      ),
    );
  }
}

/// Play/pause and a position readout relative to the saved segment, so the
/// start and stop points are visible.
class _SegmentControls extends StatelessWidget {
  final MediaSegment segment;
  final Duration position;
  final bool playing;
  final VoidCallback onToggle;
  const _SegmentControls({
    required this.segment,
    required this.position,
    required this.playing,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    var rel = position - segment.start;
    if (rel < Duration.zero) rel = Duration.zero;
    if (rel > segment.length) rel = segment.length;
    return Row(children: [
      IconButton(
        tooltip: playing ? 'Pause' : 'Play',
        onPressed: onToggle,
        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
      ),
      Text('${formatDemoTime(rel)} / ${formatDemoTime(segment.length)}',
          style: BinnacleTheme.mono(size: 11)),
      const Spacer(),
      Text(
          'source ${formatDemoTime(segment.start)}–${formatDemoTime(segment.end)}',
          style: BinnacleTheme.mono(size: 10, color: BinnacleColors.slate)),
    ]);
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
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          style: BinnacleTheme.mono(
              size: 8.5,
              color: BinnacleColors.navyDeep,
              weight: FontWeight.w700)),
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
  const _HeroClipCard(
      {required this.clip,
      required this.sheenT,
      required this.onTap,
      required this.onFavorite});

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
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: palette),
                ),
              ),
              _ClipArtwork(clip: clip),
              _Sheen(t: sheenT),
              if (clip.kind != ClipKind.photo)
                const Center(
                  child: Icon(Icons.play_circle_fill,
                      color: Colors.white70, size: 46),
                ),
              Positioned(
                top: 10,
                left: 10,
                child: Row(children: [
                  _KindBadge(kind: clip.kind),
                  if (clip.isDemoOrigin) ...[
                    const SizedBox(width: 6),
                    const _DemoBadge(),
                  ],
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: BinnacleColors.navyDeep.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('LATEST',
                        style: BinnacleTheme.mono(
                            size: 8.5,
                            color: BinnacleColors.tealBright,
                            weight: FontWeight.w700)),
                  ),
                ]),
              ),
              Positioned(
                top: 8,
                right: 8,
                child:
                    _FavoriteButton(favorite: clip.favorite, onTap: onFavorite),
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
                      colors: [
                        Colors.transparent,
                        BinnacleColors.navyDeep.withValues(alpha: 0.88)
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(clip.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'Space Grotesk',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Colors.white)),
                      const SizedBox(height: 3),
                      Text(
                        clip.duration == Duration.zero
                            ? _timeAgo(clip.capturedAt)
                            : '${clip.duration.inSeconds}s · ${_timeAgo(clip.capturedAt)}',
                        style: BinnacleTheme.mono(
                            size: 10.5, color: BinnacleColors.slate),
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
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: palette),
              ),
            ),
            _ClipArtwork(clip: clip),
            _Sheen(t: sheenT, phase: phase),
            if (clip.kind != ClipKind.photo)
              const Center(
                  child: Icon(Icons.play_arrow_rounded,
                      color: Colors.white54, size: 30)),
            Positioned(
                top: 6,
                left: 6,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _KindBadge(kind: clip.kind),
                  if (clip.isDemoOrigin) ...[
                    const SizedBox(width: 4),
                    const _DemoBadge(),
                  ],
                ])),
            Positioned(
                top: 4,
                right: 4,
                child: _FavoriteButton(
                    favorite: clip.favorite, onTap: onFavorite, small: true)),
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
                    colors: [
                      Colors.transparent,
                      BinnacleColors.navyDeep.withValues(alpha: 0.9)
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(clip.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                      clip.duration == Duration.zero
                          ? _timeAgo(clip.capturedAt)
                          : '${clip.duration.inSeconds}s',
                      style: BinnacleTheme.mono(
                          size: 9, color: BinnacleColors.slate),
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
  const _FavoriteButton(
      {required this.favorite, required this.onTap, this.small = false});

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
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
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
        subtitle:
            'Hit the water and press Save Highlight —\nyour best pass shows up here first.',
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
              const Icon(Icons.cloud_off,
                  color: BinnacleColors.amber, size: 40),
              const SizedBox(height: 12),
              const Text("Couldn't load clips from Core",
                  style: TextStyle(
                      fontFamily: 'Space Grotesk',
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
              const SizedBox(height: 6),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: BinnacleColors.slate)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}
