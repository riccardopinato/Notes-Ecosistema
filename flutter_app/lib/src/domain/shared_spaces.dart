import 'dart:convert';

import 'package:uuid/uuid.dart';

enum SharedRole {
  owner,
  editor,
  viewer;

  String get label => switch (this) {
        SharedRole.owner => 'Proprietario',
        SharedRole.editor => 'Può modificare',
        SharedRole.viewer => 'Solo lettura',
      };

  bool get canEdit => this == SharedRole.owner || this == SharedRole.editor;
  bool get canManage => this == SharedRole.owner;
}

class SharedIdentity {
  const SharedIdentity({
    required this.id,
    required this.displayName,
    this.githubUserId,
    this.githubLogin,
    this.legacyIds = const [],
  });

  final String id;
  final String displayName;
  final String? githubUserId;
  final String? githubLogin;
  final List<String> legacyIds;

  bool get githubBound => githubUserId != null && githubLogin != null;

  SharedIdentity copyWith({
    String? id,
    String? displayName,
    String? githubUserId,
    String? githubLogin,
    List<String>? legacyIds,
  }) =>
      SharedIdentity(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        githubUserId: githubUserId ?? this.githubUserId,
        githubLogin: githubLogin ?? this.githubLogin,
        legacyIds: legacyIds ?? this.legacyIds,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'displayName': displayName,
        if (githubUserId != null) 'githubUserId': githubUserId,
        if (githubLogin != null) 'githubLogin': githubLogin,
        if (legacyIds.isNotEmpty) 'legacyIds': legacyIds,
      };

  factory SharedIdentity.fromJson(Map<String, Object?> map) {
    final legacyRaw = map['legacyIds'];
    if (legacyRaw != null && legacyRaw is! List) {
      throw const FormatException('Alias identità non validi.');
    }
    final identity = SharedIdentity(
      id: _requiredId(map['id'], 'identità'),
      displayName: _displayName(map['displayName']),
      githubUserId: map['githubUserId'] == null
          ? null
          : _githubUserId(map['githubUserId']),
      githubLogin:
          map['githubLogin'] == null ? null : _githubLogin(map['githubLogin']),
      legacyIds: legacyRaw == null
          ? const []
          : (legacyRaw as List)
              .map((value) => _requiredId(value, 'alias identità'))
              .toList(growable: false),
    );
    SharedSpaces.validateIdentity(identity);
    return identity;
  }
}

class SharedMember {
  const SharedMember({
    required this.id,
    required this.displayName,
    required this.role,
    required this.updatedAt,
    this.removedAt,
  });

  final String id;
  final String displayName;
  final SharedRole role;
  final int updatedAt;
  final int? removedAt;

  bool get active => removedAt == null || updatedAt > removedAt!;

  int get clock =>
      removedAt == null || updatedAt >= removedAt! ? updatedAt : removedAt!;

  SharedMember copyWith({
    String? id,
    String? displayName,
    SharedRole? role,
    int? updatedAt,
    Object? removedAt = _sharedUnset,
  }) =>
      SharedMember(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        updatedAt: updatedAt ?? this.updatedAt,
        removedAt: identical(removedAt, _sharedUnset)
            ? this.removedAt
            : removedAt as int?,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'displayName': displayName,
        'role': role.name,
        'updatedAt': updatedAt,
        'removedAt': removedAt,
      };

  factory SharedMember.fromJson(Map<String, Object?> map) {
    final roleName = map['role']?.toString();
    final role = SharedRole.values.where((value) => value.name == roleName);
    if (role.isEmpty) {
      throw const FormatException('Ruolo membro non valido.');
    }
    final updatedAt = _timestamp(map['updatedAt'], 'membro');
    final removedAt = map['removedAt'] == null
        ? null
        : _timestamp(map['removedAt'], 'rimozione membro');
    return SharedMember(
      id: _requiredId(map['id'], 'membro'),
      displayName: _displayName(map['displayName']),
      role: role.first,
      updatedAt: updatedAt,
      removedAt: removedAt,
    );
  }
}

