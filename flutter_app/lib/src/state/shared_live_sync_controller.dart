import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/shared_spaces.dart';
import '../state/shared_spaces_controller.dart';
import '../state/workspace_controller.dart';
import '../sync/github_sync_service.dart';
import '../sync/shared_github_api.dart';
import '../sync/shared_spaces_live_sync.dart';

enum SharedLiveConnectionStatus {
  idle,
  online,
  offline,
  attention;

  String get label => switch (this) {
        SharedLiveConnectionStatus.idle => 'Inattivo',
        SharedLiveConnectionStatus.online => 'Online',
        SharedLiveConnectionStatus.offline => 'Offline',
        SharedLiveConnectionStatus.attention => 'Attenzione',
      };
}

Duration sharedLiveRetryDelay(int failureStreak) {
  if (failureStreak <= 0) return Duration.zero;
  const schedule = <Duration>[
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];
  final index = failureStreak - 1;
  return schedule[index < schedule.length ? index : schedule.length - 1];
}

SharedLiveConnectionStatus sharedLiveConnectionForError(Object error) {
  if (error is SocketException || error is TimeoutException) {
    return SharedLiveConnectionStatus.offline;
  }
  if (error is GitHubHttpFailure) {
    if (error.status == 408 ||
        error.status == 429 ||
        error.status >= 500) {
      return SharedLiveConnectionStatus.offline;
    }
  }
  return SharedLiveConnectionStatus.attention;
}

class SharedLiveSyncState {
  const SharedLiveSyncState({
    this.enabled = false,
    this.busy = false,
    this.message = 'Live Sync disattivato.',
    this.connection = SharedLiveConnectionStatus.idle,
    this.lastSyncAt,
    this.nextRetryAt,
    this.failureStreak = 0,
    this.conflicts = 0,
    this.spaceSummaries = const {},
    this.error,
  });

  final bool enabled;
  final bool busy;
  final String message;
  final SharedLiveConnectionStatus connection;
  final int? lastSyncAt;
  final int? nextRetryAt;
  final int failureStreak;
  final int conflicts;
  final Map<String, SharedSpaceSyncSummary> spaceSummaries;
  final Object? error;

  SharedLiveSyncState copyWith({
    bool? enabled,
    bool? busy,
    String? message,
    SharedLiveConnectionStatus? connection,
    int? lastSyncAt,
    int? nextRetryAt,
    bool clearNextRetry = false,
    int? failureStreak,
    int? conflicts,
    Map<String, SharedSpaceSyncSummary>? spaceSummaries,
    Object? error,
    bool clearError = false,
  }) =>
      SharedLiveSyncState(
        enabled: enabled ?? this.enabled,
        busy: busy ?? this.busy,
        message: message ?? this.message,
        connection: connection ?? this.connection,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        nextRetryAt:
            clearNextRetry ? null : nextRetryAt ?? this.nextRetryAt,
        failureStreak: failureStreak ?? this.failureStreak,
        conflicts: conflicts ?? this.conflicts,
        spaceSummaries: spaceSummaries ?? this.spaceSummaries,
        error: clearError ? null : error ?? this.error,
      );
}

class SharedLiveSyncController extends StateNotifier<SharedLiveSyncState> {
  SharedLiveSyncController(this.ref)
      : super(const SharedLiveSyncState()) {
    _load();
  }

  static const _enabledKey = 'shared_live_sync_enabled_v1';
  static const _normalInterval = Duration(seconds: 90);
  static const _busyRetry = Duration(seconds: 10);

