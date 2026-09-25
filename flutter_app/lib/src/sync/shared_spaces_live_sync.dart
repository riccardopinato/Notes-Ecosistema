import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/legacy_notes_database.dart';
import '../domain/attachments.dart';
import '../domain/shared_activity.dart';
import '../domain/shared_spaces.dart';
import '../domain/sync.dart';
import 'github_sync_service.dart';
import 'shared_github_api.dart';

enum SharedLiveDecision {
  same,
  upload,
  download,
  conflict,
}

String sharedLiveDocumentHash(SyncDocument document) =>
    sha256.convert(utf8.encode(SyncCodec.encode(document))).toString();

SharedLiveDecision decideSharedLiveDocument({
  required String? baseHash,
  required SyncDocument? local,
  required SyncDocument? remote,
}) {
  if (local == null && remote == null) {
    return SharedLiveDecision.same;
  }
  if (local == null) return SharedLiveDecision.download;
  if (remote == null) return SharedLiveDecision.upload;

  final localHash = sharedLiveDocumentHash(local);
  final remoteHash = sharedLiveDocumentHash(remote);
  if (localHash == remoteHash) return SharedLiveDecision.same;

  if (baseHash != null) {
    if (localHash == baseHash) return SharedLiveDecision.download;
    if (remoteHash == baseHash) return SharedLiveDecision.upload;
    return SharedLiveDecision.conflict;
  }

  if (local.updatedAt > remote.updatedAt) {
    return SharedLiveDecision.upload;
  }
  if (remote.updatedAt > local.updatedAt) {
    return SharedLiveDecision.download;
  }
  return SharedLiveDecision.conflict;
}

SharedActivityEvent sharedActivityEvent({
  required SharedIdentity actor,
  required String spaceId,
  required SharedActivityKind kind,
  required int at,
  String? subjectId,
}) {
  final seed = [
    spaceId,
    kind.name,
    subjectId ?? '',
    at.toString(),
    actor.id,
  ].join('\u0000');
  return SharedActivityEvent(
    id: sha256.convert(utf8.encode(seed)).toString(),
    spaceId: spaceId,
    actorId: actor.id,
    actorName: actor.displayName,
    kind: kind,
    at: at,
    subjectId: subjectId,
  );
}

List<SharedActivityEvent> buildSharedStateActivity({
  required SharedIdentity actor,
  required SharedSpace current,
  SharedSpace? previous,
}) {
  if (previous == null) {
    return [
      sharedActivityEvent(
        actor: actor,
        spaceId: current.id,
        kind: SharedActivityKind.spaceCreated,
        at: current.createdAt,
      ),
    ];
  }

  final events = <SharedActivityEvent>[];
  final metadataAt = [
    if (current.nameUpdatedAt > previous.nameUpdatedAt) current.nameUpdatedAt,
    if (current.descriptionUpdatedAt > previous.descriptionUpdatedAt)
      current.descriptionUpdatedAt,
  ];
  if (metadataAt.isNotEmpty) {
    events.add(
      sharedActivityEvent(
        actor: actor,
        spaceId: current.id,
        kind: SharedActivityKind.spaceUpdated,
        at: metadataAt.reduce((a, b) => a > b ? a : b),
      ),
    );
  }

  for (final entry in current.contentAddedAt.entries) {
    if (entry.value > (previous.contentAddedAt[entry.key] ?? -1)) {
      events.add(
        sharedActivityEvent(
          actor: actor,
          spaceId: current.id,
          kind: SharedActivityKind.contentAdded,
          at: entry.value,
          subjectId: entry.key,
        ),
      );
    }
  }
  for (final entry in current.contentRemovedAt.entries) {
    if (entry.value > (previous.contentRemovedAt[entry.key] ?? -1)) {
      events.add(
        sharedActivityEvent(
          actor: actor,
          spaceId: current.id,
          kind: SharedActivityKind.contentRemoved,
          at: entry.value,
          subjectId: entry.key,
        ),
      );
    }
  }

  final previousMembers = {
    for (final member in previous.members) member.id: member,
  };
  for (final member in current.members) {
    final before = previousMembers[member.id];
    if (before == null || member.clock > before.clock) {
      events.add(
        sharedActivityEvent(
          actor: actor,
          spaceId: current.id,
          kind: SharedActivityKind.memberChanged,
          at: member.clock,
          subjectId: member.id,
        ),
      );
    }
  }
  return mergeSharedActivity(const [], events);
}

