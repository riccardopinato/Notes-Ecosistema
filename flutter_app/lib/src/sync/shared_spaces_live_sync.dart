import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/legacy_notes_database.dart';
import '../domain/attachments.dart';
import '../domain/shared_spaces.dart';
import '../domain/sync.dart';
import 'github_sync_service.dart';

class SharedLiveSyncResult {
  const SharedLiveSyncResult({
    required this.spaces,
    required this.uploaded,
    required this.downloaded,
    required this.conflicts,
    required this.purged,
    required this.waiting,
  });

  final List<SharedSpace> spaces;
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

  factory _SpaceSyncRecords.empty() => const _SpaceSyncRecords({});

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
    required this.sha,
  });

  final SharedSpace space;
  final String sha;
}

class SharedSpacesLiveSyncService {
  SharedSpacesLiveSyncService(this.database);

  final LegacyNotesDatabase database;

  static const _remoteFormat = 'notes-ecosystem-shared-live';
  static const _remoteVersion = 1;
  static const _remoteStateLimit = 1024 * 1024;

  Future<SharedLiveSyncResult> run(
    SharedSpacesSnapshot snapshot,
  ) async {
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

    final rootApi = GitHubApi(root);
    try {
      final private = await rootApi.verify();
      if (!private) {
        throw const FormatException(
          'Shared Spaces Live Sync richiede un repository GitHub privato.',
        );
      }
    } finally {
      rootApi.close();
    }

    final localDocuments = await database.syncDocuments();
    final resultSpaces = <SharedSpace>[];
    var uploaded = 0;
    var downloaded = 0;
    var conflicts = 0;
    var purged = 0;
    var waiting = 0;

    for (final localSpace in snapshot.spaces) {
      if (!localSpace.canRead(snapshot.identity.id)) {
        resultSpaces.add(localSpace);
        continue;
      }

      final result = await _syncSpace(
        root,
        snapshot.identity,
        localSpace,
        localDocuments,
      );
      resultSpaces.add(result.space);
      uploaded += result.uploaded;
      downloaded += result.downloaded;
      conflicts += result.conflicts;
      purged += result.purged;
      waiting += result.waiting;

      // Keep subsequent spaces consistent when a conflict copy or download
      // changed the canonical local database.
      if (result.downloaded > 0 || result.conflicts > 0) {
        localDocuments
          ..clear()
          ..addAll(await database.syncDocuments());
      }
    }

    return SharedLiveSyncResult(
      spaces: resultSpaces,
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
    Map<String, SyncDocument> localDocuments,
  ) async {
    GitHubHttpFailure? lastConflict;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _syncSpaceOnce(
          root,
          identity,
          localSpace,
          localDocuments,
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
    Map<String, SyncDocument> localDocuments,
  ) async {
    final folder = _spaceFolder(root.folder, localSpace.id);
    final config = GitHubConfig(
      owner: root.owner,
      repo: root.repo,
      branch: root.branch,
      folder: folder,
      token: root.token,
      allowPublic: false,
    );
    config.validate();

    final api = GitHubApi(config);
    try {
      final head = await api.head();
      final remoteState = await _readRemoteState(api, head);
      if (remoteState == null && !localSpace.canEdit(identity.id)) {
        return _SpaceRun(
          space: localSpace,
          waiting: 1,
        );
      }

      final mergedSpace = remoteState == null
          ? localSpace
          : SharedSpaces.merge(localSpace, remoteState.space);

      if (!mergedSpace.canRead(identity.id)) {
        return _SpaceRun(space: mergedSpace);
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
            await api.deleteFile(
              remoteFile.name,
              remoteFile.sha,
              message: 'Notes Shared: rimuovi contenuto non condiviso',
            );
            purged++;
          }
        }
      }

      for (final id in activeIds) {
        final filename = SyncCodec.filename(id);
        final remoteFile = byName[filename];
        final local = localDocuments[id];
        final remote = remoteFile == null
            ? null
            : await api.readNote(remoteFile, head);

        if (remote != null && remote.id != id) {
          throw const FormatException(
            'Documento Shared Space remoto non coerente.',
          );
        }

        final baseHash = records.baseHashes[id];
        final decision = _decide(
          baseHash: baseHash,
          local: local,
          remote: remote,
        );

        switch (decision) {
          case _SharedDecision.same:
            if (local != null) {
              finalDocuments[id] = local;
              records.baseHashes[id] = _documentHash(local);
            }
          case _SharedDecision.upload:
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
                await database.applySyncDocument(remote);
                finalDocuments[id] = remote;
                records.baseHashes[id] = _documentHash(remote);
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
            await _publishAssets(local, api);
            await api.writeNote(local, remoteFile?.sha);
            finalDocuments[id] = local;
            records.baseHashes[id] = _documentHash(local);
            uploaded++;
          case _SharedDecision.download:
            if (remote == null) {
              if (canEdit && local != null) {
                await _publishAssets(local, api);
                await api.writeNote(local, null);
                finalDocuments[id] = local;
                records.baseHashes[id] = _documentHash(local);
                uploaded++;
              } else {
                waiting++;
              }
              break;
            }
            await _receiveAssets(remote, api, head);
            await database.applySyncDocument(remote);
            finalDocuments[id] = remote;
            records.baseHashes[id] = _documentHash(remote);
            downloaded++;
          case _SharedDecision.conflict:
            if (remote == null && local != null && canEdit) {
              await _publishAssets(local, api);
              await api.writeNote(local, null);
              finalDocuments[id] = local;
              records.baseHashes[id] = _documentHash(local);
              uploaded++;
              break;
            }
            if (remote == null) {
              waiting++;
              break;
            }
            if (local != null && local != remote) {
              await database.saveSyncCopy(
                local,
                suffix: ' (conflitto Shared Space)',
              );
            }
            await _receiveAssets(remote, api, head);
            await database.applySyncDocument(remote);
            finalDocuments[id] = remote;
            records.baseHashes[id] = _documentHash(remote);
            conflicts++;
            downloaded++;
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
            await api.deleteFile(
              'assets/${entry.key}',
              entry.value.sha,
              message: 'Notes Shared: rimuovi allegato orfano',
            );
            purged++;
          }
        }
      }

      final encodedState = Uint8List.fromList(
        utf8.encode(_encodeRemoteState(mergedSpace)),
      );
      final remoteRaw = remoteState == null
          ? null
          : _encodeRemoteState(remoteState.space);
      final nextRaw = utf8.decode(encodedState);
      if (remoteRaw != nextRaw) {
        await api.writeFile(
          'space.json',
          encodedState,
          expectedSha: remoteState?.sha,
          message: 'Notes Shared: aggiorna spazio',
          limit: _remoteStateLimit,
        );
        uploaded++;
      }

      await _saveRecords(root, mergedSpace.id, records);

      return _SpaceRun(
        space: mergedSpace,
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

  _SharedDecision _decide({
    required String? baseHash,
    required SyncDocument? local,
    required SyncDocument? remote,
  }) {
    if (local == null && remote == null) {
      return _SharedDecision.same;
    }
    if (local == null) return _SharedDecision.download;
    if (remote == null) return _SharedDecision.upload;

    final localHash = _documentHash(local);
    final remoteHash = _documentHash(remote);
    if (localHash == remoteHash) return _SharedDecision.same;

    if (baseHash != null) {
      if (localHash == baseHash) return _SharedDecision.download;
      if (remoteHash == baseHash) return _SharedDecision.upload;
      return _SharedDecision.conflict;
    }

    if (local.updatedAt > remote.updatedAt) {
      return _SharedDecision.upload;
    }
    if (remote.updatedAt > local.updatedAt) {
      return _SharedDecision.download;
    }
    return _SharedDecision.conflict;
  }

  Future<void> _publishAssets(
    SyncDocument document,
    GitHubApi api,
  ) async {
    if (document.sketchJson != null) return;
    final store = await AttachmentStore.open();
    for (final ref in Attachments.refs(document.body)) {
      final bytes = await store.read(ref.key);
      await api.ensureAssetUploaded(ref.key, bytes);
    }
  }

  Future<void> _receiveAssets(
    SyncDocument document,
    GitHubApi api,
    String head,
  ) async {
    if (document.sketchJson != null) return;
    final store = await AttachmentStore.open();
    for (final ref in Attachments.refs(document.body)) {
      if (await store.exists(ref.key)) continue;
      final bytes = await api.downloadAsset(ref.key, head);
      await store.put(ref.key, bytes);
    }
  }

  Future<_SpaceRemoteState?> _readRemoteState(
    GitHubApi api,
    String head,
  ) async {
    final file = await api.readFile(
      'space.json',
      head,
      limit: _remoteStateLimit,
    );
    if (file == null) return null;
    final raw = utf8.decode(file.bytes, allowMalformed: false);
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['format'] != _remoteFormat ||
        decoded['version'] != _remoteVersion ||
        decoded['space'] is! Map) {
      throw const FormatException(
        'Stato Shared Space remoto non valido.',
      );
    }
    final space = SharedSpace.fromJson(
      (decoded['space'] as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
    return _SpaceRemoteState(space: space, sha: file.sha);
  }

  String _encodeRemoteState(SharedSpace space) {
    SharedSpaces.validateSpace(space);
    return jsonEncode({
      'format': _remoteFormat,
      'version': _remoteVersion,
      'space': space.toJson(),
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

  String _documentHash(SyncDocument document) =>
      sha256.convert(utf8.encode(SyncCodec.encode(document))).toString();

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

enum _SharedDecision {
  same,
  upload,
  download,
  conflict,
}

class _SpaceRun {
  const _SpaceRun({
    required this.space,
    this.uploaded = 0,
    this.downloaded = 0,
    this.conflicts = 0,
    this.purged = 0,
    this.waiting = 0,
  });

  final SharedSpace space;
  final int uploaded;
  final int downloaded;
  final int conflicts;
  final int purged;
  final int waiting;
}