  final Ref ref;
  Timer? _timer;
  int _failureStreak = 0;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    if (!mounted) return;
    state = state.copyWith(
      enabled: enabled,
      connection: SharedLiveConnectionStatus.idle,
      message: enabled
          ? 'Live Sync pronto.'
          : 'Live Sync disattivato.',
      clearError: true,
      clearNextRetry: true,
    );
    if (enabled) {
      unawaited(syncNow(silent: true));
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (!mounted) return;

    _timer?.cancel();
    _timer = null;
    _failureStreak = 0;

    state = state.copyWith(
      enabled: enabled,
      connection: SharedLiveConnectionStatus.idle,
      failureStreak: 0,
      message: enabled
          ? 'Live Sync attivo.'
          : 'Live Sync disattivato.',
      clearError: true,
      clearNextRetry: true,
    );

    if (enabled) {
      await syncNow();
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = null;
    if (!mounted || !state.enabled) return;
    _timer = Timer(delay, () => unawaited(_scheduledSync()));
  }

  Future<void> _scheduledSync() async {
    if (!mounted || !state.enabled) return;
    if (state.busy) {
      _schedule(_busyRetry);
      return;
    }

    final nextRetryAt = state.nextRetryAt;
    if (nextRetryAt != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final remaining = nextRetryAt - now;
      if (remaining > 0) {
        _schedule(Duration(milliseconds: remaining));
        return;
      }
    }
    await syncNow(silent: true);
  }

  Future<SharedIdentity> _ensureGitHubIdentity() async {
    final shared = ref.read(sharedSpacesProvider);
    if (shared.loading || shared.identity == null) {
      throw const FormatException(
        'Profilo collaborazione non ancora disponibile.',
      );
    }
    final database = ref.read(databaseProvider);
    final config = await GitHubSyncService(database).config();
    if (config == null) {
      throw const FormatException(
        'Collega prima GitHub Sync nelle Impostazioni.',
      );
    }

    final api = SharedGitHubApi(config);
    try {
      final account = await api.authenticatedAccount();
      await ref.read(sharedSpacesProvider.notifier).bindGitHubAccount(
            userId: account.id,
            login: account.login,
          );
    } finally {
      api.close();
    }

    final identity = ref.read(sharedSpacesProvider).identity;
    if (identity == null || !identity.githubBound) {
      throw const FormatException(
        'Associazione account GitHub non riuscita.',
      );
    }
    return identity;
  }

  Future<void> syncNow({bool silent = false}) async {
    if (state.busy) return;

    _timer?.cancel();
    _timer = null;

    final initial = ref.read(sharedSpacesProvider);
    if (initial.identity == null || initial.loading) {
      if (state.enabled) _schedule(_busyRetry);
      return;
    }

    state = state.copyWith(
      busy: true,
      message: 'Verifica account GitHub…',
      clearError: true,
    );

    try {
      final identity = await _ensureGitHubIdentity();
      final shared = ref.read(sharedSpacesProvider);

      state = state.copyWith(
        busy: true,
        message: 'Shared Spaces in sincronizzazione…',
        clearError: true,
      );

      final database = ref.read(databaseProvider);
      final service = SharedSpacesLiveSyncService(database);
      final result = await service.run(
        SharedSpacesSnapshot(
          identity: identity,
          spaces: shared.spaces,
        ),
      );

      final current = ref.read(sharedSpacesProvider).spaces;
      final currentById = {
        for (final space in current) space.id: space,
      };
      final merged = <SharedSpace>[];
      final syncedIds = <String>{};

      for (final synced in result.spaces) {
        syncedIds.add(synced.id);
        final latestLocal = currentById[synced.id];
        if (latestLocal == null) {
          merged.add(synced);
        } else {
          merged.add(SharedSpaces.merge(latestLocal, synced));
        }
      }
      for (final local in current) {
        if (!syncedIds.contains(local.id)) {
          merged.add(local);
        }
      }

      await ref
          .read(sharedSpacesProvider.notifier)
          .applyLiveSync(merged);
      await ref.read(workspaceProvider.notifier).refresh();

      if (!mounted) return;
      _failureStreak = 0;
      state = state.copyWith(
        busy: false,
        connection: SharedLiveConnectionStatus.online,
        message: result.spaces.isEmpty
            ? 'GitHub @${identity.githubLogin ?? ''} collegato · '
                'nessuno Shared Space disponibile.'
            : result.message,
        lastSyncAt: DateTime.now().millisecondsSinceEpoch,
        failureStreak: 0,
        conflicts: result.conflicts,
        spaceSummaries: result.spaceSummaries,
        clearNextRetry: true,
        clearError: true,
      );
      if (state.enabled) _schedule(_normalInterval);
    } catch (error) {
      if (!mounted) return;

      _failureStreak++;
      final retryDelay = sharedLiveRetryDelay(_failureStreak);
      final connection = sharedLiveConnectionForError(error);
      final retryAt = DateTime.now().add(retryDelay).millisecondsSinceEpoch;
      state = state.copyWith(
        busy: false,
        connection: connection,
        message: silent
            ? connection == SharedLiveConnectionStatus.offline
                ? 'Offline · nuovo tentativo automatico.'
                : 'Live Sync in attesa di un nuovo tentativo.'
            : 'Live Sync non completato.',
        nextRetryAt: state.enabled ? retryAt : null,
        clearNextRetry: !state.enabled,
        failureStreak: _failureStreak,
        error: error,
      );
      if (state.enabled) _schedule(retryDelay);
    }
  }

  Future<void> syncSoon() async {
    if (!state.enabled || state.busy) return;
    final nextRetryAt = state.nextRetryAt;
    if (nextRetryAt != null &&
        nextRetryAt > DateTime.now().millisecondsSinceEpoch) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (mounted && state.enabled && !state.busy) {
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