class SharedSpace {
  const SharedSpace({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.createdAt,
    required this.nameUpdatedAt,
    required this.descriptionUpdatedAt,
    required this.members,
    required this.contentAddedAt,
    required this.contentRemovedAt,
  });

  final String id;
  final String name;
  final String description;
  final String ownerId;
  final int createdAt;
  final int nameUpdatedAt;
  final int descriptionUpdatedAt;
  final List<SharedMember> members;
  final Map<String, int> contentAddedAt;
  final Map<String, int> contentRemovedAt;

  List<SharedMember> get activeMembers =>
      members.where((member) => member.active).toList(growable: false);

  Set<String> get contentIds {
    final ids = <String>{...contentAddedAt.keys, ...contentRemovedAt.keys};
    return {
      for (final id in ids)
        if ((contentAddedAt[id] ?? -1) > (contentRemovedAt[id] ?? -1)) id,
    };
  }

  int get updatedAt {
    var result = createdAt;
    if (nameUpdatedAt > result) result = nameUpdatedAt;
    if (descriptionUpdatedAt > result) result = descriptionUpdatedAt;
    for (final member in members) {
      if (member.clock > result) result = member.clock;
    }
    for (final value in contentAddedAt.values) {
      if (value > result) result = value;
    }
    for (final value in contentRemovedAt.values) {
      if (value > result) result = value;
    }
    return result;
  }

  SharedMember? member(String identityId) {
    for (final value in members) {
      if (value.id == identityId && value.active) return value;
    }
    return null;
  }

  SharedRole? roleFor(String identityId) => member(identityId)?.role;

  bool canRead(String identityId) => roleFor(identityId) != null;

  bool canEdit(String identityId) => roleFor(identityId)?.canEdit ?? false;

  bool canManage(String identityId) => roleFor(identityId)?.canManage ?? false;

  SharedSpace copyWith({
    String? name,
    String? description,
    String? ownerId,
    int? nameUpdatedAt,
    int? descriptionUpdatedAt,
    List<SharedMember>? members,
    Map<String, int>? contentAddedAt,
    Map<String, int>? contentRemovedAt,
  }) =>
      SharedSpace(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        ownerId: ownerId ?? this.ownerId,
        createdAt: createdAt,
        nameUpdatedAt: nameUpdatedAt ?? this.nameUpdatedAt,
        descriptionUpdatedAt: descriptionUpdatedAt ?? this.descriptionUpdatedAt,
        members: members ?? this.members,
        contentAddedAt: contentAddedAt ?? this.contentAddedAt,
        contentRemovedAt: contentRemovedAt ?? this.contentRemovedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'ownerId': ownerId,
        'createdAt': createdAt,
        'nameUpdatedAt': nameUpdatedAt,
        'descriptionUpdatedAt': descriptionUpdatedAt,
        'members': members.map((member) => member.toJson()).toList(),
        'contentAddedAt': contentAddedAt,
        'contentRemovedAt': contentRemovedAt,
      };

  factory SharedSpace.fromJson(Map<String, Object?> map) {
    final membersRaw = map['members'];
    final addedRaw = map['contentAddedAt'];
    final removedRaw = map['contentRemovedAt'];
    if (membersRaw is! List || addedRaw is! Map || removedRaw is! Map) {
      throw const FormatException('Spazio condiviso non valido.');
    }
    final space = SharedSpace(
      id: _requiredId(map['id'], 'spazio'),
      name: _spaceName(map['name']),
      description: _description(map['description']),
      ownerId: _requiredId(map['ownerId'], 'proprietario'),
      createdAt: _timestamp(map['createdAt'], 'creazione spazio'),
      nameUpdatedAt: _timestamp(map['nameUpdatedAt'], 'nome spazio'),
      descriptionUpdatedAt:
          _timestamp(map['descriptionUpdatedAt'], 'descrizione spazio'),
      members: membersRaw
          .map(
            (item) => SharedMember.fromJson(
              _stringMap(item, 'membro'),
            ),
          )
          .toList(growable: false),
      contentAddedAt: _clockMap(addedRaw, 'contenuti aggiunti'),
      contentRemovedAt: _clockMap(removedRaw, 'contenuti rimossi'),
    );
    SharedSpaces.validateSpace(space);
    return space;
  }
}

