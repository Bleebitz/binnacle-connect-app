class Rider {
  final String id;
  final String name;
  final bool biometricConsent; // see Connect_App_Consent_Verification — BIPA-scoped

  const Rider({
    required this.id,
    required this.name,
    this.biometricConsent = false,
  });
}

class CrewSession {
  final String id;
  final String label; // e.g. "Today", "Saturday"
  final String location;
  final List<String> riderIds;
  final List<String> clipIds;
  final Map<String, int> reactions; // emoji -> count

  const CrewSession({
    required this.id,
    required this.label,
    required this.location,
    required this.riderIds,
    required this.clipIds,
    this.reactions = const {},
  });
}
