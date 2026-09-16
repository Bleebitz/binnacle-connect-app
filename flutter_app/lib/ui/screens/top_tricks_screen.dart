import 'package:flutter/material.dart';
import '../../core/models/trick_entry.dart';
import '../theme/binnacle_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_sheet.dart';

/// Top Tricks. Community-vote-only ranking — see the design note in
/// trick_entry.dart for why (no real trick classifier exists yet).
class TopTricksScreen extends StatefulWidget {
  final TrickRepository repository;
  const TopTricksScreen({super.key, required this.repository});

  @override
  State<TopTricksScreen> createState() => _TopTricksScreenState();
}

class _TopTricksScreenState extends State<TopTricksScreen> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        final ranked = widget.repository.ranked;
        return Scaffold(
          appBar: AppBar(title: const Text('Top Tricks')),
          body: ranked.isEmpty
              ? const BinnacleEmptyState(
                  icon: Icons.auto_awesome_outlined,
                  title: 'No tricks logged',
                  subtitle: 'Land something clean and log it —\ncommunity votes decide who\'s got the best trick.',
                  accent: BinnacleColors.amber,
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: ranked.length,
                  itemBuilder: (_, i) => _TrickCard(
                    entry: ranked[i],
                    rank: i + 1,
                    onVote: (fire, stoke) =>
                        widget.repository.vote(ranked[i].id, fire: fire, stoke: stoke),
                  ),
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEntrySheet(context),
            icon: const Icon(Icons.add),
            label: const Text('Log a trick'),
          ),
        );
      },
    );
  }

  void _openEntrySheet(BuildContext context) {
    showGlassBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EntrySheet(repository: widget.repository),
    );
  }
}

class _TrickCard extends StatelessWidget {
  final TrickEntry entry;
  final int rank;
  final void Function(bool fire, bool stoke) onVote;
  const _TrickCard({required this.entry, required this.rank, required this.onVote});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: BinnacleColors.navy, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(
          width: 28, height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: rank == 1 ? BinnacleColors.amber : BinnacleColors.navyRaised,
            shape: BoxShape.circle,
          ),
          child: Text('$rank', style: TextStyle(
              fontWeight: FontWeight.w700,
              color: rank == 1 ? BinnacleColors.navyDeep : BinnacleColors.offWhite)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.trickName, style: Theme.of(context).textTheme.titleMedium),
              Text(entry.riderName, style: BinnacleTheme.mono(size: 10.5)),
            ],
          ),
        ),
        _VoteButtons(
          fireVotes: entry.fireVotes,
          stokeVotes: entry.stokeVotes,
          onVote: onVote,
        ),
      ]),
    );
  }
}

/// Shared vote-button pair. Split out here rather than duplicated across
/// Top Tricks / Best Falls / King of Wake's own _VoteButton, since the
/// third copy is what made the duplication worth naming.
class _VoteButtons extends StatelessWidget {
  final int fireVotes;
  final int stokeVotes;
  final void Function(bool fire, bool stoke) onVote;
  const _VoteButtons({required this.fireVotes, required this.stokeVotes, required this.onVote});

  @override
  Widget build(BuildContext context) {
    Widget btn(String icon, int count, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              Text('$count', style: BinnacleTheme.mono(size: 10)),
            ]),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      btn('🔥', fireVotes, () => onVote(true, false)),
      btn('🤙', stokeVotes, () => onVote(false, true)),
    ]);
  }
}

class _EntrySheet extends StatefulWidget {
  final TrickRepository repository;
  const _EntrySheet({required this.repository});

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final _name = TextEditingController();
  final _trick = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _trick.dispose();
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
          Text('Log a trick', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Rider name')),
          const SizedBox(height: 10),
          TextField(
            controller: _trick,
            decoration: const InputDecoration(labelText: 'Trick name'),
            // Rebuilds on every keystroke so the Submit button's enabled
            // state below actually reacts to typing — without this,
            // onPressed reads _trick.text once at initial build and never
            // updates, so the button stays permanently disabled no matter
            // what's typed. Caught by reasoning through the flow before
            // writing a test, not by a test itself.
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _trick.text.trim().isEmpty ? null : _submit,
              child: const Text('Submit'),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    widget.repository.submit(TrickEntry(
      id: 'trick-${DateTime.now().millisecondsSinceEpoch}',
      riderId: 'r0',
      riderName: _name.text.trim().isEmpty ? 'Unnamed rider' : _name.text.trim(),
      trickName: _trick.text.trim(),
      submittedAt: DateTime.now(),
    ));
    Navigator.of(context).pop();
  }
}