class SharedSpaceInvite {
  const SharedSpaceInvite({
    required this.spaceId,
    required this.spaceName,
    required this.owner,
    required this.spaceCreatedAt,
    required this.role,
    required this.issuedAt,
    required this.expiresAt,
  });

  static const prefix = 'NS26.';
  static const format = 'notes-ecosystem-shared-invite';
  static const version = 1;

  final String spaceId;
  final String spaceName;
  final SharedMember owner;
  final int spaceCreatedAt;
  final SharedRole role;
  final int issuedAt;
  final int expiresAt;

  String encode() {
    if (role == SharedRole.owner) {
      throw const FormatException(
        'Un invito non può trasferire la proprietà.',
      );
    }
    if (!owner.active || owner.role != SharedRole.owner) {
      throw const FormatException('Proprietario invito non valido.');
    }
    final raw = utf8.encode(
      jsonEncode({
        'format': format,
        'version': version,
        'spaceId': spaceId,
        'spaceName': spaceName,
        'owner': owner.toJson(),
        'spaceCreatedAt': spaceCreatedAt,
        'role': role.name,
        'issuedAt': issuedAt,
        'expiresAt': expiresAt,
      }),
    );
    return '$prefix${base64Url.encode(raw).replaceAll('=', '')}';
  }

  factory SharedSpaceInvite.decode(
    String code, {
    int? now,
  }) {
    final clean = code.trim();
    if (!clean.startsWith(prefix) || clean.length > 12000) {
      throw const FormatException('Codice invito non riconosciuto.');
    }
    final encoded = clean.substring(prefix.length);
    final padding = '=' * ((4 - encoded.length % 4) % 4);
    late final Object? decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(base64Url.decode('$encoded$padding')),
      );
    } catch (_) {
      throw const FormatException('Codice invito danneggiato.');
    }
    final map = _stringMap(decoded, 'invito');
    if (map['format'] != format || map['version'] != version) {
      throw const FormatException('Versione invito non supportata.');
    }
    final roleName = map['role']?.toString();
    final role = SharedRole.values.where((value) => value.name == roleName);
    if (role.isEmpty || role.first == SharedRole.owner) {
      throw const FormatException('Ruolo invito non valido.');
    }
    final invite = SharedSpaceInvite(
      spaceId: _requiredId(map['spaceId'], 'spazio'),
      spaceName: _spaceName(map['spaceName']),
      owner: SharedMember.fromJson(_stringMap(map['owner'], 'proprietario')),
      spaceCreatedAt: _timestamp(map['spaceCreatedAt'], 'creazione spazio'),
      role: role.first,
      issuedAt: _timestamp(map['issuedAt'], 'invito'),
      expiresAt: _timestamp(map['expiresAt'], 'scadenza invito'),
    );
    if (invite.owner.id.isEmpty ||
        invite.owner.role != SharedRole.owner ||
        !invite.owner.active) {
      throw const FormatException('Proprietario invito non valido.');
    }
    final clock = now ?? DateTime.now().millisecondsSinceEpoch;
    if (invite.expiresAt <= invite.issuedAt || invite.expiresAt < clock) {
      throw const FormatException('Questo invito è scaduto.');
    }
    if (invite.expiresAt - invite.issuedAt >
        const Duration(days: 31).inMilliseconds) {
      throw const FormatException('Durata invito non valida.');
    }
    return invite;
  }
}

class SharedSpacesSnapshot {
  const SharedSpacesSnapshot({
    required this.identity,
    required this.spaces,
  });