List<SharedSpace> mergeDiscoveredSharedSpaces({
  required SharedIdentity identity,
  required List<SharedSpace> localSpaces,
  required List<SharedSpace> remoteSpaces,
}) {
  SharedSpaces.validateIdentity(identity);
  final byId = <String, SharedSpace>{
    for (final local in localSpaces) local.id: local,
  };

  for (final remote in remoteSpaces) {
    final canonical = SharedSpaces.canonicalizeIdentity(remote, identity);
    if (!canonical.canRead(identity.id)) continue;

    final local = byId[canonical.id];
    byId[canonical.id] =
        local == null ? canonical : SharedSpaces.merge(local, canonical);
  }

  if (byId.length > SharedSpaces.maxSpaces) {
    throw const FormatException(
      'Troppi Shared Spaces accessibili per questo profilo.',
    );
  }

  final result = byId.values.toList(growable: false)
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return result;
}

class SharedSpaceSyncSummary {
  const SharedSpaceSyncSummary({
    required this.spaceId,
    this.uploaded = 0,
    this.downloaded = 0,
    this.conflicts = 0,
    this.purged = 0,
    this.waiting = 0,
  });

  final String spaceId;
  final int uploaded;
  final int downloaded;
  final int conflicts;
  final int purged;
  final int waiting;

  bool get hasActivity => uploaded > 0 || downloaded > 0 || purged > 0;

  bool get hasAttention => conflicts > 0 || waiting > 0;

  String get label {
    if (conflicts > 0) {
      return conflicts == 1 ? '1 conflitto' : '$conflicts conflitti';
    }
    if (waiting > 0) {
      return waiting == 1 ? '1 elemento in attesa' : '$waiting in attesa';
    }
    final parts = <String>[
      if (uploaded > 0) '$uploaded inviati',
      if (downloaded > 0) '$downloaded ricevuti',
      if (purged > 0) '$purged rimossi',
    ];
    return parts.isEmpty ? 'Aggiornato' : parts.join(' · ');
  }
}

class SharedLiveSyncResult {
  const SharedLiveSyncResult({
    required this.spaces,
    required this.spaceSummaries,
    required this.activitiesBySpace,
    required this.uploaded,
    required this.downloaded,
    required this.conflicts,
    required this.purged,
    required this.waiting,
  });

  final List<SharedSpace> spaces;
  final Map<String, SharedSpaceSyncSummary> spaceSummaries;
  final Map<String, List<SharedActivityEvent>> activitiesBySpace;
  final int uploaded;
  final int downloaded;
  final int conflicts;
  final int purged;
  final int waiting;

  String get message {
    final parts = <String>[
      if (uploaded > 0) '$uploaded inviati',
      if (downloaded > 0) '$downloaded ricevuti',
      if (conflicts > 0) '$conflicts conflitti preservati',
      if (purged > 0) '$purged file rimossi dal cloud',
      if (waiting > 0) '$waiting in attesa',
    ];
    return parts.isEmpty ? 'Shared Spaces già aggiornati.' : parts.join(' · ');
  }
}

class _SpaceSyncRecords {
  const _SpaceSyncRecords(this.baseHashes);

  final Map<String, String> baseHashes;

  factory _SpaceSyncRecords.empty() => _SpaceSyncRecords({});

  factory _SpaceSyncRecords.decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['format'] != 'notes-shared-live-state' ||
        decoded['version'] != 1 ||
        decoded['baseHashes'] is! Map) {
      throw const FormatException(
        'Stato locale Shared Live Sync non valido.',
      );
    }
    final hashes = <String, String>{};
    for (final entry in (decoded['baseHashes'] as Map).entries) {
      final id = entry.key.toString();
      final hash = entry.value?.toString() ?? '';
      if (id.isEmpty ||
          id.length > 200 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
        throw const FormatException(
          'Stato locale Shared Live Sync danneggiato.',
        );
      }
      hashes[id] = hash;
    }
    return _SpaceSyncRecords(hashes);
  }

  String encode() => jsonEncode({
        'format': 'notes-shared-live-state',
        'version': 1,
        'baseHashes': baseHashes,
      });
}

class _SpaceRemoteState {
  const _SpaceRemoteState({
    required this.space,
    required this.activity,
    required this.sha,
  });

  final SharedSpace space;
  final List<SharedActivityEvent> activity;
  final String sha;
}

const sharedRemoteWriteVersion = 1;

bool sharedRemoteVersionSupported(int? version) => version == 1 || version == 2;

