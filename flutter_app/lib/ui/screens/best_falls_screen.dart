import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/clip.dart' show Clip, ClipKind;
import '../../core/models/fall_entry.dart';
import '../theme/binnacle_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_sheet.dart';
import 'library_screen.dart' show ClipRepository;

/// Best Falls. Submission requires a real captured clip (Vision or phone —
/// see fall_entry.dart's module comment for why the old free-typed-name-
/// plus-checkbox flow is gone), and removed-for-injury entries stay visible
/// in their own section rather than disappearing.
class BestFallsScreen extends StatefulWidget {
  final FallRepository repository;
  const BestFallsScreen({super.key, required this.repository});

  @override
  State<BestFallsScreen> createState() => _BestFallsScreenState();
}

class _BestFallsScreenState extends State<BestFallsScreen> {
  @override
  Widget build(BuildContext context) {
    final clips = context.watch<ClipRepository>().clips;
    String? clipTitle(String clipId) {
      for (final c in clips) {
        if (c.id == clipId) return c.title;
      }
      return null; // the source clip was deleted from the Library — entry still stands
    }

    return AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        final ranked = widget.repository.ranked;
        final removed = widget.repository.removedForInjury;
        return Scaffold(
          appBar: AppBar(title: const Text('Best Falls')),
          body: ranked.isEmpty && removed.isEmpty
              ? const _EmptyState()
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    ...ranked.map((e) => _FallCard(
                          entry: e,
                          sourceClipTitle: clipTitle(e.sourceClipId),
                          onVote: (fire, stoke) =>
                              widget.repository.vote(e.id, fire: fire, stoke: stoke),
                          onReportInjury: () => _confirmReportInjury(context, e.id),
                        )),
                    if (removed.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('REMOVED — INJURY REPORTED',
                            style: TextStyle(color: BinnacleColors.orange, fontSize: 11)),
                      ),
                      ...removed.map((e) => _FallCard(
                            entry: e,
                            sourceClipTitle: clipTitle(e.sourceClipId),
                            onVote: null,
                            onReportInjury: null,
                          )),
                    ],
                  ],
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEntrySheet(context),
            icon: const Icon(Icons.add),
            label: const Text('Submit a fall'),
          ),
        );
      },
    );
  }

  Future<void> _confirmReportInjury(BuildContext context, String entryId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: BinnacleColors.navy,
        title: const Text('Report this as an injury?'),
        content: const Text(
          'Per the safety rule, any clip showing a fall that caused injury is '
          'removed from the board. This cannot be undone from the app.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: BinnacleColors.orange),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    if (ok == true) widget.repository.flagInjury(entryId);
  }

  void _openEntrySheet(BuildContext context) {
    showGlassBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EntrySheet(repository: widget.repository),
    );
  }
}

class _FallCard extends StatelessWidget {
  final FallEntry entry;
  final String? sourceClipTitle;
  final void Function(bool fire, bool stoke)? onVote;
  final VoidCallback? onReportInjury;
  const _FallCard({
    required this.entry,
    required this.sourceClipTitle,
    required this.onVote,
    required this.onReportInjury,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: entry.injuryFlagged ? BinnacleColors.navyRaised : BinnacleColors.navy,
        borderRadius: BorderRadius.circular(12),
        border: entry.injuryFlagged ? Border.all(color: BinnacleColors.orange.withValues(alpha: 0.4)) : null,
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.riderName, style: Theme.of(context).textTheme.titleMedium),
              Row(children: [
                const Icon(Icons.videocam_outlined, size: 12, color: BinnacleColors.tealBright),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    sourceClipTitle == null ? 'Verified capture' : 'Verified capture · $sourceClipTitle',
                    style: BinnacleTheme.mono(size: 10, color: BinnacleColors.tealBright),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ],
          ),
        ),
        if (onVote != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            _VoteBtn(icon: '🔥', count: entry.fireVotes, onTap: () => onVote!(true, false)),
            _VoteBtn(icon: '🤙', count: entry.stokeVotes, onTap: () => onVote!(false, true)),
          ]),
        if (onReportInjury != null)
          IconButton(
            icon: const Icon(Icons.report_outlined, size: 18, color: BinnacleColors.orange),
            onPressed: onReportInjury,
            tooltip: 'Report injury',
          ),
      ]),
    );
  }
}

class _VoteBtn extends StatelessWidget {
  final String icon;
  final int count;
  final VoidCallback onTap;
  const _VoteBtn({required this.icon, required this.count, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            Text('$count', style: BinnacleTheme.mono(size: 9)),
          ]),
        ),
      );
}

/// Submission is picking real footage, not filling out a form: a free-typed
/// rider name plus a self-ticked "rider signaled OK" checkbox let anyone
/// claim anything with no connection to what actually happened on the
/// water. Consent to appear on this board is part of the account-level
/// user agreement made at sign-up — nothing to re-confirm here.
class _EntrySheet extends StatelessWidget {
  final FallRepository repository;
  const _EntrySheet({required this.repository});

  @override
  Widget build(BuildContext context) {
    final clips = context.watch<ClipRepository>().clips.where((c) => c.kind == ClipKind.fall).toList();

    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Submit a fall', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Pick footage captured on Vision or your phone. Consent to appear '
            'on this board is part of your account agreement — nothing more '
            'to confirm here.',
            style: TextStyle(color: BinnacleColors.slate, fontSize: 11.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (clips.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No fall footage in your Library yet.',
                  style: TextStyle(color: BinnacleColors.slateDim, fontSize: 12)),
            )
          else
            ...clips.map((c) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.videocam_outlined, color: BinnacleColors.tealBright),
                  title: Text(c.title, style: const TextStyle(fontSize: 13.5)),
                  subtitle: Text('${c.duration.inSeconds}s', style: BinnacleTheme.mono(size: 10.5)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _submitFromClip(context, c),
                )),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _importAndSubmit(context),
              icon: const Icon(Icons.upload_outlined),
              label: const Text('Import from Vision or phone'),
            ),
          ),
        ],
      ),
    );
  }

  void _submitFromClip(BuildContext context, Clip clip) {
    // sourceClipId is always populated here — submit() throws
    // MissingSourceClip as a backstop regardless, per the "don't rely on
    // the UI alone" discipline used for role enforcement elsewhere.
    try {
      repository.submit(FallEntry(
        id: 'fall-${DateTime.now().millisecondsSinceEpoch}',
        riderId: clip.riderId,
        riderName: _displayName(clip.riderId),
        sourceClipId: clip.id,
        submittedAt: DateTime.now(),
      ));
      Navigator.of(context).pop();
    } on MissingSourceClip {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot submit without a real captured clip.')),
      );
    }
  }

  void _importAndSubmit(BuildContext context) {
    final clip = context.read<ClipRepository>().importFallClip();
    _submitFromClip(context, clip);
  }

  String _displayName(String riderId) =>
      riderId.isEmpty ? 'Unknown rider' : riderId[0].toUpperCase() + riderId.substring(1);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const BinnacleEmptyState(
        icon: Icons.videocam_outlined,
        title: 'No falls yet',
        subtitle: 'Wipeouts count too —\nsubmit real footage from Vision or your phone.',
        accent: BinnacleColors.orange,
      );
}
