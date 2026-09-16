import 'package:flutter/material.dart';
import '../../core/models/fall_entry.dart';
import '../theme/binnacle_theme.dart';
import '../widgets/empty_state.dart';

/// Best Falls. Two-part safety rule enforced by fall_entry.dart's
/// FallRepository, not just by this UI — see that file's module comment.
/// This screen's job is to make both parts visible: the entry sheet cannot
/// be submitted without the rider-OK checkbox, and removed-for-injury
/// entries stay visible in their own section rather than disappearing.
class BestFallsScreen extends StatefulWidget {
  final FallRepository repository;
  const BestFallsScreen({super.key, required this.repository});

  @override
  State<BestFallsScreen> createState() => _BestFallsScreenState();
}

class _BestFallsScreenState extends State<BestFallsScreen> {
  @override
  Widget build(BuildContext context) {
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
                      ...removed.map((e) => _FallCard(entry: e, onVote: null, onReportInjury: null)),
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: BinnacleColors.navy,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => _EntrySheet(repository: widget.repository),
    );
  }
}

class _FallCard extends StatelessWidget {
  final FallEntry entry;
  final void Function(bool fire, bool stoke)? onVote;
  final VoidCallback? onReportInjury;
  const _FallCard({required this.entry, required this.onVote, required this.onReportInjury});

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
                const Icon(Icons.check_circle_outline, size: 12, color: BinnacleColors.tealBright),
                const SizedBox(width: 4),
                Text('Rider OK signaled', style: BinnacleTheme.mono(size: 10, color: BinnacleColors.tealBright)),
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

class _EntrySheet extends StatefulWidget {
  final FallRepository repository;
  const _EntrySheet({required this.repository});

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final _name = TextEditingController();
  bool _riderOk = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Submit a fall', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Rider name')),
          const SizedBox(height: 10),
          // The safety gate. Unticking this must be the ONLY way this entry
          // is missing riderOkSignaled — there is no other path to Submit.
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _riderOk,
            // setState here is what makes the Submit button below actually
            // react to the checkbox — the exact bug class caught and fixed
            // in Top Tricks' entry sheet, applied here before it could ship
            // broken a second time.
            onChanged: (v) => setState(() => _riderOk = v ?? false),
            title: const Text(
              'Rider signaled OK (both arms up) at the time of the fall',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _riderOk ? _submit : null,
              child: const Text('Submit'),
            ),
          ),
          if (!_riderOk)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Cannot submit without the rider-OK signal — this is the '
                'qualifying gate for Best Falls, not optional.',
                style: TextStyle(color: BinnacleColors.amber, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  void _submit() {
    // The button is disabled unless _riderOk is true, so this branch should
    // be unreachable with riderOkSignaled false — submit() throws
    // MissingRiderOkSignal as a backstop regardless, per the "don't rely on
    // the UI alone" discipline used for role enforcement elsewhere. Caught
    // here defensively rather than trusted to never happen.
    try {
      widget.repository.submit(FallEntry(
        id: 'fall-${DateTime.now().millisecondsSinceEpoch}',
        riderId: 'r0',
        riderName: _name.text.trim().isEmpty ? 'Unnamed rider' : _name.text.trim(),
        riderOkSignaled: _riderOk,
        submittedAt: DateTime.now(),
      ));
      Navigator.of(context).pop();
    } on MissingRiderOkSignal {
      // Should be unreachable given the disabled-button gate above. If this
      // ever fires, something upstream broke the gate — fail loudly rather
      // than silently swallowing it.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot submit without rider-OK signal.')),
      );
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const BinnacleEmptyState(
        icon: Icons.videocam_outlined,
        title: 'No falls yet',
        subtitle: 'Wipeouts count too —\nrider-OK required before it hits the board.',
        accent: BinnacleColors.orange,
      );
}