  final SharedIdentity identity;
  final List<SharedSpace> spaces;
}

abstract final class SharedSpacesCodec {
  static const format = 'notes-ecosystem-shared-spaces';
  static const version = 1;
  static const maxBytes = 1024 * 1024;

  static String encode(SharedSpacesSnapshot snapshot) {
    SharedSpaces.validateIdentity(snapshot.identity);
    if (snapshot.spaces.length > SharedSpaces.maxSpaces) {
      throw const FormatException('Troppi spazi condivisi.');
    }
    final ids = <String>{};
    for (final space in snapshot.spaces) {
      SharedSpaces.validateSpace(space);
      if (!ids.add(space.id)) {
        throw const FormatException('Spazio condiviso duplicato.');
      }
    }
    final raw = jsonEncode({
      'format': format,
      'version': version,
      'identity': snapshot.identity.toJson(),
      'spaces': snapshot.spaces.map((space) => space.toJson()).toList(),
    });
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Dati Shared Spaces troppo grandi.');
    }
    return raw;
  }

  static SharedSpacesSnapshot decode(String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Dati Shared Spaces troppo grandi.');
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const FormatException('Dati Shared Spaces danneggiati.');
    }
    final map = _stringMap(decoded, 'Shared Spaces');
    if (map['format'] != format || map['version'] != version) {
      throw const FormatException('Formato Shared Spaces non supportato.');
    }
    final spacesRaw = map['spaces'];
    if (spacesRaw is! List || spacesRaw.length > SharedSpaces.maxSpaces) {
      throw const FormatException('Elenco Shared Spaces non valido.');
    }
    final snapshot = SharedSpacesSnapshot(
      identity: SharedIdentity.fromJson(
        _stringMap(map['identity'], 'identità'),
      ),
      spaces: spacesRaw
          .map(
            (item) => SharedSpace.fromJson(
              _stringMap(item, 'spazio'),
            ),
          )
          .toList(growable: false),
    );
    encode(snapshot);
    return snapshot;
  }
}

abstract final class SharedSpaces {
  static const maxSpaces = 30;
  static const maxMembers = 50;
  static const maxContentPerSpace = 500;
  static const maxLegacyIdentityIds = 8;

  static SharedIdentity newIdentity({String displayName = 'Io'}) =>
      SharedIdentity(
        id: const Uuid().v4(),
        displayName: _displayName(displayName),
      );

  static String githubIdentityId(String userId) =>
      'github:${_githubUserId(userId)}';

  static SharedSpacesSnapshot bindGitHubIdentity(
    SharedSpacesSnapshot snapshot, {
    required String userId,
    required String login,
  }) {
    validateIdentity(snapshot.identity);
    final verifiedUserId = _githubUserId(userId);
    final verifiedLogin = _githubLogin(login);
    final current = snapshot.identity;

    if (current.githubUserId != null &&
        current.githubUserId != verifiedUserId &&
        snapshot.spaces.isNotEmpty) {
      throw const FormatException(
        'Questo profilo Shared Spaces è già associato a un altro account GitHub.',
      );
    }

    final canonicalId = githubIdentityId(verifiedUserId);
    final aliases = <String>{
      ...current.legacyIds,
      if (current.id != canonicalId) current.id,
    }..remove(canonicalId);
    if (aliases.length > maxLegacyIdentityIds) {
      throw const FormatException(
        'Troppi alias identità durante la migrazione GitHub.',
      );
    }

    final identity = SharedIdentity(
      id: canonicalId,
      displayName: current.displayName,
      githubUserId: verifiedUserId,
      githubLogin: verifiedLogin,
      legacyIds: aliases.toList(growable: false)..sort(),
    );
    validateIdentity(identity);

    final spaces = snapshot.spaces
        .map((space) => canonicalizeIdentity(space, identity))
        .toList(growable: false);
    return SharedSpacesSnapshot(identity: identity, spaces: spaces);
  }

