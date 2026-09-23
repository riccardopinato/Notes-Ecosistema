import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/shared_spaces.dart';
import '../state/shared_spaces_controller.dart';
import '../state/workspace_controller.dart';
import '../sync/shared_spaces_live_sync.dart';

class SharedLiveSyncState {
  const SharedLiveSyncState({
    this.enabled = false,
    this.busy = false,
    this.message = 'Live Sync disattivato.',
    this.lastSyncAt,
    this.conflicts = 0,
    this.error,
  });

  final bool enabled;
  final bool busy;
  final String message;
  final int? lastSyncAt;
  final int conflicts;
  final Object? error;

  SharedLiveSyncState copyWith({
    bool? enabled,
    bool? busy,
    String? message,
    int? lastSyncAt,
    int? conflicts,
    Object? error,
    bool clearError = false,
  }) =>
      SharedLiveSyncState(
        enabled: enabled ?? this.enabled,
        busy: busy ?? this.busy,
        message: message ?? this.message,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        conflicts: conflicts ?? this.conflicts,
        error: clearError ? null : error ?? this.error,
      );
}

class SharedLiveSyncController extends StateNotifier<SharedLiveSyncState> {
  SharedLiveSyncController(this.ref)
      : super(const SharedLiveSyncState()) {
    _load();
  }

  static const _enabledKey = 'shared_live_sync_enabled_v1';
  static const _interval = Duration(seconds: 90);

  final Ref ref;
  Timer? _timer;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    if (!mounted) return;
    state = state.copyWith(
      enabled: enabled,
      message: enabled
          ? 'Live Sync pronto.'
          : 'Live Sync disattivato.',
      clearError: true,
    );
    if (enabled) {
      _schedule();
      unawaited(syncNow(silent: true));
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (!mounted) return;
    state = state.copyWith(
      enabled: enabled,
      message: enabled
          ? 'Live Sync attivo.'
          : 'Live Sync disattivato.',
      clearError: true,
    );
    if (enabled) {
      _schedule();
      await syncNow();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(
      _interval,
      (_) => unawaited(syncNow(silent: true)),
    );
  }

  Future<void> syncNow({bool silent = false}) async {
    if (state.busy) return;

    final shared = ref.read(sharedSpacesProvider);
    final identity = shared.identity;
    if (identity == null || shared.loading) return;

    if (shared.spaces.isEmpty) {
      if (!mounted) return;
      state = state.copyWith(
        busy: false,
        message: 'Nessuno Shared Space da sincronizzare.',
        clearError: true,
      );
      return;
    }

    state = state.copyWith(
      busy: true,
      message: 'Shared Spaces in sincronizzazione…',
      clearError: true,
    );

    try {
      final database = ref.read(databaseProvider);
      final service = SharedSpacesLiveSyncService(database);
      final result = await service.run(
        SharedSpacesSnapshot(
          identity: identity,
          spaces: shared.spaces,
        ),
      );
      await ref
          .read(sharedSpacesProvider.notifier)
          .applyLiveSync(result.spaces);
      await ref.read(workspaceProvider.notifier).refresh();

      if (!mounted) return;
      state = state.copyWith(
        busy: false,
        message: result.message,
        lastSyncAt: DateTime.now().millisecondsSinceEpoch,
        conflicts: result.conflicts,
        clearError: true,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        busy: false,
        message: silent
            ? state.message
            : 'Live Sync non completato.',
        error: error,
      );
    }
  }

  Future<void> syncSoon() async {
    if (!state.enabled || state.busy) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (mounted) {
      await syncNow(silent: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final sharedLiveSyncProvider =
    StateNotifierProvider<SharedLiveSyncController, SharedLiveSyncState>(
  (ref) => SharedLiveSyncController(ref),
);
