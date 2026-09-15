import 'package:flutter/material.dart';
import '../../core/models/rider.dart';
import '../theme/binnacle_theme.dart';

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

  void react(String sessionId, String emoji) {
    final i = _sessions.indexWhere((s) => s.id == sessionId);
    if (i == -1) return;
    final s = _sessions[i];
    final reactions = Map<String, int>.from(s.reactions);
    reactions[emoji] = (reactions[emoji] ?? 0) + 1;
    _sessions[i] = CrewSession(
      id: s.id, label: s.label, location: s.location,
      riderIds: s.riderIds, clipIds: s.clipIds, reactions: reactions,
    );
    notifyListeners();
  }
}

class CrewScreen extends StatelessWidget {
  final CrewRepository repository;
  const CrewScreen({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Crew'),
            bottom: const TabBar(tabs: [Tab(text: 'Sessions'), Tab(text: 'People')]),
          ),
          body: TabBarView(children: [
            _SessionsTab(sessions: repository.sessions, onReact: repository.react),
            _PeopleTab(riders: repository.riders, onAdd: repository.addRider),
          ]),
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
      return Center(
        child: Text('No sessions yet — they appear once a highlight is saved on the water.',
            textAlign: TextAlign.center, style: TextStyle(color: BinnacleColors.slate)),
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
                Text(s.label, style: Theme.of(context).textTheme.titleMedium),
                Text(s.location, style: BinnacleTheme.mono(size: 10)),
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Add a rider name'))),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  onAdd(controller.text.trim());
                  controller.clear();
                }
              },
              child: const Text('Add'),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: riders.length,
            itemBuilder: (_, i) => ListTile(
              leading: CircleAvatar(
                backgroundColor: BinnacleColors.teal,
                child: Text(riders[i].name.substring(0, 1)),
              ),
              title: Text(riders[i].name),
              subtitle: riders[i].biometricConsent
                  ? const Text('Identification enabled', style: TextStyle(fontSize: 11))
                  : const Text('No biometric consent on file', style: TextStyle(fontSize: 11)),
            ),
          ),
        ),
      ],
    );
  }
}