  static SharedSpace canonicalizeIdentity(
    SharedSpace space,
    SharedIdentity identity,
  ) {
    validateIdentity(identity);
    final aliases = <String>{identity.id, ...identity.legacyIds};
    final matches = space.members
        .where((member) => aliases.contains(member.id))
        .toList(growable: false);
    final ownsSpace = aliases.contains(space.ownerId);

    if (matches.isEmpty) {
      if (ownsSpace) {
        throw const FormatException(
          'Proprietario Shared Space non coerente con i membri.',
        );
      }
      return space;
    }

    var selected = matches.first;
    for (final candidate in matches.skip(1)) {
      if (candidate.clock > selected.clock ||
          (candidate.clock == selected.clock &&
              candidate.updatedAt > selected.updatedAt)) {
        selected = candidate;
      }
    }

    final canonical = selected.copyWith(
      id: identity.id,
      role: ownsSpace ? SharedRole.owner : selected.role,
      removedAt: ownsSpace ? null : selected.removedAt,
    );
    final members = <SharedMember>[
      for (final member in space.members)
        if (!aliases.contains(member.id)) member,
      canonical,
    ];
    final result = space.copyWith(
      ownerId: ownsSpace ? identity.id : space.ownerId,
      members: members,
    );
    validateSpace(result);
    return result;
  }

  static SharedSpace create({
    required SharedIdentity owner,
    required String name,
    String description = '',
    int? now,
  }) {
    validateIdentity(owner);
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    final ownerMember = SharedMember(
      id: owner.id,
      displayName: owner.displayName,
      role: SharedRole.owner,
      updatedAt: at,
    );
    final space = SharedSpace(
      id: const Uuid().v4(),
      name: _spaceName(name),
      description: _description(description),
      ownerId: owner.id,
      createdAt: at,
      nameUpdatedAt: at,
      descriptionUpdatedAt: at,
      members: [ownerMember],
      contentAddedAt: const {},
      contentRemovedAt: const {},
    );
    validateSpace(space);
    return space;
  }

  static SharedSpace rename(
    SharedSpace space,
    SharedIdentity actor, {
    required String name,
    required String description,
    int? now,
  }) {
    requireManage(space, actor.id);
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    return space.copyWith(
      name: _spaceName(name),
      description: _description(description),
      nameUpdatedAt: at,
      descriptionUpdatedAt: at,
    );
  }

  static SharedSpace linkContent(
    SharedSpace space,
    String actorId,
    String contentId, {
    int? now,
  }) {
    requireEdit(space, actorId);
    final id = _requiredId(contentId, 'contenuto');
    final all = <String>{
      ...space.contentAddedAt.keys,
      ...space.contentRemovedAt.keys,
      id,
    };
    if (all.length > maxContentPerSpace) {
      throw const FormatException(
        'Uno spazio può contenere al massimo 500 elementi.',
      );
    }
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    return space.copyWith(
      contentAddedAt: {...space.contentAddedAt, id: at},
    );
  }

  static SharedSpace unlinkContent(
    SharedSpace space,
    String actorId,
    String contentId, {
    int? now,
  }) {
    requireEdit(space, actorId);
    final id = _requiredId(contentId, 'contenuto');
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    return space.copyWith(
      contentRemovedAt: {...space.contentRemovedAt, id: at},
    );
  }

  static SharedSpace updateMember(
    SharedSpace space,
    SharedIdentity actor,
    String memberId, {
    required SharedRole role,
    String? displayName,
    int? now,
  }) {
    requireManage(space, actor.id);
    if (memberId == space.ownerId && role != SharedRole.owner) {
      throw const FormatException(
        'Il proprietario non può perdere il proprio ruolo.',
      );
    }
    if (role == SharedRole.owner && memberId != space.ownerId) {
      throw const FormatException(
        'Il trasferimento proprietà non è disponibile in 0.26.',
      );
    }
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    final members = [...space.members];
    final index = members.indexWhere((member) => member.id == memberId);
    if (index < 0) {
      if (members.length >= maxMembers) {
        throw const FormatException('Limite di 50 membri raggiunto.');
      }
      members.add(
        SharedMember(
          id: _requiredId(memberId, 'membro'),
          displayName: _displayName(displayName ?? 'Membro'),
          role: role,
          updatedAt: at,
        ),
      );
    } else {
      members[index] = members[index].copyWith(
        displayName: displayName == null
            ? members[index].displayName
            : _displayName(displayName),
        role: role,
        updatedAt: at,
        removedAt: null,
      );
    }
    final result = space.copyWith(members: members);
    validateSpace(result);
    return result;
  }

