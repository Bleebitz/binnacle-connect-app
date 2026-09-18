// Live entitlement — architecture §11.2/§11.4: free is exactly one
// simultaneous destination, paid tiers unlock more. INJECTED, never a
// hard-coded logged-in paid user: there is no real Binnacle Billing service
// yet (architecture §16's "Binnacle Billing" is unbuilt), so the only
// implementation shipped here is a static, always-Free default. A future
// real billing-backed EntitlementService can replace this without any
// change to LiveBroadcastService or the UI that reads it.

import 'package:flutter/foundation.dart';

enum SubscriptionTier { free, ride, creator, creatorPlus }

extension SubscriptionTierX on SubscriptionTier {
  String get label => switch (this) {
        SubscriptionTier.free => 'Free',
        SubscriptionTier.ride => 'Ride',
        SubscriptionTier.creator => 'Creator',
        SubscriptionTier.creatorPlus => 'Creator+',
      };
}

/// §11.2/§11.4's live-destination limits. Only [maxSimultaneousDestinations]
/// is load-bearing for BIN-38; storage/retention/AI-credit entitlements
/// belong to later phases (§11.4, §26) and are not modeled here.
class LiveEntitlement {
  final SubscriptionTier tier;
  final int maxSimultaneousDestinations;

  const LiveEntitlement({required this.tier, required this.maxSimultaneousDestinations});

  static const free = LiveEntitlement(tier: SubscriptionTier.free, maxSimultaneousDestinations: 1);

  /// §11.4's approximate target — "Creator: ... target approximately three
  /// simultaneous destinations." An illustrative product-design target from
  /// the architecture doc, not a billed/verified quota. Only reachable by
  /// explicitly injecting this entitlement (e.g. in tests) — never surfaced
  /// as a real logged-in user's plan; see module comment.
  static const creator = LiveEntitlement(tier: SubscriptionTier.creator, maxSimultaneousDestinations: 3);
}

abstract class EntitlementService extends ChangeNotifier {
  LiveEntitlement get liveEntitlement;
}

/// The only implementation shipped: always Free. There is no real
/// Binnacle Identity/Billing service to check a real subscription against
/// (architecture §16) — reporting anything else here would be exactly the
/// fabricated paid-user state BIN-38 forbids. Real billing integration
/// replaces this class, not the interface it implements.
class StaticEntitlementService extends EntitlementService {
  final LiveEntitlement _entitlement;
  StaticEntitlementService({LiveEntitlement entitlement = LiveEntitlement.free}) : _entitlement = entitlement;

  @override
  LiveEntitlement get liveEntitlement => _entitlement;
}
