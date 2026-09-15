// Riders leaderboard — cumulative season points.
//
// This is deliberately NOT its own repository with its own stored state.
// It's a pure computation over the other three: King of Wake, Top Tricks,
// and Best Falls. There is nowhere for it to drift out of sync with them,
// because it has no state of its own to drift — every rebuild recomputes
// from source. Best Falls entries removed for injury are correctly excluded
// automatically, because .ranked already excludes them upstream; this file
// never has to remember that rule separately.
//
// Grouped by riderName, not riderId. Honest limitation: none of the three
// source repositories populate a meaningful riderId today (WakeEntry hard-
// codes riderId 'r0' for the local user; Trick/Fall entries don't collect
// one at all in the entry sheets). Two different people who happen to type
// the same display name would be merged into one leaderboard row. Fixing
// this needs a real rider-identity system, which doesn't exist yet.

import 'wake_entry.dart';
import 'trick_entry.dart';
import 'fall_entry.dart';

class RiderStanding {
  final String riderName;
  final int totalPoints;
  final int wakeEntries;
  final int trickEntries;
  final int fallEntries;

  const RiderStanding({
    required this.riderName,
    required this.totalPoints,
    required this.wakeEntries,
    required this.trickEntries,
    required this.fallEntries,
  });

  int get totalEntries => wakeEntries + trickEntries + fallEntries;
}

class RidersLeaderboard {
  static List<RiderStanding> compute({
    required WakeRepository wake,
    required TrickRepository trick,
    required FallRepository fall,
  }) {
    final points = <String, int>{};
    final wakeCount = <String, int>{};
    final trickCount = <String, int>{};
    final fallCount = <String, int>{};

    for (final e in wake.entries) {
      // King of Wake's real score is measured GPS speed, not votes (F-43) —
      // but speed has no natural common unit to sum against trick/fall vote
      // counts for a cross-discipline season leaderboard. Using voteScore
      // here for cross-discipline comparability; this does NOT change how
      // King of Wake ranks within itself, only how it contributes to this
      // separate aggregate view.
      points[e.riderName] = (points[e.riderName] ?? 0) + e.voteScore;
      wakeCount[e.riderName] = (wakeCount[e.riderName] ?? 0) + 1;
    }
    for (final e in trick.entries) {
      points[e.riderName] = (points[e.riderName] ?? 0) + e.voteScore;
      trickCount[e.riderName] = (trickCount[e.riderName] ?? 0) + 1;
    }
    for (final e in fall.ranked) { // .ranked, not .entries — excludes injury-flagged
      points[e.riderName] = (points[e.riderName] ?? 0) + e.voteScore;
      fallCount[e.riderName] = (fallCount[e.riderName] ?? 0) + 1;
    }

    final standings = points.keys
        .map((name) => RiderStanding(
              riderName: name,
              totalPoints: points[name]!,
              wakeEntries: wakeCount[name] ?? 0,
              trickEntries: trickCount[name] ?? 0,
              fallEntries: fallCount[name] ?? 0,
            ))
        .toList();
    standings.sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
    return standings;
  }
}
