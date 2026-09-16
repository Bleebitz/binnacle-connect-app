// Best Falls leaderboard. Community-scored, with a real safety rule this
// model enforces structurally rather than just documenting:
//
//   "Any clip showing a fall that caused injury is removed."
//
// This used to also gate submission on a second, in-app "rider signaled OK
// (both arms up)" checkbox the SUBMITTER manually ticked next to a
// free-typed rider name — i.e. anyone could claim anything, with no
// connection to what actually happened on the water, and it duplicated
// consent that belongs at account creation, not re-litigated per
// submission. Fixed per product direction: submission now requires a real
// captured clip (Vision or phone — see sourceClipId), and consent to
// appear on this board lives in the account-level user agreement made at
// sign-up (see the consent design doc in Drive), not an in-app checkbox.
//
// The safety mechanism that remains:
//   POST-HOC REMOVAL, for a genuine injury discovered later. Modeled as a
//   soft-remove (injuryFlagged = true), not a hard delete — consistent
//   with the evidence-continuity discipline used throughout this project
//   (nothing gets silently deleted; a removed entry stays visible as
//   removed, with the reason, rather than vanishing). Flagged entries are
//   excluded from the ranked board and shown separately.

import 'package:flutter/foundation.dart';

class FallEntry {
  final String id;
  final String riderId;
  final String riderName;
  final String sourceClipId; // the real captured footage this entry is built from
  final int fireVotes;
  final int stokeVotes;
  final bool injuryFlagged;
  final DateTime submittedAt;

  const FallEntry({
    required this.id,
    required this.riderId,
    required this.riderName,
    required this.sourceClipId,
    this.fireVotes = 0,
    this.stokeVotes = 0,
    this.injuryFlagged = false,
    required this.submittedAt,
  });

  int get voteScore => fireVotes + stokeVotes;

  FallEntry copyWith({int? fireVotes, int? stokeVotes, bool? injuryFlagged}) => FallEntry(
        id: id, riderId: riderId, riderName: riderName,
        sourceClipId: sourceClipId,
        fireVotes: fireVotes ?? this.fireVotes,
        stokeVotes: stokeVotes ?? this.stokeVotes,
        injuryFlagged: injuryFlagged ?? this.injuryFlagged,
        submittedAt: submittedAt,
      );
}

/// Thrown when submit() is called for an entry with no real source clip.
/// The caller should not be able to reach this in normal UI flow — the
/// entry sheet only ever offers real clips to pick from, or a fresh import
/// — but the repository refuses it independently, the same "don't rely on
/// the UI alone" discipline used for role enforcement in
/// control_channel_service.
class MissingSourceClip implements Exception {
  @override
  String toString() => 'MissingSourceClip: cannot submit a Best Falls entry '
      'without a real captured clip (Vision or phone) behind it.';
}

class FallRepository extends ChangeNotifier {
  final List<FallEntry> _entries = [];
  List<FallEntry> get entries => List.unmodifiable(_entries);

  void submit(FallEntry e) {
    if (e.sourceClipId.isEmpty) {
      throw MissingSourceClip();
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
