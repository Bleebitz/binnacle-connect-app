import 'package:flutter/material.dart';
import '../../core/models/wake_entry.dart';
import '../theme/binnacle_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_sheet.dart';

class KingOfWakeScreen extends StatefulWidget {
  final WakeRepository repository;
  const KingOfWakeScreen({super.key, required this.repository});

  @override
  State<KingOfWakeScreen> createState() => _KingOfWakeScreenState();
}

class _KingOfWakeScreenState extends State<KingOfWakeScreen> {
  WakeDiscipline _discipline = WakeDiscipline.surf;
  EntryDivision _division = EntryDivision.open;
  String _classLabel = 'A';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        final classes = KingOfWakeClasses.classesFor(_discipline);
        final board = widget.repository.board(_discipline, _classLabel, _division);

        return Scaffold(
          appBar: AppBar(
            title: const Text('King of Wake'),
            actions: [
              TextButton(
                onPressed: () => _showRules(context),
                child: const Text('📋 Rules', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          body: Column(
            children: [
              _DisciplineToggle(
                discipline: _discipline,
                onChanged: (d) => setState(() {
                  _discipline = d;
                  _classLabel = KingOfWakeClasses.classesFor(d).first.label;
                }),
              ),
              _ClassAndDivisionRow(
                classes: classes,
                selectedClass: _classLabel,
                division: _division,
                onClassChanged: (c) => setState(() => _classLabel = c),
                onDivisionChanged: (d) => setState(() => _division = d),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (board.ranked.isEmpty && board.unranked.isEmpty)
                      const _EmptyBoard()
                    else ...[
                      ...board.ranked.asMap().entries.map((kv) => _EntryCard(
                            entry: kv.value,
                            rank: kv.key + 1,
                            onVote: (fire, stoke) => widget.repository
                                .vote(kv.value.id, fire: fire, stoke: stoke),
                          )),
                      if (board.unranked.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('UNVERIFIED — never prize eligible',
                              style: TextStyle(color: BinnacleColors.slate, fontSize: 11)),
                        ),
                        ...board.unranked.map((e) => _EntryCard(
                              entry: e,
                              rank: null,
                              onVote: (fire, stoke) =>
                                  widget.repository.vote(e.id, fire: fire, stoke: stoke),
                            )),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEntrySheet(context),
            icon: const Icon(Icons.add),
            label: const Text('Enter'),
          ),
        );
      },
    );
  }

  void _showRules(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: BinnacleColors.navy,
        title: const Text('King of Wake — how scoring works'),
        content: const Text(
          'GPS speed is measured and is the real score within a class. '
          'Community votes break ties and, in the Pro division, gate whether '
          'an entry appears on the ranked board at all — 10 votes minimum. '
          'Boat make/model and division are self-declared and are not '
          'verified; they classify an entry, they never score it. Speed IS '
          'GPS-verified.',
          style: TextStyle(height: 1.5, fontSize: 13),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _openEntrySheet(BuildContext context) {
    showGlassBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EntrySheet(
        discipline: _discipline,
        repository: widget.repository,
      ),
    );
  }
}

class _DisciplineToggle extends StatelessWidget {
  final WakeDiscipline discipline;
  final void Function(WakeDiscipline) onChanged;
  const _DisciplineToggle({required this.discipline, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: SegmentedButton<WakeDiscipline>(
        segments: const [
          ButtonSegment(value: WakeDiscipline.surf, label: Text('Surf wave')),
          ButtonSegment(value: WakeDiscipline.ramp, label: Text('Wakeboard ramp')),
        ],
        selected: {discipline},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _ClassAndDivisionRow extends StatelessWidget {
  final List<SpeedClass> classes;
  final String selectedClass;
  final EntryDivision division;
  final void Function(String) onClassChanged;
  final void Function(EntryDivision) onDivisionChanged;
  const _ClassAndDivisionRow({
    required this.classes,
    required this.selectedClass,
    required this.division,
    required this.onClassChanged,
    required this.onDivisionChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Two rows, not one — class chips ("A · 9.5-10.5 mph", etc.) plus a
    // spacer plus a division dropdown genuinely overflow a normal phone
    // width in a single Row. Caught by a widget test, not visible in
    // dart analyze. The chip row scrolls horizontally in case a discipline
    // ever gets a 4th class; the division control gets its own row so it
    // never competes with the chips for space.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: classes
                  .map((c) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                              '${c.label} · ${c.minMph.toStringAsFixed(1)}-${c.maxMph.toStringAsFixed(1)} mph'),
                          selected: selectedClass == c.label,
                          onSelected: (_) => onClassChanged(c.label),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Text('Division', style: TextStyle(fontSize: 12, color: BinnacleColors.slate)),
            const SizedBox(width: 10),
            DropdownButton<EntryDivision>(
              value: division,
              items: const [
                DropdownMenuItem(value: EntryDivision.open, child: Text('Open')),
                DropdownMenuItem(value: EntryDivision.pro, child: Text('Pro')),
              ],
              onChanged: (v) => v == null ? null : onDivisionChanged(v),
            ),
          ]),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final WakeEntry entry;
  final int? rank;
  final void Function(bool fire, bool stoke) onVote;
  const _EntryCard({required this.entry, required this.rank, required this.onVote});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: BinnacleColors.navy, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        if (rank != null)
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
          )
        else
          const Icon(Icons.hourglass_bottom, size: 20, color: BinnacleColors.slate),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.riderName, style: Theme.of(context).textTheme.titleMedium),
              Text('${entry.boatMake} ${entry.boatModel} · ${entry.gpsSpeedMph.toStringAsFixed(1)} mph GPS',
                  style: BinnacleTheme.mono(size: 10.5)),
              if (entry.division == EntryDivision.pro)
                Text('${entry.voteScore}/${WakeRepository.proVotesToRank} votes to rank',
                    style: BinnacleTheme.mono(size: 9.5, color: BinnacleColors.amber)),
            ],
          ),
        ),
        _VoteButton(icon: '🔥', count: entry.fireVotes, onTap: () => onVote(true, false)),
        _VoteButton(icon: '🤙', count: entry.stokeVotes, onTap: () => onVote(false, true)),
      ]),
    );
  }
}