class SharedSpacesLiveSyncService {
  SharedSpacesLiveSyncService(this.database);

  final LegacyNotesDatabase database;

  static const _remoteFormat = 'notes-ecosystem-shared-live';
  static const _remoteStateLimit = 1024 * 1024;

  Future<SharedLiveSyncResult> run(
    SharedSpacesSnapshot snapshot, {
    bool discoverRemote = true,
  }) async {
    SharedSpaces.validateIdentity(snapshot.identity);
    if (snapshot.spaces.length > SharedSpaces.maxSpaces) {
      throw const FormatException('Troppi Shared Spaces.');
    }

    final root = await GitHubSyncService(database).config();
    if (root == null) {
      throw const FormatException(
        'Collega prima GitHub Sync nelle Impostazioni.',
      );
    }

    final rootApi = SharedGitHubApi(root);
    final discoveredRemoteSpaces = <SharedSpace>[];
    try {
      final private = await rootApi.verifyPrivateWritable(checkHead: false);
      if (!private) {
        throw const FormatException(
          'Shared Spaces Live Sync richiede un repository GitHub privato.',
        );
      }

      final head = await rootApi.head();
      if (discoverRemote) {
        final folders = await rootApi.listSharedSpaceFolders(head);
        for (final folder in folders) {
          final discoveredConfig = GitHubConfig(
            owner: root.owner,
            repo: root.repo,
            branch: root.branch,
            folder: folder,
            token: root.token,
            allowPublic: false,
          );
          final discoveredApi = SharedGitHubApi(discoveredConfig);
          try {
            final state = await _readRemoteState(discoveredApi, head);
            if (state != null) {
              discoveredRemoteSpaces.add(state.space);
            }
          } finally {
            discoveredApi.close();
          }
        }
      }
    } finally {
      rootApi.close();
    }

    final spacesToSync = mergeDiscoveredSharedSpaces(
      identity: snapshot.identity,
      localSpaces: snapshot.spaces,
      remoteSpaces: discoveredRemoteSpaces,
    );

    final resultSpaces = <SharedSpace>[];
    final spaceSummaries = <String, SharedSpaceSyncSummary>{};
    final activitiesBySpace = <String, List<SharedActivityEvent>>{};
    var uploaded = 0;
    var downloaded = 0;
    var conflicts = 0;
    var purged = 0;
    var waiting = 0;

    for (final localSpace in spacesToSync) {
      if (!localSpace.canRead(snapshot.identity.id)) {
        resultSpaces.add(localSpace);
        continue;
      }

      final result = await _syncSpace(
        root,
        snapshot.identity,
        localSpace,
      );
      resultSpaces.add(result.space);
      spaceSummaries[result.space.id] = SharedSpaceSyncSummary(
        spaceId: result.space.id,
        uploaded: result.uploaded,
        downloaded: result.downloaded,
        conflicts: result.conflicts,
        purged: result.purged,
        waiting: result.waiting,
      );
      activitiesBySpace[result.space.id] = result.activity;
      uploaded += result.uploaded;
      downloaded += result.downloaded;
      conflicts += result.conflicts;
      purged += result.purged;
      waiting += result.waiting;
    }

    return SharedLiveSyncResult(
      spaces: resultSpaces,
      spaceSummaries: Map.unmodifiable(spaceSummaries),
      activitiesBySpace: Map.unmodifiable(activitiesBySpace),
      uploaded: uploaded,
      downloaded: downloaded,
      conflicts: conflicts,
      purged: purged,
      waiting: waiting,
    );
  }

