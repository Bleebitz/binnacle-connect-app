// Top Tricks leaderboard.
//
// DESIGN NOTE, stated explicitly because it fills a gap the original spec
// left open: Track's trick-detection is a toggle in Settings > Detection &
// AI, but no real trick classifier exists yet (no model, no training data —
// see the Track fork tracker items). There is no automated difficulty score
// to rank against. Scoring here is therefore community-vote-only (🔥/🤙),
// same mechanic as Best Falls. If a real trick classifier ships later, this
// is the file to revisit — TrickEntry.difficultyScore is left as a nullable
// field for that, unused for now, so the model doesn't need to change shape
// when it arrives.
//
// Single implicit season. No season id anywhere in this file — every entry
// belongs to "the current season," there's no rollover logic. Documented
// limitation, not an oversight.

import 'package:flutter/foundation.dart';

class TrickEntry {
  final String id;
  final String riderId;
  final String riderName;
  final String trickName;
  final double? difficultyScore; // unused until a real trick classifier exists
  final int fireVotes;
  final int stokeVotes;
  final DateTime submittedAt;

  const TrickEntry({
    required this.id,
    required this.riderId,
    required this.riderName,
    required this.trickName,
    this.difficultyScore,
    this.fireVotes = 0,
    this.stokeVotes = 0,
    required this.submittedAt,
  });

  int get voteScore => fireVotes + stokeVotes;

  TrickEntry copyWith({int? fireVotes, int? stokeVotes}) => TrickEntry(
        id: id, riderId: riderId, riderName: riderName, trickName: trickName,
        difficultyScore: difficultyScore,
        fireVotes: fireVotes ?? this.fireVotes,
        stokeVotes: stokeVotes ?? this.stokeVotes,
        submittedAt: submittedAt,
      );
}

class TrickRepository extends ChangeNotifier {
  final List<TrickEntry> _entries = [];
  List<TrickEntry> get entries => List.unmodifiable(_entries);

  void submit(TrickEntry e) {
    _entries.add(e);
    notifyListeners();
  }

  void vote(String entryId, {bool fire = false, bool stoke = false}) {
    final i = _entries.indexWhere((e) => e.id == entryId);
    if (i == -1) return;
    final e = _entries[i];
    _entries[i] = e.copyWith(
      fireVotes: fire ? e.fireVotes + 1 : null,
      stokeVotes: stoke ? e.stokeVotes + 1 : null,
    );
    notifyListeners();
  }

  /// Ranked purely by community vote score — see the module note on why
  /// there's no measured/automated component yet.
  List<TrickEntry> get ranked {
    final list = List<TrickEntry>.from(_entries);
    list.sort((a, b) => b.voteScore.compareTo(a.voteScore));
    return list;
  }
}