  static SharedSpace removeMember(
    SharedSpace space,
    SharedIdentity actor,
    String memberId, {
    int? now,
  }) {
    requireManage(space, actor.id);
    if (memberId == space.ownerId) {
      throw const FormatException('Il proprietario non può essere rimosso.');
    }
    final index = space.members.indexWhere((member) => member.id == memberId);
    if (index < 0) return space;
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    final members = [...space.members];
    members[index] = members[index].copyWith(removedAt: at);
    return space.copyWith(members: members);
  }

  static SharedSpace merge(SharedSpace local, SharedSpace remote) {
    if (local.id != remote.id ||
        local.ownerId != remote.ownerId ||
        local.createdAt != remote.createdAt) {
      throw const FormatException(
        'Le due copie dello spazio non sono compatibili.',
      );
    }

    final members = <String, SharedMember>{};
    for (final source in [...local.members, ...remote.members]) {
      final current = members[source.id];
      if (current == null ||
          source.clock > current.clock ||
          (source.clock == current.clock &&
              source.updatedAt > current.updatedAt)) {
        members[source.id] = source;
      }
    }

    Map<String, int> mergeClock(
      Map<String, int> a,
      Map<String, int> b,
    ) {
      final result = <String, int>{...a};
      for (final entry in b.entries) {
        final current = result[entry.key];
        if (current == null || entry.value > current) {
          result[entry.key] = entry.value;
        }
      }
      return result;
    }

    final owner = members[local.ownerId];
    if (owner == null || !owner.active || owner.role != SharedRole.owner) {
      final fallback = local.members.firstWhere(
        (member) => member.id == local.ownerId,
        orElse: () => remote.members.firstWhere(
          (member) => member.id == remote.ownerId,
        ),
      );
      members[local.ownerId] = fallback.copyWith(
        role: SharedRole.owner,
        removedAt: null,
        updatedAt: fallback.updatedAt,
      );
    }

    final useRemoteName = remote.nameUpdatedAt > local.nameUpdatedAt;
    final useRemoteDescription =
        remote.descriptionUpdatedAt > local.descriptionUpdatedAt;

    final merged = SharedSpace(
      id: local.id,
      name: useRemoteName ? remote.name : local.name,
      description:
          useRemoteDescription ? remote.description : local.description,
      ownerId: local.ownerId,
      createdAt: local.createdAt,
      nameUpdatedAt: useRemoteName ? remote.nameUpdatedAt : local.nameUpdatedAt,
      descriptionUpdatedAt: useRemoteDescription
          ? remote.descriptionUpdatedAt
          : local.descriptionUpdatedAt,
      members: members.values.toList(growable: false),
      contentAddedAt: mergeClock(
        local.contentAddedAt,
        remote.contentAddedAt,
      ),
      contentRemovedAt: mergeClock(
        local.contentRemovedAt,
        remote.contentRemovedAt,
      ),
    );
    validateSpace(merged);
    return merged;
  }

