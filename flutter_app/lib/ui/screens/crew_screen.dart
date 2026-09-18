import 'package:flutter/material.dart';
import '../../core/models/rider.dart';
import '../theme/binnacle_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/solid_panel.dart';

class CrewRepository extends ChangeNotifier {
  final List<Rider> _riders = [const Rider(id: 'r0', name: 'You')];
  final List<CrewSession> _sessions = [];

  List<Rider> get riders => List.unmodifiable(_riders);
  List<CrewSession> get sessions => List.unmodifiable(_sessions);

  void addRider(String name) {
    _riders.add(Rider(id: 'r${_riders.length}', name: name));
    notifyListeners();
  }

  void addSession(CrewSession s) {
    _sessions.insert(0, s);
    notifyListeners();
  }

  /// Real "publish" destination for Community's Post a highlight flow —
  /// there is no external identity/social backend (BIN-46/BIN-40 are both
  /// Todo), so "publish to Crew" is the only genuine audience today: it
  /// attaches [clipId] to the most recent session (creating one first if
  /// none exists yet), visible to this Crew immediately, with no network
  /// call and no fabricated "posted publicly" state.
  void postHighlight(String clipId) {
    if (_sessions.isEmpty) {
      _sessions.insert(
        0,
        CrewSession(
          id: 'session-${DateTime.now().microsecondsSinceEpoch}',
          label: 'Today',
          location: '',
          riderIds: const [],
          clipIds: [clipId],
        ),
      );
    } else if (!_sessions.first.clipIds.contains(clipId)) {
      final s = _sessions.first;
      _sessions[0] = CrewSession(
        id: s.id,
        label: s.label,
        location: s.location,
        riderIds: s.riderIds,
        clipIds: [...s.clipIds, clipId],
        reactions: s.reactions,
      );
    }
    notifyListeners();
  }

  void react(String sessionId, String emoji) {
    final i = _sessions.indexWhere((s) => s.id == sessionId);
    if (i == -1) return;
    final s = _sessions[i];
    final reactions = Map<String, int>.from(s.reactions);
    reactions[emoji] = (reactions[emoji] ?? 0) + 1;
    _sessions[i] = CrewSession(
      id: s.id,
      label: s.label,
      location: s.location,
      riderIds: s.riderIds,
      clipIds: s.clipIds,
      reactions: reactions,
    );
    notifyListeners();
  }
}

/// Body-only content — no Scaffold/AppBar of its own, so it can be embedded
/// as one tab of CommunityScreen rather than owning a full screen. See that
/// file's module comment for why Crew moved off the primary bottom nav.
class CrewScreen extends StatelessWidget {
  final CrewRepository repository;
  const CrewScreen({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) => DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const Material(
              color: BinnacleColors.navy,
              child: TabBar(
                tabs: [Tab(text: 'Sessions'), Tab(text: 'People')],
                labelColor: BinnacleColors.tealBright,
                unselectedLabelColor: BinnacleColors.slateLight,
                indicatorColor: BinnacleColors.tealBright,
              ),
            ),
            Expanded(
              child: TabBarView(children: [
                _SessionsTab(
                    sessions: repository.sessions, onReact: repository.react),
                _PeopleTab(
                    riders: repository.riders, onAdd: repository.addRider),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionsTab extends StatelessWidget {
  final List<CrewSession> sessions;
  final void Function(String, String) onReact;
  const _SessionsTab({required this.sessions, required this.onReact});

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const SolidPanel(
        margin: EdgeInsets.all(20),
        child: Center(
          child: SingleChildScrollView(
            child: BinnacleEmptyState(
              icon: Icons.directions_boat_filled_outlined,
              title: 'No sessions yet',
              subtitle:
                  'They show up automatically\nonce a highlight is saved on the water.',
              accent: BinnacleColors.tealBright,
              titleStyle: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: BinnacleColors.offWhite),
              subtitleStyle: TextStyle(
                  fontSize: 14, height: 1.4, color: BinnacleColors.slateLight),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: sessions.length,
      itemBuilder: (_, i) {
        final s = sessions[i];
        return Card(
          color: BinnacleColors.navy,
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: BinnacleColors.offWhite)),
                if (s.location.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(s.location,
                      style: BinnacleTheme.mono(
                          size: 14, color: BinnacleColors.slateLight)),
                ],
                if (s.clipIds.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.movie_creation_outlined,
                        size: 13, color: BinnacleColors.tealBright),
                    const SizedBox(width: 4),
                    Text(
                      '${s.clipIds.length} highlight${s.clipIds.length == 1 ? '' : 's'} posted',
                      style: BinnacleTheme.mono(size: 11.5, color: BinnacleColors.tealBright),
                    ),
                  ]),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['🔥', '🤙', '👏', '💀']
                      .map((e) => ActionChip(
                            label: Text('$e ${s.reactions[e] ?? 0}'),
                            onPressed: () => onReact(s.id, e),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PeopleTab extends StatelessWidget {
  final List<Rider> riders;
  final void Function(String) onAdd;
  const _PeopleTab({required this.riders, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();
    return SolidPanel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(
                    color: BinnacleColors.offWhite, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Add a rider name',
                  hintStyle: const TextStyle(color: BinnacleColors.slateLight),
                  filled: true,
                  fillColor: BinnacleColors.navyRaised,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: BinnacleColors.offWhite.withValues(alpha: 0.15)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: BinnacleColors.tealBright, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: BinnacleColors.tealBright,
                foregroundColor: BinnacleColors.navyDeep,
              ),
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  onAdd(controller.text.trim());
                  controller.clear();
                }
              },
              child: const Text('Add'),
            ),
          ]),
          Expanded(
            child: ListView.builder(
              itemCount: riders.length,
              itemBuilder: (_, i) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: BinnacleColors.teal,
                  child: Text(riders[i].name.isEmpty
                      ? '?'
                      : riders[i].name.substring(0, 1)),
                ),
                title: Text(riders[i].name,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: BinnacleColors.offWhite)),
                subtitle: Text(
                  riders[i].biometricConsent
                      ? 'Identification enabled'
                      : 'No biometric consent on file',
                  style: const TextStyle(
                      fontSize: 14, color: BinnacleColors.slateLight),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