  Future<_SpaceRun> _syncSpace(
    GitHubConfig root,
    SharedIdentity identity,
    SharedSpace localSpace,
  ) async {
    GitHubHttpFailure? lastConflict;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _syncSpaceOnce(
          root,
          identity,
          localSpace,
        );
      } on GitHubHttpFailure catch (error) {
        if (error.status != 409 && error.status != 422) rethrow;
        lastConflict = error;
        await Future<void>.delayed(
          Duration(milliseconds: 150 * (attempt + 1)),
        );
      }
    }
    throw lastConflict ??
        const FormatException(
          'Shared Space cambiato troppe volte durante il sync.',
        );
  }

  Future<_SpaceRun> _syncSpaceOnce(
    GitHubConfig root,
    SharedIdentity identity,
    SharedSpace localSpace,
  ) async {
    final canonicalLocalSpace = SharedSpaces.canonicalizeIdentity(
      localSpace,
      identity,
    );
    final folder = _spaceFolder(root.folder, canonicalLocalSpace.id);
    final config = GitHubConfig(
      owner: root.owner,
      repo: root.repo,
      branch: root.branch,
      folder: folder,
      token: root.token,
      allowPublic: false,
    );
    config.validate();

    final api = SharedGitHubApi(config);
    try {
      final head = await api.head();
      final remoteState = await _readRemoteState(api, head);
      if (remoteState == null && !canonicalLocalSpace.canEdit(identity.id)) {
        return _SpaceRun(
          space: canonicalLocalSpace,
          activity: const [],
          waiting: 1,
        );
      }

      final canonicalRemoteSpace = remoteState == null
          ? null
          : SharedSpaces.canonicalizeIdentity(
              remoteState.space,
              identity,
            );
      final mergedSpace = canonicalRemoteSpace == null
          ? canonicalLocalSpace
          : SharedSpaces.merge(
              canonicalLocalSpace,
              canonicalRemoteSpace,
            );
      var activity = mergeSharedActivity(
        remoteState?.activity ?? const [],
        buildSharedStateActivity(
          actor: identity,
          current: canonicalLocalSpace,
          previous: canonicalRemoteSpace,
        ),
      );

      if (!mergedSpace.canRead(identity.id)) {
        return _SpaceRun(
          space: mergedSpace,
          activity: activity,
        );
      }

      final canEdit = mergedSpace.canEdit(identity.id);
      final records = await _loadRecords(root, mergedSpace.id);
      final remoteFiles = await api.listNotes(head);
      final byName = {
        for (final file in remoteFiles) file.name: file,
      };
      final activeIds = mergedSpace.contentIds;
      final finalDocuments = <String, SyncDocument>{};

      var uploaded = 0;
      var downloaded = 0;
      var conflicts = 0;
      var purged = 0;
      var waiting = 0;

      if (canEdit) {
        final expectedNames = {
          for (final id in activeIds) SyncCodec.filename(id),
        };
        for (final remoteFile in remoteFiles) {
          if (!expectedNames.contains(remoteFile.name)) {
            await api.deleteNote(remoteFile);
            purged++;
          }
        }
      }

      for (final id in activeIds) {
        final filename = SyncCodec.filename(id);
        final remoteFile = byName[filename];
        final remote =
            remoteFile == null ? null : await api.readNote(remoteFile, head);
        final local = await database.syncDocument(id);

        if (remote != null && remote.id != id) {
          throw const FormatException(
            'Documento Shared Space remoto non coerente.',
          );
        }

        final baseHash = records.baseHashes[id];
        final decision = decideSharedLiveDocument(
          baseHash: baseHash,
          local: local,
          remote: remote,
        );

        switch (decision) {
          case SharedLiveDecision.same:
            if (local != null) {
              finalDocuments[id] = local;
              records.baseHashes[id] = sharedLiveDocumentHash(local);
            }
            break;
          case SharedLiveDecision.upload:
            if (!canEdit) {
              if (remote != null) {
                if (local != null && local != remote) {
                  await database.saveSyncCopy(
                    local,
                    suffix: ' (copia locale Shared Space)',
                  );
                  conflicts++;
                }
                await _receiveAssets(remote, api, head);
                if (await _preserveConcurrentLocalIfNeeded(
                  expectedLocal: local,
                  remote: remote,
                  suffix: ' (copia locale Shared Space)',
                )) {
                  conflicts++;
                }
                await database.applySyncDocument(remote);
                finalDocuments[id] = remote;
                records.baseHashes[id] = sharedLiveDocumentHash(remote);
                downloaded++;
              } else {
                waiting++;
              }
              break;
            }
            if (local == null) {
              waiting++;
              break;
            }
            await _publishAssets(local, api, head);
            await api.writeNote(local, remoteFile?.sha);
            finalDocuments[id] = local;
            records.baseHashes[id] = sharedLiveDocumentHash(local);
            activity = mergeSharedActivity(
              activity,
              [
                sharedActivityEvent(
                  actor: identity,
                  spaceId: mergedSpace.id,
                  kind: SharedActivityKind.documentUpdated,
                  at: local.updatedAt,
                  subjectId: local.id,
                ),
              ],
            );
            uploaded++;
            break;
          case SharedLiveDecision.download:
            if (remote == null) {
              if (canEdit && local != null) {
                await _publishAssets(local, api, head);
                await api.writeNote(local, null);
                finalDocuments[id] = local;
                records.baseHashes[id] = sharedLiveDocumentHash(local);
                activity = mergeSharedActivity(
                  activity,
                  [
                    sharedActivityEvent(
                      actor: identity,
                      spaceId: mergedSpace.id,
                      kind: SharedActivityKind.documentUpdated,
                      at: local.updatedAt,
                      subjectId: local.id,
                    ),
                  ],
                );
                uploaded++;
              } else {
                waiting++;
              }
              break;
            }
            await _receiveAssets(remote, api, head);
            if (await _preserveConcurrentLocalIfNeeded(
              expectedLocal: local,
              remote: remote,
              suffix: ' (conflitto Shared Space)',
            )) {
              conflicts++;
            }
            await database.applySyncDocument(remote);
            finalDocuments[id] = remote;
            records.baseHashes[id] = sharedLiveDocumentHash(remote);
            downloaded++;
            break;
          case SharedLiveDecision.conflict:
            if (remote == null && local != null && canEdit) {
              await _publishAssets(local, api, head);
              await api.writeNote(local, null);
              finalDocuments[id] = local;
              records.baseHashes[id] = sharedLiveDocumentHash(local);
              uploaded++;
              break;
            }
            if (remote == null) {
              waiting++;
              break;
            }
            await _receiveAssets(remote, api, head);
            final currentLocal = await database.syncDocument(id);
            if (currentLocal != null && currentLocal != remote) {
              await database.saveSyncCopy(
                currentLocal,
                suffix: ' (conflitto Shared Space)',
              );
            }
            await database.applySyncDocument(remote);
            finalDocuments[id] = remote;
            records.baseHashes[id] = sharedLiveDocumentHash(remote);
            activity = mergeSharedActivity(
              activity,
              [
                sharedActivityEvent(
                  actor: identity,
                  spaceId: mergedSpace.id,
                  kind: SharedActivityKind.conflictPreserved,
                  at: local != null && local.updatedAt > remote.updatedAt
                      ? local.updatedAt
                      : remote.updatedAt,
                  subjectId: id,
                ),
              ],
            );
            conflicts++;
            downloaded++;
            break;
        }
      }

      records.baseHashes.removeWhere(
        (id, _) => !activeIds.contains(id),
      );

      if (canEdit) {
        final referenced = <String>{};
        for (final document in finalDocuments.values) {
          if (document.sketchJson == null) {
            referenced.addAll(
              Attachments.refs(document.body).map((ref) => ref.key),
            );
          }
        }
        final remoteAssets = await api.listAssets(root.branch);
        for (final entry in remoteAssets.entries) {
          if (!referenced.contains(entry.key)) {
            await api.deleteAsset(entry.value);
            purged++;
          }
        }
      }

      final encodedState = Uint8List.fromList(
        utf8.encode(_encodeRemoteState(mergedSpace, activity)),
      );
      final remoteRaw = remoteState == null
          ? null
          : _encodeRemoteState(remoteState.space, remoteState.activity);
      final nextRaw = utf8.decode(encodedState);
      if (remoteRaw != nextRaw) {
        await api.writeState(
          encodedState,
          expectedSha: remoteState?.sha,
          limit: _remoteStateLimit,
        );
        uploaded++;
      }

      await _saveRecords(root, mergedSpace.id, records);

      return _SpaceRun(
        space: mergedSpace,
        activity: activity,
        uploaded: uploaded,
        downloaded: downloaded,
        conflicts: conflicts,
        purged: purged,
        waiting: waiting,
      );
    } finally {
      api.close();
    }
  }

  Future<bool> _preserveConcurrentLocalIfNeeded({
    required SyncDocument? expectedLocal,
    required SyncDocument remote,
    required String suffix,
  }) async {
    final currentLocal = await database.syncDocument(remote.id);
    if (!shouldPreserveConcurrentLocal(
      expectedLocal: expectedLocal,
      currentLocal: currentLocal,
      remote: remote,
    )) {
      return false;
    }
    if (currentLocal != null) {
      await database.saveSyncCopy(
        currentLocal,
        suffix: suffix,
      );
    }
    return true;
  }

  Future<void> _publishAssets(
    SyncDocument document,
    SharedGitHubApi api,
    String head,
  ) async {
    if (document.sketchJson != null) return;
    final store = await AttachmentStore.open();
    for (final ref in Attachments.refs(document.body)) {
      final bytes = await store.read(ref.key);
      await api.ensureAssetUploaded(ref.key, bytes, head);
    }
  }

  Future<void> _receiveAssets(
    SyncDocument document,
    SharedGitHubApi api,
    String head,
  ) async {
    if (document.sketchJson != null) return;
    final store = await AttachmentStore.open();
    for (final ref in Attachments.refs(document.body)) {
      if (await store.contains(ref.key)) continue;
      final bytes = await api.downloadAsset(ref.key, head);
      await store.put(ref.key, bytes);
    }
  }

  Future<_SpaceRemoteState?> _readRemoteState(
    SharedGitHubApi api,
    String head,
  ) async {
    final file = await api.readState(
      head,
      limit: _remoteStateLimit,
    );
    if (file == null) return null;
    final raw = utf8.decode(file.bytes, allowMalformed: false);
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['format'] != _remoteFormat ||
        decoded['space'] is! Map) {
      throw const FormatException(
        'Stato Shared Space remoto non valido.',
      );
    }
    final version = (decoded['version'] as num?)?.toInt();
    if (!sharedRemoteVersionSupported(version)) {
      throw const FormatException(
        'Versione Shared Space remota non supportata.',
      );
    }
    final space = SharedSpace.fromJson(
      (decoded['space'] as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
    final activityRaw = decoded['activity'];
    final activity = <SharedActivityEvent>[];
    if (activityRaw != null) {
      if (activityRaw is! List || activityRaw.length > sharedActivityLimit) {
        throw const FormatException('Cronologia Shared remota non valida.');
      }
      for (final item in activityRaw) {
        if (item is! Map) {
          throw const FormatException('Cronologia Shared remota non valida.');
        }
        final event = SharedActivityEvent.fromJson(
          item.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        );
        if (event.spaceId != space.id) {
          throw const FormatException(
            'Evento Shared associato allo spazio remoto errato.',
          );
        }
        activity.add(event);
      }
    }
    return _SpaceRemoteState(
      space: space,
      activity: mergeSharedActivity(const [], activity),
      sha: file.sha,
    );
  }

  String _encodeRemoteState(
    SharedSpace space,
    List<SharedActivityEvent> activity,
  ) {
    SharedSpaces.validateSpace(space);
    final normalized = mergeSharedActivity(const [], activity);
    return jsonEncode({
      'format': _remoteFormat,
      'version': sharedRemoteWriteVersion,
      'space': space.toJson(),
      'activity': normalized.map((event) => event.toJson()).toList(),
    });
  }

  String _spaceFolder(String rootFolder, String spaceId) {
    final hash = sha256.convert(utf8.encode(spaceId)).toString();
    final folder = '$rootFolder/shared/${hash.substring(0, 32)}';
    if (folder.length > 160) {
      throw const FormatException(
        'Cartella GitHub troppo lunga per Shared Spaces Live Sync.',
      );
    }
    return folder;
  }

  Future<File> _recordsFile(
    GitHubConfig config,
    String spaceId,
  ) async {
    final support = await getApplicationSupportDirectory();
    final folder = Directory(
      p.join(support.path, 'shared_spaces_live_sync'),
    );
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final name = sha256
        .convert(
          utf8.encode('${config.key}\u0000$spaceId'),
        )
        .toString();
    return File(p.join(folder.path, '$name.json'));
  }

  Future<_SpaceSyncRecords> _loadRecords(
    GitHubConfig config,
    String spaceId,
  ) async {
    final file = await _recordsFile(config, spaceId);
    if (!await file.exists()) return _SpaceSyncRecords.empty();
    final raw = await file.readAsString();
    if (utf8.encode(raw).length > 256 * 1024) {
      throw const FormatException(
        'Stato Shared Live Sync locale troppo grande.',
      );
    }
    return _SpaceSyncRecords.decode(raw);
  }

  Future<void> _saveRecords(
    GitHubConfig config,
    String spaceId,
    _SpaceSyncRecords records,
  ) async {
    final file = await _recordsFile(config, spaceId);
    final raw = records.encode();
    if (utf8.encode(raw).length > 256 * 1024) {
      throw const FormatException(
        'Stato Shared Live Sync locale troppo grande.',
      );
    }
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(raw, flush: true);
    await temp.rename(file.path);
  }
}

class _SpaceRun {
  const _SpaceRun({
    required this.space,
    required this.activity,
    this.uploaded = 0,
    this.downloaded = 0,
    this.conflicts = 0,
    this.purged = 0,
    this.waiting = 0,
  });

  final SharedSpace space;
  final List<SharedActivityEvent> activity;
  final int uploaded;
  final int downloaded;
  final int conflicts;
  final int purged;
  final int waiting;
}