  static SharedSpace joinInvite(
    SharedSpaceInvite invite,
    SharedIdentity identity, {
    SharedSpace? existing,
    int? now,
  }) {
    validateIdentity(identity);
    if (identity.id == invite.owner.id) {
      throw const FormatException(
        'Questo invito appartiene già al proprietario.',
      );
    }
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    final recipient = SharedMember(
      id: identity.id,
      displayName: identity.displayName,
      role: invite.role,
      updatedAt: at,
    );
    if (existing == null) {
      final result = SharedSpace(
        id: invite.spaceId,
        name: invite.spaceName,
        description: '',
        ownerId: invite.owner.id,
        createdAt: invite.spaceCreatedAt,
        nameUpdatedAt: invite.issuedAt,
        descriptionUpdatedAt: invite.issuedAt,
        members: [invite.owner, recipient],
        contentAddedAt: const {},
        contentRemovedAt: const {},
      );
      validateSpace(result);
      return result;
    }
    if (existing.id != invite.spaceId || existing.ownerId != invite.owner.id) {
      throw const FormatException(
        'L’invito non corrisponde allo spazio locale.',
      );
    }
    final members = [...existing.members];
    final ownerIndex =
        members.indexWhere((member) => member.id == invite.owner.id);
    if (ownerIndex < 0) {
      members.add(invite.owner);
    }
    final selfIndex = members.indexWhere((member) => member.id == identity.id);
    if (selfIndex < 0) {
      members.add(recipient);
    } else if (!members[selfIndex].active) {
      members[selfIndex] = recipient;
    }
    final result = existing.copyWith(members: members);
    validateSpace(result);
    return result;
  }

  static SharedSpaceInvite invite(
    SharedSpace space,
    SharedIdentity actor, {
    SharedRole role = SharedRole.editor,
    int? now,
  }) {
    requireManage(space, actor.id);
    if (role == SharedRole.owner) {
      throw const FormatException(
        'Non puoi invitare un secondo proprietario.',
      );
    }
    final owner = space.member(space.ownerId);
    if (owner == null) {
      throw const FormatException('Proprietario spazio non disponibile.');
    }
    final issuedAt = now ?? DateTime.now().millisecondsSinceEpoch;
    return SharedSpaceInvite(
      spaceId: space.id,
      spaceName: space.name,
      owner: owner,
      spaceCreatedAt: space.createdAt,
      role: role,
      issuedAt: issuedAt,
      expiresAt: issuedAt + const Duration(days: 7).inMilliseconds,
    );
  }

  static void validateIdentity(SharedIdentity identity) {
    _requiredId(identity.id, 'identità');
    _displayName(identity.displayName);
    if ((identity.githubUserId == null) != (identity.githubLogin == null)) {
      throw const FormatException(
        'Associazione account GitHub incompleta.',
      );
    }
    if (identity.githubUserId != null) {
      _githubUserId(identity.githubUserId);
      _githubLogin(identity.githubLogin);
      if (identity.id != githubIdentityId(identity.githubUserId!)) {
        throw const FormatException(
          'ID collaborazione GitHub non coerente.',
        );
      }
    }
    if (identity.legacyIds.length > maxLegacyIdentityIds) {
      throw const FormatException('Troppi alias identità.');
    }
    final aliases = <String>{};
    for (final alias in identity.legacyIds) {
      final value = _requiredId(alias, 'alias identità');
      if (value == identity.id || !aliases.add(value)) {
        throw const FormatException('Alias identità duplicato.');
      }
    }
  }

