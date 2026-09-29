import 'package:flutter/foundation.dart';

import '../domain/plus.dart';

/// Temporary entitlement boundary for 0.56.2.
///
/// Production builds stay Free until the billing adapter is connected.
/// Debug builds can exercise the Plus delivery flow without pretending that
/// a real purchase has occurred.
class PlusEntitlementService {
  const PlusEntitlementService({
    bool? debugPlus,
  }) : _debugPlus = debugPlus;

  final bool? _debugPlus;

  Future<PlusEntitlementSnapshot> snapshot() async {
    final debugEnabled = _debugPlus ?? kDebugMode;
    if (debugEnabled) {
      return const PlusEntitlementSnapshot(
        plan: NotesPlan.plus,
        source: EntitlementSource.debug,
      );
    }

    return const PlusEntitlementSnapshot(
      plan: NotesPlan.free,
      source: EntitlementSource.none,
    );
  }
}
