enum NotesPlan { free, plus }

enum PlusFeature { localAi20L }

enum EntitlementSource { none, debug, billing }

class PlusEntitlementSnapshot {
  const PlusEntitlementSnapshot({
    required this.plan,
    required this.source,
  });

  final NotesPlan plan;
  final EntitlementSource source;

  bool get isPlus => plan == NotesPlan.plus;

  bool allows(PlusFeature feature) => isPlus;

  Map<String, Object?> toJson() => {
        'plan': plan.name,
        'source': source.name,
      };
}

abstract final class PlusPolicy {
  static const localAiLabel = 'AI locale avanzata';
  static const localAiModel = 'Needle 3 20L';

  static bool allows(
    PlusEntitlementSnapshot entitlement,
    PlusFeature feature,
  ) =>
      entitlement.allows(feature);
}
