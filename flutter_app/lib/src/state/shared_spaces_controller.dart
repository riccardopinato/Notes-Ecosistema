import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/shared_spaces.dart';

class SharedSpacesState {
  const SharedSpacesState({
    this.identity,
    this.spaces = const [],
    this.loading = true,
    this.error,
  });

  final SharedIdentity? identity;
  final List<SharedSpace> spaces;
  final bool loading;
  final Object? error;

  SharedSpace? byId(String id) {
    for (final space in spaces) {
      if (space.id == id) return space;
    }
    return null;
  }

  SharedSpacesState copyWith({
    SharedIdentity? identity,
    List<SharedSpace>? spaces,
    bool? loading,
    Object? error,
    bool clearError = false,
  }) =>
      SharedSpacesState(
        identity: identity ?? this.identity,
        spaces: spaces ?? this.spaces,
        loading: loading ?? this.loading,
        error: clearError ? null : error ?? this.error,
      );
}

class SharedSpacesController extends StateNotifier<SharedSpacesState> {
  SharedSpacesController() : super(const SharedSpacesState()) {
    load();
  }

  static const _key = 'shared_spaces_v1';

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.trim().isEmpty) {
        final identity = SharedSpaces.newIdentity();
        state = SharedSpacesState(
          identity: identity,
          spaces: const [],
          loading: false,
        );
        await _persist();
        return;
      }
      final snapshot = SharedSpacesCodec.decode(raw);
      state = SharedSpacesState(
        identity: snapshot.identity,
        spaces: snapshot.spaces,
        loading: false,
      );
    } catch (error) {
      state = SharedSpacesState(
        identity: SharedSpaces.newIdentity(),
        spaces: const [],
        loading: false,
        error: error,
      );
    }
  }

  Future<void> _persist() async {
    final identity = state.identity;
    if (identity == null) return;
    final raw = SharedSpacesCodec.encode(
      SharedSpacesSnapshot(
        identity: identity,
        spaces: state.spaces,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, raw);
  }

  int _clock(SharedSpace? space) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (space == null) return now;
    return now > space.updatedAt ? now : space.updatedAt + 1;
  }

  SharedIdentity get _identity {
    final value = state.identity;
    if (value == null) {
      throw const FormatException(
        'Profilo collaborazione non ancora disponibile.',
      );
    }
    return value;
  }

  SharedSpace _space(String id) {
    final value = state.byId(id);
    if (value == null) {
      throw const FormatException('Spazio condiviso non trovato.');
    }
    return value;
  }

  Future<void> _replace(SharedSpace next) async {
    final spaces = [
      for (final space in state.spaces)
        if (space.id == next.id) next else space,
    ];
    if (!spaces.any((space) => space.id == next.id)) {
      spaces.add(next);
    }
    spaces.sort(
      (a, b) => b.updatedAt.compareTo(a.updatedAt),
    );
    state = state.copyWith(spaces: spaces, clearError: true);
    await _persist();
  }

  Future<void> setIdentityName(String name) async {
    final current = _identity;
    final next = current.copyWith(displayName: name.trim());
    SharedSpaces.validateIdentity(next);
    final now = DateTime.now().millisecondsSinceEpoch;
    final spaces = state.spaces.map((space) {
      final index =
          space.members.indexWhere((member) => member.id == current.id);
      if (index < 0) return space;
      final members = [...space.members];
      final old = members[index];
      members[index] = old.copyWith(
        displayName: next.displayName,
        updatedAt: now > old.clock ? now : old.clock + 1,
      );
      return space.copyWith(members: members);
    }).toList(growable: false);
    state = state.copyWith(
      identity: next,
      spaces: spaces,
      clearError: true,
    );
    await _persist();
  }

  Future<void> bindGitHubAccount({
    required String userId,
    required String login,
  }) async {
    final current = _identity;
    final canonicalId = SharedSpaces.githubIdentityId(userId);
    if (current.id == canonicalId &&
        current.githubUserId == userId &&
        current.githubLogin == login) {
      return;
    }
    final snapshot = SharedSpaces.bindGitHubIdentity(
      SharedSpacesSnapshot(
        identity: _identity,
        spaces: state.spaces,
      ),
      userId: userId,
      login: login,
    );
    state = state.copyWith(
      identity: snapshot.identity,
      spaces: snapshot.spaces,
      clearError: true,
    );
    await _persist();
  }

  Future<String> createSpace(
    String name, {
    String description = '',
  }) async {
    if (state.spaces.length >= SharedSpaces.maxSpaces) {
      throw const FormatException(
        'Puoi creare fino a 30 Shared Spaces.',
      );
    }
    final space = SharedSpaces.create(
      owner: _identity,
      name: name,
      description: description,
    );
    state = state.copyWith(
      spaces: [space, ...state.spaces],
      clearError: true,
    );
    await _persist();
    return space.id;
  }

  Future<void> updateDetails(
    String spaceId, {
    required String name,
    required String description,
  }) async {
    final current = _space(spaceId);
    final next = SharedSpaces.rename(
      current,
      _identity,
      name: name,
      description: description,
      now: _clock(current),
    );
    await _replace(next);
  }

  Future<void> linkContent(String spaceId, String contentId) async {
    final current = _space(spaceId);
    final next = SharedSpaces.linkContent(
      current,
      _identity.id,
      contentId,
      now: _clock(current),
    );
    await _replace(next);
  }

  Future<void> unlinkContent(String spaceId, String contentId) async {
    final current = _space(spaceId);
    final next = SharedSpaces.unlinkContent(
      current,
      _identity.id,
      contentId,
      now: _clock(current),
    );
    await _replace(next);
  }

  Future<void> setMemberRole(
    String spaceId,
    String memberId,
    SharedRole role,
  ) async {
    final current = _space(spaceId);
    final next = SharedSpaces.updateMember(
      current,
      _identity,
      memberId,
      role: role,
      now: _clock(current),
    );
    await _replace(next);
  }

  Future<void> removeMember(
    String spaceId,
    String memberId,
  ) async {
    final current = _space(spaceId);
    final next = SharedSpaces.removeMember(
      current,
      _identity,
      memberId,
      now: _clock(current),
    );
    await _replace(next);
  }

  String createInvite(
    String spaceId, {
    SharedRole role = SharedRole.editor,
  }) {
    final current = _space(spaceId);
    return SharedSpaces.invite(
      current,
      _identity,
      role: role,
      now: _clock(current),
    ).encode();
  }

  Future<String> joinInvite(String code) async {
    final invite = SharedSpaceInvite.decode(code);
    final existing = state.byId(invite.spaceId);
    final joined = SharedSpaces.joinInvite(
      invite,
      _identity,
      existing: existing,
      now: _clock(existing),
    );
    await _replace(joined);
    return joined.id;
  }

  Future<void> mergeRemoteSpace(SharedSpace remote) async {
    SharedSpaces.validateSpace(remote);
    final current = state.byId(remote.id);
    final identity = _identity;

    if (current == null) {
      if (!remote.canRead(identity.id)) {
        throw const FormatException(
          'Importa prima l’invito per accedere a questo spazio.',
        );
      }
      await _replace(remote);
      return;
    }

    if (!current.canRead(identity.id) && !remote.canRead(identity.id)) {
      throw const FormatException(
        'Il tuo profilo non appartiene a questo spazio.',
      );
    }
    final merged = SharedSpaces.merge(current, remote);
    await _replace(merged);
  }

  Future<void> applyLiveSync(List<SharedSpace> spaces) async {
    if (spaces.length > SharedSpaces.maxSpaces) {
      throw const FormatException('Troppi Shared Spaces sincronizzati.');
    }
    final ids = <String>{};
    for (final space in spaces) {
      SharedSpaces.validateSpace(space);
      if (!ids.add(space.id)) {
        throw const FormatException('Shared Space duplicato nel sync.');
      }
    }
    final ordered = [...spaces]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final identity = _identity;
    final currentRaw = SharedSpacesCodec.encode(
      SharedSpacesSnapshot(
        identity: identity,
        spaces: state.spaces,
      ),
    );
    final nextRaw = SharedSpacesCodec.encode(
      SharedSpacesSnapshot(
        identity: identity,
        spaces: ordered,
      ),
    );
    if (currentRaw == nextRaw) {
      if (state.error != null) {
        state = state.copyWith(clearError: true);
      }
      return;
    }
    state = state.copyWith(
      spaces: ordered,
      clearError: true,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, nextRaw);
  }

  Future<void> forgetSpace(String spaceId) async {
    _space(spaceId);
    final spaces = state.spaces.where((space) => space.id != spaceId).toList();
    state = state.copyWith(spaces: spaces, clearError: true);
    await _persist();
  }
}

final sharedSpacesProvider =
    StateNotifierProvider<SharedSpacesController, SharedSpacesState>(
  (ref) => SharedSpacesController(),
);
