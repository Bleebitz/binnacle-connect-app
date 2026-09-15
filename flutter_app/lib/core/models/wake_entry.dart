import 'package:flutter/foundation.dart';

// King of Wake model and speed-class validation.
// Per the original product design: two divisions (Surf, Ramp), each with
// three GPS speed classes, verified/unverified tiers, and an Open/Pro split
// where Pro requires 10 community votes to rank.

enum WakeDiscipline { surf, ramp }

class SpeedClass {
  final String label;      // "A", "B", "C"
  final double minMph;
  final double maxMph;
  const SpeedClass(this.label, this.minMph, this.maxMph);

  bool contains(double mph) => mph >= minMph && mph <= maxMph;
}

class KingOfWakeClasses {
  // Bands as specified in the original product design — do not renumber
  // without checking Connect_Contest_Rules_Framework_2026-09-04 in Drive,
  // these are referenced there by name.
  static const surf = [
    SpeedClass('A', 9.5, 10.5),
    SpeedClass('B', 10.5, 11.5),
    SpeedClass('C', 11.5, 12.5),
  ];
  static const ramp = [
    SpeedClass('A', 20.0, 21.5),
    SpeedClass('B', 21.5, 23.0),
    SpeedClass('C', 23.0, 24.5),
  ];

  static List<SpeedClass> classesFor(WakeDiscipline d) =>
      d == WakeDiscipline.surf ? surf : ramp;

  /// Returns the matching class for a GPS speed, or null if the speed is
  /// outside the whole A-C range for this discipline. The three bands are
  /// contiguous (A's max equals B's min, etc.) — a boundary value like
  /// exactly 10.5 mph matches the first band checked (A), since classify()
  /// returns on first match. There is no unclassed gap between bands; only
  /// speeds outside the full 9.5-12.5 (surf) or 20-24.5 (ramp) range return
  /// null. An earlier version of this comment incorrectly claimed a
  /// deliberate gap existed between bands — it didn't, this was caught by a
  /// failing widget test that assumed gap behavior the code never had.
  static SpeedClass? classify(WakeDiscipline d, double gpsSpeedMph) {
    for (final c in classesFor(d)) {
      if (c.contains(gpsSpeedMph)) return c;
    }
    return null;
  }
}

enum EntryDivision { open, pro }

class WakeEntry {
  final String id;
  final String riderId;
  final String riderName;
  final WakeDiscipline discipline;
  final double gpsSpeedMph;      // measured, not declared — see F-43 in Drive
  final String boatMake;         // self-declared — see F-45
  final String boatModel;        // self-declared — see F-45
  final EntryDivision division;
  final bool verified;           // true only if capture conditions met — see notes
  final int fireVotes;
  final int stokeVotes;          // 🤙
  final DateTime submittedAt;

  const WakeEntry({
    required this.id,
    required this.riderId,
    required this.riderName,
    required this.discipline,
    required this.gpsSpeedMph,
    required this.boatMake,
    required this.boatModel,
    required this.division,
    this.verified = false,
    this.fireVotes = 0,
    this.stokeVotes = 0,
    required this.submittedAt,
  });

  SpeedClass? get speedClass => KingOfWakeClasses.classify(discipline, gpsSpeedMph);

  /// Community votes are the tie-breaker within a class, not the primary
  /// score — GPS speed within a class is. See F-43: declared/voted data
  /// classifies and breaks ties, it never overrides a measured value.
  int get voteScore => fireVotes + stokeVotes;

  WakeEntry copyWith({int? fireVotes, int? stokeVotes}) => WakeEntry(
        id: id, riderId: riderId, riderName: riderName, discipline: discipline,
        gpsSpeedMph: gpsSpeedMph, boatMake: boatMake, boatModel: boatModel,
        division: division, verified: verified,
        fireVotes: fireVotes ?? this.fireVotes,
        stokeVotes: stokeVotes ?? this.stokeVotes,
        submittedAt: submittedAt,
      );
}

/// King of Wake repository. Per Connect_Contest_Rules_Framework_2026-09-04:
/// GPS speed is measured and is the real score within a class; votes break
/// ties and gate Pro-division ranking, they never override a measured
/// value. See F-43 (Drive) — declared/voted data classifies, it doesn't score.
class WakeRepository extends ChangeNotifier {
  final List<WakeEntry> _entries = [];
  List<WakeEntry> get entries => List.unmodifiable(_entries);

  static const int proVotesToRank = 10;

  void submit(WakeEntry e) {
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

  /// Entries for one discipline/class, split into what the board actually
  /// shows: verified-and-ranked, and everything held back from the main
  /// board (unverified, or Pro entries short of the vote threshold).
  ({List<WakeEntry> ranked, List<WakeEntry> unranked}) board(
      WakeDiscipline d, String classLabel, EntryDivision division) {
    final inClass = _entries.where((e) =>
        e.discipline == d &&
        e.division == division &&
        e.speedClass?.label == classLabel);

    final ranked = <WakeEntry>[];
    final unranked = <WakeEntry>[];
    for (final e in inClass) {
      final proGated = e.division == EntryDivision.pro && e.voteScore < proVotesToRank;
      if (e.verified && !proGated) {
        ranked.add(e);
      } else {
        unranked.add(e);
      }
    }
    // Measured GPS speed is the real score within a class — ranked strictly
    // by speed, votes only break an exact tie.
    ranked.sort((a, b) {
      final bySpeed = b.gpsSpeedMph.compareTo(a.gpsSpeedMph);
      return bySpeed != 0 ? bySpeed : b.voteScore.compareTo(a.voteScore);
    });
    return (ranked: ranked, unranked: unranked);
  }
}