class _VoteButton extends StatelessWidget {
  final String icon;
  final int count;
  final VoidCallback onTap;
  const _VoteButton({required this.icon, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: BinnacleEmptyState(
          icon: Icons.emoji_events_outlined,
          title: 'No runs on the board',
          subtitle: 'GPS-verified speed leaderboard —\nfirst entry takes the crown.',
          accent: BinnacleColors.amber,
        ),
      );
}

/// Entry form. GPS speed classification updates live as the value is typed,
/// showing which class it lands in (or a clear "between classes" state) —
/// this is the amber/teal live-validation behavior from the original design.
class _EntrySheet extends StatefulWidget {
  final WakeDiscipline discipline;
  final WakeRepository repository;
  const _EntrySheet({required this.discipline, required this.repository});

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  final _name = TextEditingController();
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _speed = TextEditingController();
  EntryDivision _division = EntryDivision.open;
  double? _liveSpeed;

  @override
  void dispose() {
    _name.dispose();
    _make.dispose();
    _model.dispose();
    _speed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cls = _liveSpeed == null ? null : KingOfWakeClasses.classify(widget.discipline, _liveSpeed!);
    final statusColor = _liveSpeed == null
        ? BinnacleColors.slate
        : (cls != null ? BinnacleColors.tealBright : BinnacleColors.amber);
    final statusText = _liveSpeed == null
        ? 'Enter GPS speed to see class'
        : (cls != null ? 'Class ${cls.label}' : 'Not in range for any class');

    return Padding(
      padding: EdgeInsets.only(
          left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter King of Wake', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Rider name')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _make, decoration: const InputDecoration(labelText: 'Boat make'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _model, decoration: const InputDecoration(labelText: 'Boat model'))),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _speed,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'GPS speed (mph)'),
              onChanged: (v) => setState(() => _liveSpeed = double.tryParse(v)),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.circle, size: 8, color: statusColor),
              const SizedBox(width: 6),
              Text(statusText, style: TextStyle(color: statusColor, fontSize: 12)),
            ]),
            const SizedBox(height: 14),
            SegmentedButton<EntryDivision>(
              segments: const [
                ButtonSegment(value: EntryDivision.open, label: Text('Open')),
                ButtonSegment(value: EntryDivision.pro, label: Text('Pro')),
              ],
              selected: {_division},
              onSelectionChanged: (s) => setState(() => _division = s.first),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: cls == null ? null : _submit,
                child: const Text('Submit entry'),
              ),
            ),
            if (cls == null && _liveSpeed != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Speed must land inside a class band to enter.',
                    style: TextStyle(color: BinnacleColors.amber, fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    widget.repository.submit(WakeEntry(
      id: 'entry-${DateTime.now().millisecondsSinceEpoch}',
      riderId: 'r0',
      riderName: _name.text.trim().isEmpty ? 'Unnamed rider' : _name.text.trim(),
      discipline: widget.discipline,
      gpsSpeedMph: _liveSpeed!,
      boatMake: _make.text.trim(),
      boatModel: _model.text.trim(),
      division: _division,
      verified: true, // simulated GPS is treated as verified in this scaffold
      submittedAt: DateTime.now(),
    ));
    Navigator.of(context).pop();
  }
}
