// Best Falls leaderboard. Community-scored, with a real safety rule this
// model enforces structurally rather than just documenting:
//
//   "Any clip showing a fall that caused injury, or where the rider did not
//    signal OK, is removed. The both-arms-up 'rider OK' hand signal is the
//    qualifying gate."
//
// Two separate mechanisms, matching the two clauses above:
//   1. QUALIFYING GATE, at submission. FallRepository.submit() REJECTS an
//      entry outright if riderOkSignaled is false — it never enters the
//      list at all. This mirrors how King of Wake's entry sheet disables
//      Submit until a speed lands in a valid class: the invalid case can't
//      be constructed in the first place, not merely hidden in the UI.
//   2. POST-HOC REMOVAL, for a genuine injury discovered later. Modeled as
//      a soft-remove (injuryFlagged = true), not a hard delete — consistent
//      with the evidence-continuity discipline used throughout this project
//      (nothing gets silently deleted; a removed entry stays visible as
//      removed, with the reason, rather than vanishing). Flagged entries
//      are excluded from the ranked board and shown separately.

import 'package:flutter/foundation.dart';

class FallEntry {
  final String id;
  final String riderId;
  final String riderName;
  final bool riderOkSignaled; // the qualifying gate itself
  final int fireVotes;
  final int stokeVotes;
  final bool injuryFlagged;
  final DateTime submittedAt;

  const FallEntry({
    required this.id,
    required this.riderId,
    required this.riderName,
    required this.riderOkSignaled,
    this.fireVotes = 0,
    this.stokeVotes = 0,
    this.injuryFlagged = false,
    required this.submittedAt,
  });

  int get voteScore => fireVotes + stokeVotes;

  FallEntry copyWith({int? fireVotes, int? stokeVotes, bool? injuryFlagged}) => FallEntry(
        id: id, riderId: riderId, riderName: riderName,
        riderOkSignaled: riderOkSignaled,
        fireVotes: fireVotes ?? this.fireVotes,
        stokeVotes: stokeVotes ?? this.stokeVotes,
        injuryFlagged: injuryFlagged ?? this.injuryFlagged,
        submittedAt: submittedAt,
      );
}

/// Thrown when submit() is called for an entry that never had the rider-OK
/// signal. The caller should not be able to reach this in normal UI flow —
/// the entry sheet disables submission until the signal is confirmed — but
/// the repository refuses it independently, the same "don't rely on the UI
/// alone" discipline used for role enforcement in control_channel_service.
class MissingRiderOkSignal implements Exception {
  @override
  String toString() => 'MissingRiderOkSignal: cannot submit a Best Falls '
      'entry without the rider-OK hand signal confirmed at capture.';
}

class FallRepository extends ChangeNotifier {
  final List<FallEntry> _entries = [];
  List<FallEntry> get entries => List.unmodifiable(_entries);

  void submit(FallEntry e) {
    if (!e.riderOkSignaled) {
      throw MissingRiderOkSignal();
    }
    _entries.add(e);
    notifyListeners();
  }

  void vote(String entryId, {bool fire = false, bool stoke = false}) {
    final i = _entries.indexWhere((e) => e.id == entryId);
    if (i == -1) return;
    final e = _entries[i];
    if (e.injuryFlagged) return; // votes don't matter once removed
    _entries[i] = e.copyWith(
      fireVotes: fire ? e.fireVotes + 1 : null,
      stokeVotes: stoke ? e.stokeVotes + 1 : null,
    );
    notifyListeners();
  }

  /// Any viewer can flag a genuine injury — matches the "community/self
  /// report" pattern already used for clip takedowns elsewhere in the app.
  /// This is the post-hoc removal clause of the safety rule.
  void flagInjury(String entryId) {
    final i = _entries.indexWhere((e) => e.id == entryId);
    if (i == -1) return;
    _entries[i] = _entries[i].copyWith(injuryFlagged: true);
    notifyListeners();
  }

  List<FallEntry> get ranked {
    final list = _entries.where((e) => !e.injuryFlagged).toList();
    list.sort((a, b) => b.voteScore.compareTo(a.voteScore));
    return list;
  }

  List<FallEntry> get removedForInjury =>
      _entries.where((e) => e.injuryFlagged).toList();
}
