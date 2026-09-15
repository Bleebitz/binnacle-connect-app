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
}

class LibraryScreen extends StatefulWidget {
  final ClipRepository repository;
  const LibraryScreen({super.key, required this.repository});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  ClipKind? _filter;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        final clips = widget.repository.clips.where((c) => _filter == null || c.kind == _filter).toList();
        return Scaffold(
          appBar: AppBar(title: const Text('Library')),
          body: Column(
            children: [
              _FilterRow(current: _filter, onChanged: (f) => setState(() => _filter = f)),
              Expanded(
                child: clips.isEmpty
                    ? const _EmptyState()
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 1,
                        ),
                        itemCount: clips.length,
                        itemBuilder: (_, i) => _ClipCell(
                          clip: clips[i],
                          onTap: () => _openClip(context, clips[i]),
                        ),
                      ),
              ),
            ],
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
    Widget chip(String label, ClipKind? k) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(label: Text(label), selected: current == k, onSelected: (_) => onChanged(k)),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

class _ClipCell extends StatelessWidget {
  final Clip clip;
  final VoidCallback onTap;
  const _ClipCell({required this.clip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: BinnacleColors.navyRaised,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(children: [
          if (clip.kind == ClipKind.fall)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: BinnacleColors.orange, borderRadius: BorderRadius.circular(6)),
                child: const Text('MOB', style: TextStyle(fontSize: 8, color: Colors.white)),
              ),
            ),
          if (clip.favorite)
            const Positioned(top: 4, right: 4, child: Icon(Icons.favorite, size: 14, color: BinnacleColors.orange)),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(
            'Nothing here yet. Capture a highlight, or import footage to run through Track.',
            textAlign: TextAlign.center,
            style: TextStyle(color: BinnacleColors.slate),
          ),
        ),
      );
}
