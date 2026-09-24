import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/shared_activity.dart';
import '../domain/shared_spaces.dart';
import '../platform/shared_background_bridge.dart';
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
    if (error.status == 408 || error.status == 429 || error.status >= 500) {
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
    this.activitiesBySpace = const {},
    this.lastReadAt = const {},
    this.backgroundLastCheckAt,
    this.backgroundLastSuccessAt,
    this.backgroundIntervalMinutes = 15,
    this.backgroundError,
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
  final Map<String, List<SharedActivityEvent>> activitiesBySpace;
  final Map<String, int> lastReadAt;
  final int? backgroundLastCheckAt;
  final int? backgroundLastSuccessAt;
  final int backgroundIntervalMinutes;
  final String? backgroundError;
  final Object? error;

  int unreadFor(String spaceId, String identityId) => sharedUnreadCount(
        events: activitiesBySpace[spaceId] ?? const [],
        identityId: identityId,
        lastReadAt: lastReadAt[spaceId] ?? 0,
      );

  int totalUnread(String identityId) {
    var total = 0;
    for (final spaceId in activitiesBySpace.keys) {
      total += unreadFor(spaceId, identityId);
    }
    return total;
  }

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
    Map<String, List<SharedActivityEvent>>? activitiesBySpace,
    Map<String, int>? lastReadAt,
    int? backgroundLastCheckAt,
    int? backgroundLastSuccessAt,
    int? backgroundIntervalMinutes,
    String? backgroundError,
    bool clearBackgroundError = false,
    Object? error,
    bool clearError = false,
  }) =>
      SharedLiveSyncState(
        enabled: enabled ?? this.enabled,
        busy: busy ?? this.busy,
        message: message ?? this.message,
        connection: connection ?? this.connection,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        nextRetryAt: clearNextRetry ? null : nextRetryAt ?? this.nextRetryAt,
        failureStreak: failureStreak ?? this.failureStreak,
        conflicts: conflicts ?? this.conflicts,
        spaceSummaries: spaceSummaries ?? this.spaceSummaries,
        activitiesBySpace: activitiesBySpace ?? this.activitiesBySpace,
        lastReadAt: lastReadAt ?? this.lastReadAt,
        backgroundLastCheckAt:
            backgroundLastCheckAt ?? this.backgroundLastCheckAt,
        backgroundLastSuccessAt:
            backgroundLastSuccessAt ?? this.backgroundLastSuccessAt,
        backgroundIntervalMinutes:
            backgroundIntervalMinutes ?? this.backgroundIntervalMinutes,
        backgroundError: clearBackgroundError
            ? null
            : backgroundError ?? this.backgroundError,
        error: clearError ? null : error ?? this.error,
      );
}

class SharedLiveSyncController extends StateNotifier<SharedLiveSyncState> {
  SharedLiveSyncController(this.ref) : super(const SharedLiveSyncState()) {
    _load();
  }

  static const _enabledKey = 'shared_live_sync_enabled_v1';
  static const _activityKey = 'shared_live_activity_v1';
  static const _readKey = 'shared_live_activity_read_v1';
  static const _normalInterval = Duration(seconds: 90);
  static const _busyRetry = Duration(seconds: 10);
  static const _foregroundMinInterval = Duration(seconds: 30);
  static const _identityVerificationInterval = Duration(minutes: 10);
  static const _remoteDiscoveryInterval = Duration(minutes: 5);

  final Ref ref;
  Timer? _timer;
  int _failureStreak = 0;
  int? _lastIdentityVerificationAt;
  int? _lastRemoteDiscoveryAt;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    var activities = <String, List<SharedActivityEvent>>{};
    var reads = <String, int>{};

    final activityRaw = prefs.getString(_activityKey);
    if (activityRaw != null && activityRaw.trim().isNotEmpty) {
      try {
        activities = SharedActivityCodec.decode(activityRaw);
      } catch (_) {
        await prefs.remove(_activityKey);
      }
    }

    final readRaw = prefs.getString(_readKey);
    if (readRaw != null && readRaw.trim().isNotEmpty) {
      try {
        reads = _decodeReadState(readRaw);
      } catch (_) {
        await prefs.remove(_readKey);
      }
    }

    try {
      await SharedBackgroundBridge.setEnabled(enabled);
    } catch (_) {
      // Background worker is Android-only; foreground sync remains available.
    }

