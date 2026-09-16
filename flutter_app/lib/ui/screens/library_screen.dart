import 'package:flutter/material.dart';
import '../../core/models/clip.dart';
import '../theme/binnacle_theme.dart';

/// Local, in-memory clip store for this scaffold. A real build replaces
/// this with a repository backed by the Core's clip API — signing and GPS
/// attachment happen on Vision at capture time (see F-44), this class only
/// displays what it's told.
class ClipRepository extends ChangeNotifier {
  final List<Clip> _clips = [];
  List<Clip> get clips => List.unmodifiable(_clips);

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
                      const Expanded(child: _EmptyState()),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: BinnacleColors.navy,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => widget.repository.toggleFavorite(clip.id),
                  icon: Icon(clip.favorite ? Icons.favorite : Icons.favorite_border),
                  label: Text(clip.favorite ? 'Favorited' : 'Favorite'),
                ),
              ),
            ]),
          ],
        ),
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
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.video_camera_back_outlined, size: 40, color: BinnacleColors.slateDim),
              const SizedBox(height: 14),
              Text(
                'Nothing here yet. Capture a highlight, or import footage to run through Track.',
                textAlign: TextAlign.center,
                style: TextStyle(color: BinnacleColors.slate),
              ),
            ],
          ),
        ),
      );
}