  static void validateSpace(SharedSpace space) {
    _requiredId(space.id, 'spazio');
    _requiredId(space.ownerId, 'proprietario');
    _spaceName(space.name);
    _description(space.description);
    _timestamp(space.createdAt, 'creazione spazio');
    _timestamp(space.nameUpdatedAt, 'nome spazio');
    _timestamp(space.descriptionUpdatedAt, 'descrizione spazio');

    if (space.members.isEmpty || space.members.length > maxMembers) {
      throw const FormatException('Elenco membri non valido.');
    }
    final memberIds = <String>{};
    for (final member in space.members) {
      _requiredId(member.id, 'membro');
      _displayName(member.displayName);
      _timestamp(member.updatedAt, 'membro');
      if (member.removedAt != null) {
        _timestamp(member.removedAt, 'rimozione membro');
      }
      if (!memberIds.add(member.id)) {
        throw const FormatException('Membro duplicato.');
      }
    }
    final owner = space.members.where(
      (member) =>
          member.id == space.ownerId &&
          member.active &&
          member.role == SharedRole.owner,
    );
    if (owner.length != 1) {
      throw const FormatException(
        'Lo spazio deve avere un proprietario attivo.',
      );
    }
    if (space.members.any(
      (member) =>
          member.id != space.ownerId &&
          member.active &&
          member.role == SharedRole.owner,
    )) {
      throw const FormatException(
        '0.26 supporta un solo proprietario per spazio.',
      );
    }

    final allContent = <String>{
      ...space.contentAddedAt.keys,
      ...space.contentRemovedAt.keys,
    };
    if (allContent.length > maxContentPerSpace) {
      throw const FormatException(
        'Uno spazio supera il limite di 500 elementi.',
      );
    }
    for (final entry in space.contentAddedAt.entries) {
      _requiredId(entry.key, 'contenuto');
      _timestamp(entry.value, 'contenuto');
    }
    for (final entry in space.contentRemovedAt.entries) {
      _requiredId(entry.key, 'contenuto');
      _timestamp(entry.value, 'contenuto');
    }
  }

  static void requireEdit(SharedSpace space, String actorId) {
    if (!space.canEdit(actorId)) {
      throw const FormatException(
        'Non hai il permesso di modificare questo spazio.',
      );
    }
  }

  static void requireManage(SharedSpace space, String actorId) {
    if (!space.canManage(actorId)) {
      throw const FormatException(
        'Solo il proprietario può gestire questo spazio.',
      );
    }
  }
}

const _sharedUnset = Object();

Map<String, Object?> _stringMap(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('$field non valido.');
  }
  return value.map((key, value) => MapEntry(key.toString(), value));
}

String _requiredId(Object? value, String field) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > 200 ||
      value.contains('\u0000')) {
    throw FormatException('ID $field non valido.');
  }
  return value;
}

String _displayName(Object? value) {
  if (value is! String) {
    throw const FormatException('Nome profilo non valido.');
  }
  final clean = value.trim();
  if (clean.isEmpty ||
      clean.length > 80 ||
      clean.codeUnits.any((value) => value < 32)) {
    throw const FormatException('Nome profilo tra 1 e 80 caratteri.');
  }
  return clean;
}

String _githubUserId(Object? value) {
  final text = value?.toString() ?? '';
  if (!RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(text)) {
    throw const FormatException('Account GitHub non valido.');
  }
  return text;
}

String _githubLogin(Object? value) {
  if (value is! String) {
    throw const FormatException('Login GitHub non valido.');
  }
  final clean = value.trim();
  if (!RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$')
      .hasMatch(clean)) {
    throw const FormatException('Login GitHub non valido.');
  }
  return clean;
}

String _spaceName(Object? value) {
  if (value is! String) {
    throw const FormatException('Nome spazio non valido.');
  }
  final clean = value.trim();
  if (clean.isEmpty ||
      clean.length > 100 ||
      clean.codeUnits.any((value) => value < 32)) {
    throw const FormatException('Nome spazio tra 1 e 100 caratteri.');
  }
  return clean;
}

String _description(Object? value) {
  if (value == null) return '';
  if (value is! String || value.length > 1000 || value.contains('\u0000')) {
    throw const FormatException('Descrizione spazio non valida.');
  }
  return value.trim();
}

int _timestamp(Object? value, String field) {
  if (value is! num || value.toInt() != value || value.toInt() < 0) {
    throw FormatException('Data $field non valida.');
  }
  return value.toInt();
}

Map<String, int> _clockMap(Map source, String field) {
  final result = <String, int>{};
  for (final entry in source.entries) {
    final key = _requiredId(entry.key, field);
    result[key] = _timestamp(entry.value, field);
  }
  return result;
}