    if (!mounted) return;
    state = state.copyWith(
      enabled: enabled,
      connection: SharedLiveConnectionStatus.idle,
      activitiesBySpace: activities,
      lastReadAt: reads,
      message: enabled ? 'Live Sync pronto.' : 'Live Sync disattivato.',
      clearError: true,
      clearNextRetry: true,
    );
    unawaited(refreshBackgroundStatus());
    if (enabled) {
      unawaited(syncNow(silent: true));
    }
  }

  Future<void> refreshBackgroundStatus() async {
    try {
      final background = await SharedBackgroundBridge.status();
      if (!mounted) return;
      state = state.copyWith(
        backgroundLastCheckAt:
            background.lastCheckAt > 0 ? background.lastCheckAt : null,
        backgroundLastSuccessAt:
            background.lastSuccessAt > 0 ? background.lastSuccessAt : null,
        backgroundIntervalMinutes: background.intervalMinutes,
        backgroundError: background.lastError,
        clearBackgroundError: background.lastError == null ||
            background.lastError!.trim().isEmpty,
      );
    } catch (_) {
      // Native background diagnostics are optional outside Android.
    }
  }

  Future<void> _persistActivityCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _activityKey,
      SharedActivityCodec.encode(state.activitiesBySpace),
    );
  }

  Future<void> _persistReadState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_readKey, jsonEncode(state.lastReadAt));
  }

  Map<String, int> _decodeReadState(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded.length > SharedSpaces.maxSpaces) {
      throw const FormatException('Stato lettura Shared non valido.');
    }
    final result = <String, int>{};
    for (final entry in decoded.entries) {
      final key = entry.key.toString();
      final value = entry.value is num
          ? (entry.value as num).toInt()
          : int.tryParse('${entry.value}');
      if (key.isEmpty ||
          key.length > 200 ||
          value == null ||
          value < 0 ||
          value > 4102444800000) {
        throw const FormatException('Stato lettura Shared non valido.');
      }
      result[key] = value;
    }
    return result;
  }

  Future<void> markSpaceRead(String spaceId) async {
    final events = state.activitiesBySpace[spaceId] ?? const [];
    if (events.isEmpty) return;
    final latest =
        events.map((event) => event.at).reduce((a, b) => a > b ? a : b);
    if ((state.lastReadAt[spaceId] ?? 0) >= latest) return;
    state = state.copyWith(
      lastReadAt: {
        ...state.lastReadAt,
        spaceId: latest,
      },
    );
    await _persistReadState();
  }

  Future<void> markAllRead() async {
    final next = <String, int>{...state.lastReadAt};
    for (final entry in state.activitiesBySpace.entries) {
      if (entry.value.isEmpty) continue;
      next[entry.key] =
          entry.value.map((event) => event.at).reduce((a, b) => a > b ? a : b);
    }
    state = state.copyWith(lastReadAt: next);
    await _persistReadState();
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    try {
      await SharedBackgroundBridge.setEnabled(enabled);
    } catch (_) {
      // Keep foreground sync working if the native worker is unavailable.
    }
    if (!mounted) return;

    _timer?.cancel();
    _timer = null;
    _failureStreak = 0;

    state = state.copyWith(
      enabled: enabled,
      connection: SharedLiveConnectionStatus.idle,
      failureStreak: 0,
      message: enabled ? 'Live Sync attivo.' : 'Live Sync disattivato.',
      clearError: true,
      clearNextRetry: true,
    );

    await refreshBackgroundStatus();
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

  Future<SharedIdentity> _ensureGitHubIdentity({
    required bool force,
  }) async {
    final shared = ref.read(sharedSpacesProvider);
    final current = shared.identity;
    if (shared.loading || current == null) {
      throw const FormatException(
        'Profilo collaborazione non ancora disponibile.',
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastVerified = _lastIdentityVerificationAt;
    if (!force &&
        current.githubBound &&
        lastVerified != null &&
        now - lastVerified < _identityVerificationInterval.inMilliseconds) {
      return current;
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
      _lastIdentityVerificationAt = now;
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
      final identity = await _ensureGitHubIdentity(force: !silent);
      final shared = ref.read(sharedSpacesProvider);

      state = state.copyWith(
        busy: true,
        message: 'Shared Spaces in sincronizzazione…',
        clearError: true,
      );

      final database = ref.read(databaseProvider);
      final service = SharedSpacesLiveSyncService(database);
      final now = DateTime.now().millisecondsSinceEpoch;
      final lastDiscovery = _lastRemoteDiscoveryAt;
      final discoverRemote = !silent ||
          lastDiscovery == null ||
          now - lastDiscovery >= _remoteDiscoveryInterval.inMilliseconds;
      final result = await service.run(
        SharedSpacesSnapshot(
          identity: identity,
          spaces: shared.spaces,
        ),
        discoverRemote: discoverRemote,
      );
      if (discoverRemote) {
        _lastRemoteDiscoveryAt = DateTime.now().millisecondsSinceEpoch;
      }

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

      await ref.read(sharedSpacesProvider.notifier).applyLiveSync(merged);
      if (result.downloaded > 0 || result.conflicts > 0) {
        await ref.read(workspaceProvider.notifier).refresh();
      }

      final accessibleIds = merged.map((space) => space.id).toSet();
      var activityChanged = state.activitiesBySpace.keys
          .any((spaceId) => !accessibleIds.contains(spaceId));
      final activity = <String, List<SharedActivityEvent>>{
        for (final entry in state.activitiesBySpace.entries)
          if (accessibleIds.contains(entry.key)) entry.key: entry.value,
      };
      for (final entry in result.activitiesBySpace.entries) {
        final previous = activity[entry.key] ?? const [];
        final next = mergeSharedActivity(previous, entry.value);
        if (!_sameActivity(previous, next)) {
          activityChanged = true;
        }
        activity[entry.key] = next;
      }

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
        activitiesBySpace: activity,
        clearNextRetry: true,
        clearError: true,
      );
      if (activityChanged) {
        await _persistActivityCache();
      }
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

  Future<void> syncOnForeground() async {
    unawaited(refreshBackgroundStatus());
    if (!state.enabled || state.busy) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextRetryAt = state.nextRetryAt;
    if (nextRetryAt != null && nextRetryAt > now) return;
    final lastSyncAt = state.lastSyncAt;
    if (lastSyncAt != null &&
        now - lastSyncAt < _foregroundMinInterval.inMilliseconds) {
      return;
    }
    await syncNow(silent: true);
  }

  bool _sameActivity(
    List<SharedActivityEvent> left,
    List<SharedActivityEvent> right,
  ) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].id != right[index].id) return false;
    }
    return true;
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
