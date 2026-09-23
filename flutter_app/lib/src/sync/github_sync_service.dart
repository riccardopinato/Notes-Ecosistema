import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/legacy_notes_database.dart';
import '../domain/attachments.dart';
import '../domain/sync.dart';
import '../platform/secure_token_bridge.dart';

class GitHubConfig {
  const GitHubConfig({
    required this.owner,
    required this.repo,
    required this.branch,
    required this.folder,
    required this.token,
    this.allowPublic = false,
  });

  final String owner;
  final String repo;
  final String branch;
  final String folder;
  final String token;
  final bool allowPublic;

  String get key =>
      '${owner.toLowerCase()}\u0000${repo.toLowerCase()}\u0000$branch\u0000$folder';

  String get label => '$owner/$repo · $branch · $folder';

  void validate() {
    if (!RegExp(r'^[A-Za-z0-9-]{1,100}$').hasMatch(owner) ||
        !RegExp(r'^[A-Za-z0-9_.-]{1,100}$').hasMatch(repo) ||
        repo == '.' ||
        repo == '..') {
      throw const FormatException(
        'Indica proprietario e repository validi.',
      );
    }
    if (branch.trim().isEmpty ||
        branch.length > 200 ||
        branch.codeUnits.any((value) => value < 32 || value == 127)) {
      throw const FormatException('Indica un ramo valido.');
    }
    if (folder.isEmpty ||
        folder.length > 160 ||
        folder.split('/').any(
              (part) => !RegExp(r'^[A-Za-z0-9_-]{1,60}$').hasMatch(part),
            )) {
      throw const FormatException(
        'Cartella: usa lettere, numeri, trattini e /, senza spazi.',
      );
    }
    if (token.trim().isEmpty || token.codeUnits.any((c) => c <= 32)) {
      throw const FormatException('Inserisci un token GitHub valido.');
    }
  }
}

class GitHubHttpFailure implements Exception {
  const GitHubHttpFailure(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => message;
}

class RemoteFile {
  const RemoteFile(this.name, this.sha);
  final String name;
  final String sha;
}

class RemoteAsset {
  const RemoteAsset(this.name, this.sha, this.size);
  final String name;
  final String sha;
  final int size;
}

class GitHubApi {
  GitHubApi(this.config);

  final GitHubConfig config;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  Map<String, RemoteAsset>? _assets;

  String get _root =>
      '/repos/${Uri.encodeComponent(config.owner)}/${Uri.encodeComponent(config.repo)}';

  String _path(String value) => value
      .split('/')
      .map(Uri.encodeComponent)
      .join('/');

  Future<String> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    int limit = 12 * 1024 * 1024,
  }) async {
    final request = await _client.openUrl(
      method,
      Uri.parse('https://api.github.com$path'),
    );
    request.followRedirects = false;
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${config.token}')
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
      ..set('X-GitHub-Api-Version', '2026-03-10')
      ..set(HttpHeaders.userAgentHeader, 'Notes-Ecosistema-Flutter');
    if (body != null) {
      request.headers.contentType =
          ContentType('application', 'json', charset: 'utf-8');
      request.write(jsonEncode(body));
    }

    final response =
        await request.close().timeout(const Duration(seconds: 20));
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > limit) {
        throw const FormatException('Risposta GitHub troppo grande.');
      }
      bytes.addAll(chunk);
    }
    final text = utf8.decode(bytes, allowMalformed: false);
    if (response.statusCode < 200 || response.statusCode > 299) {
      final message = switch (response.statusCode) {
        401 => 'Accesso GitHub scaduto o token non valido.',
        403 => 'GitHub ha rifiutato l’accesso o il limite richieste è stato raggiunto.',
        404 => 'Repository, ramo o file non accessibile.',
        409 || 422 =>
          'GitHub è cambiato o il ramo rifiuta la scrittura.',
        429 => 'Limite GitHub raggiunto.',
        _ => 'GitHub non disponibile (HTTP ${response.statusCode}).',
      };
      throw GitHubHttpFailure(response.statusCode, message);
    }
    return text;
  }

  Future<bool> verify() async {
    final repo = jsonDecode(await _request('GET', _root));
    if (repo is! Map) {
      throw const FormatException('Risposta repository non valida.');
    }
    final permissions = repo['permissions'];
    if (permissions is! Map || permissions['push'] != true) {
      throw const FormatException(
        'Serve accesso Contents: Read and write al repository.',
      );
    }
    await head();
    return repo['private'] == true;
  }

  Future<String> head() async {
    final branch = config.branch
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    final value = jsonDecode(
      await _request('GET', '$_root/git/ref/heads/$branch'),
    );
    if (value is! Map ||
        value['object'] is! Map ||
        (value['object'] as Map)['sha'] is! String) {
      throw const FormatException('Ramo GitHub non valido.');
    }
    return (value['object'] as Map)['sha'] as String;
  }

  Future<List<RemoteFile>> listNotes(String ref) async {
    final path = _path(config.folder);
    String text;
    try {
      text = await _request(
        'GET',
        '$_root/contents/$path?ref=${Uri.encodeQueryComponent(ref)}',
      );
    } on GitHubHttpFailure catch (error) {
      if (error.status == 404) return const [];
      rethrow;
    }
    final decoded = jsonDecode(text);
    if (decoded is! List || decoded.length >= 1000) {
      throw const FormatException(
        'Cartella GitHub troppo grande o non valida.',
      );
    }
    final result = <RemoteFile>[];
    final namePattern = RegExp(r'^[a-f0-9]{64}\.md$');
    for (final item in decoded) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? '';
      if (!namePattern.hasMatch(name)) continue;
      if (item['type'] != 'file') {
        throw const FormatException('File note remoto non valido.');
      }
      final size = (item['size'] as num?)?.toInt() ?? -1;
      if (size < 0 || size > SyncCodec.maxBytes) {
        throw const FormatException('Nota remota oltre 256 KB.');
      }
      final sha = item['sha']?.toString() ?? '';
      if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(sha)) {
        throw const FormatException('SHA remoto non valido.');
      }
      result.add(RemoteFile(name, sha));
    }
    if (result.length > 500) {
      throw const FormatException(
        'Questa versione sincronizza fino a 500 note.',
      );
    }
    return result;
  }

  Future<SyncDocument> readNote(RemoteFile file, String ref) async {
    final path = _path('${config.folder}/${file.name}');
    final decoded = jsonDecode(
      await _request(
        'GET',
        '$_root/contents/$path?ref=${Uri.encodeQueryComponent(ref)}',
      ),
    );
    if (decoded is! Map ||
        decoded['sha'] != file.sha ||
        decoded['encoding'] != 'base64') {
      throw const FormatException('File GitHub cambiato durante la lettura.');
    }
    final raw = decoded['content']?.toString() ?? '';
    final bytes = base64Decode(raw.replaceAll(RegExp(r'\s'), ''));
    if (bytes.length > SyncCodec.maxBytes) {
      throw const FormatException('Nota GitHub oltre 256 KB.');
    }
    final document = SyncCodec.decode(utf8.decode(bytes, allowMalformed: false));
    if (SyncCodec.filename(document.id) != file.name) {
      throw const FormatException(
        'ID e nome file GitHub non corrispondono.',
      );
    }
    return document;
  }

  Future<String> writeNote(
    SyncDocument document,
    String? expectedSha,
  ) async {
    final bytes = utf8.encode(SyncCodec.encode(document));
    if (bytes.length > SyncCodec.maxBytes) {
      throw const FormatException('Nota oltre 256 KB.');
    }
    final path = _path(
      '${config.folder}/${SyncCodec.filename(document.id)}',
    );
    final body = <String, Object?>{
      'message': 'Notes: aggiorna nota',
      'branch': config.branch,
      'content': base64Encode(bytes),
      if (expectedSha != null) 'sha': expectedSha,
    };
    final decoded = jsonDecode(
      await _request('PUT', '$_root/contents/$path', body: body),
    );
    if (decoded is! Map || decoded['content'] is! Map) {
      throw const FormatException('Risposta upload GitHub non valida.');
    }
    final sha = (decoded['content'] as Map)['sha']?.toString() ?? '';
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(sha)) {
      throw const FormatException('SHA upload non valido.');
    }
    return sha;
  }

  Future<Map<String, RemoteAsset>> _assetIndex(String ref) async {
    if (_assets != null) return _assets!;
    final path = _path('${config.folder}/assets');
    String text;
    try {
      text = await _request(
        'GET',
        '$_root/contents/$path?ref=${Uri.encodeQueryComponent(ref)}',
      );
    } on GitHubHttpFailure catch (error) {
      if (error.status == 404) {
        _assets = {};
        return _assets!;
      }
      rethrow;
    }
    final decoded = jsonDecode(text);
    if (decoded is! List || decoded.length >= 1000) {
      throw const FormatException('Cartella allegati GitHub troppo grande.');
    }
    final result = <String, RemoteAsset>{};
    for (final item in decoded) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? '';
      if (!Attachments.validKey(name)) continue;
      final size = (item['size'] as num?)?.toInt() ?? -1;
      final sha = item['sha']?.toString() ?? '';
      if (item['type'] != 'file' ||
          size < 1 ||
          size > Attachments.fileLimit ||
          !RegExp(r'^[a-f0-9]{40}$').hasMatch(sha)) {
        throw const FormatException('Allegato remoto non valido.');
      }
      result[name] = RemoteAsset(name, sha, size);
    }
    if (result.length > Attachments.maxFiles) {
      throw const FormatException('Repository oltre 500 allegati.');
    }
    _assets = result;
    return result;
  }

  String _gitSha(Uint8List bytes) {
    final prefix = utf8.encode('blob ${bytes.length}\u0000');
    return sha1.convert([...prefix, ...bytes]).toString();
  }

  Future<void> ensureAssetUploaded(
    String key,
    Uint8List bytes,
  ) async {
    Attachments.verify(key, bytes);
    final index = await _assetIndex(config.branch);
    final existing = index[key];
    final expectedSha = _gitSha(bytes);
    if (existing != null) {
      if (existing.sha != expectedSha || existing.size != bytes.length) {
        throw const FormatException(
          'Allegato remoto con lo stesso nome ma contenuto diverso.',
        );
      }
      return;
    }
    if (index.length >= Attachments.maxFiles) {
      throw const FormatException('Repository oltre 500 allegati.');
    }

    final path = _path('${config.folder}/assets/$key');
    final decoded = jsonDecode(
      await _request(
        'PUT',
        '$_root/contents/$path',
        body: {
          'message': 'Notes: aggiungi allegato',
          'branch': config.branch,
          'content': base64Encode(bytes),
        },
      ),
    );
    if (decoded is! Map || decoded['content'] is! Map) {
      throw const FormatException('Upload allegato non verificabile.');
    }
    final content = decoded['content'] as Map;
    final sha = content['sha']?.toString() ?? '';
    if (sha != expectedSha) {
      throw const FormatException(
        'Verifica allegato caricato non riuscita.',
      );
    }
    index[key] = RemoteAsset(key, sha, bytes.length);
  }

  Future<Uint8List> downloadAsset(String key, String ref) async {
    final index = await _assetIndex(ref);
    final info = index[key];
    if (info == null) {
      throw const FormatException(
        'Allegato remoto non disponibile.',
      );
    }
    final decoded = jsonDecode(
      await _request(
        'GET',
        '$_root/git/blobs/${Uri.encodeComponent(info.sha)}',
        limit: 12 * 1024 * 1024,
      ),
    );
    if (decoded is! Map ||
        decoded['encoding'] != 'base64' ||
        decoded['sha'] != info.sha) {
      throw const FormatException('Blob allegato GitHub non valido.');
    }
    final bytes = Uint8List.fromList(
      base64Decode(
        (decoded['content']?.toString() ?? '')
            .replaceAll(RegExp(r'\s'), ''),
      ),
    );
    if (bytes.length != info.size) {
      throw const FormatException('Dimensione allegato remota non valida.');
    }
    Attachments.verify(key, bytes);
    return bytes;
  }

  void close() => _client.close(force: true);
}

class GitHubSyncRecord {
  const GitHubSyncRecord({
    this.base,
    this.sha,
    this.conflict = false,
    this.local,
    this.remote,
  });

  final SyncDocument? base;
  final String? sha;
  final bool conflict;
  final SyncDocument? local;
  final SyncDocument? remote;

  Map<String, Object?> toJson() => {
        'base': base == null ? null : SyncCodec.encode(base!),
        'sha': sha,
        'conflict': conflict,
        'local': local == null ? null : SyncCodec.encode(local!),
        'remote': remote == null ? null : SyncCodec.encode(remote!),
      };

  factory GitHubSyncRecord.fromJson(Map<String, Object?> map) {
    SyncDocument? document(Object? value) =>
        value is String ? SyncCodec.decode(value) : null;
    return GitHubSyncRecord(
      base: document(map['base']),
      sha: map['sha']?.toString(),
      conflict: map['conflict'] == true,
      local: document(map['local']),
      remote: document(map['remote']),
    );
  }
}

class GitHubSyncStatus {
  const GitHubSyncStatus({
    this.connection,
    this.message = 'GitHub non collegato',
    this.busy = false,
    this.conflicts = const {},
  });

  final String? connection;
  final String message;
  final bool busy;
  final Map<String, GitHubSyncRecord> conflicts;
}

class GitHubSyncService {
  GitHubSyncService(this.database);

  final LegacyNotesDatabase database;
  GitHubSyncStatus status = const GitHubSyncStatus();

  static const _ownerKey = 'github_owner';
  static const _repoKey = 'github_repo';
  static const _branchKey = 'github_branch';
  static const _folderKey = 'github_folder';
  static const _publicKey = 'github_allow_public';

  Future<GitHubConfig?> config() async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getString(_ownerKey);
    final repo = prefs.getString(_repoKey);
    final branch = prefs.getString(_branchKey);
    final folder = prefs.getString(_folderKey);
    final token = await SecureTokenBridge.readGitHubToken();
    if (owner == null ||
        repo == null ||
        branch == null ||
        folder == null ||
        token == null) {
      return null;
    }
    final value = GitHubConfig(
      owner: owner,
      repo: repo,
      branch: branch,
      folder: folder,
      token: token,
      allowPublic: prefs.getBool(_publicKey) ?? false,
    );
    value.validate();
    return value;
  }

  Future<void> connect(GitHubConfig value) async {
    value.validate();
    final api = GitHubApi(value);
    try {
      final private = await api.verify();
      if (!private && !value.allowPublic) {
        throw const FormatException(
          'Il repository è pubblico. Abilita esplicitamente la pubblicazione oppure usa un repository privato.',
        );
      }
    } finally {
      api.close();
    }

    await SecureTokenBridge.saveGitHubToken(value.token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ownerKey, value.owner);
    await prefs.setString(_repoKey, value.repo);
    await prefs.setString(_branchKey, value.branch);
    await prefs.setString(_folderKey, value.folder);
    await prefs.setBool(_publicKey, value.allowPublic);
    status = GitHubSyncStatus(
      connection: value.label,
      message: 'Collegato. Sincronizzazione pronta.',
    );
  }

  Future<void> disconnect() async {
    final current = await config();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ownerKey);
    await prefs.remove(_repoKey);
    await prefs.remove(_branchKey);
    await prefs.remove(_folderKey);
    await prefs.remove(_publicKey);
    await SecureTokenBridge.deleteGitHubToken();
    if (current != null) {
      final file = await _stateFile(current);
      if (await file.exists()) await file.delete();
    }
    status = const GitHubSyncStatus(
      message: 'GitHub scollegato. Note locali conservate.',
    );
  }

  Future<bool> loadStatus() async {
    final current = await config();
    if (current == null) {
      status = const GitHubSyncStatus();
      return false;
    }
    final records = await _loadRecords(current);
    status = GitHubSyncStatus(
      connection: current.label,
      message: 'Pronto per sincronizzare.',
      conflicts: {
        for (final entry in records.entries)
          if (entry.value.conflict) entry.key: entry.value,
      },
    );
    return true;
  }

  Future<GitHubSyncStatus> run() async {
    final current = await config();
    if (current == null) {
      throw const FormatException('Collega GitHub.');
    }
    current.validate();

    status = GitHubSyncStatus(
      connection: current.label,
      message: 'Sincronizzazione in corso…',
      busy: true,
      conflicts: status.conflicts,
    );

    final api = GitHubApi(current);
    try {
      final private = await api.verify();
      if (!private && !current.allowPublic) {
        throw const FormatException(
          'Il repository ora è pubblico. Sincronizzazione sospesa.',
        );
      }

      final local = await database.syncDocuments();
      final records = await _loadRecords(current);
      final head = await api.head();
      final files = await api.listNotes(head);
      final remote = <String, SyncDocument>{};
      final remoteSha = <String, String>{};

      for (final file in files) {
        final document = await api.readNote(file, head);
        if (remote.containsKey(document.id)) {
          throw const FormatException('ID remoto duplicato.');
        }
        remote[document.id] = document;
        remoteSha[document.id] = file.sha;
      }

      final attachmentStore = await AttachmentStore.open();
      final ids = <String>{
        ...local.keys,
        ...remote.keys,
        ...records.keys,
      };

      for (final id in ids) {
        final localDocument = local[id];
        final remoteDocument = remote[id];
        final previous = records[id];

        if (localDocument == null && remoteDocument == null) {
          records.remove(id);
          continue;
        }

        if (remoteDocument == null && localDocument != null) {
          await _publishAssets(
            localDocument,
            api,
            attachmentStore,
          );
          final sha = await api.writeNote(localDocument, null);
          records[id] = GitHubSyncRecord(
            base: localDocument,
            sha: sha,
          );
          continue;
        }

        if (localDocument == null && remoteDocument != null) {
          await _receiveAssets(
            remoteDocument,
            api,
            attachmentStore,
            head,
          );
          await database.applySyncDocument(remoteDocument);
          records[id] = GitHubSyncRecord(
            base: remoteDocument,
            sha: remoteSha[id],
          );
          continue;
        }

        final decision = decideSync(
          previous?.base,
          localDocument,
          remoteDocument,
        );

        switch (decision) {
          case SyncDecision.same:
            records[id] = GitHubSyncRecord(
              base: localDocument,
              sha: remoteSha[id],
            );
            break;
          case SyncDecision.upload:
            await _publishAssets(
              localDocument!,
              api,
              attachmentStore,
            );
            final sha = await api.writeNote(
              localDocument,
              remoteSha[id],
            );
            records[id] = GitHubSyncRecord(
              base: localDocument,
              sha: sha,
            );
            break;
          case SyncDecision.download:
            await _receiveAssets(
              remoteDocument!,
              api,
              attachmentStore,
              head,
            );
            await database.applySyncDocument(remoteDocument);
            records[id] = GitHubSyncRecord(
              base: remoteDocument,
              sha: remoteSha[id],
            );
            break;
          case SyncDecision.conflict:
            records[id] = GitHubSyncRecord(
              base: previous?.base,
              sha: remoteSha[id],
              conflict: true,
              local: localDocument,
              remote: remoteDocument,
            );
            break;
        }
      }

      await _saveRecords(current, records);
      final conflicts = {
        for (final entry in records.entries)
          if (entry.value.conflict) entry.key: entry.value,
      };
      status = GitHubSyncStatus(
        connection: current.label,
        message: conflicts.isEmpty
            ? 'Sincronizzazione completata'
            : 'Conflitti da risolvere: entrambe le versioni sono conservate.',
        conflicts: conflicts,
      );
      return status;
    } catch (error) {
      status = GitHubSyncStatus(
        connection: current.label,
        message: error.toString().replaceFirst('FormatException: ', ''),
        conflicts: status.conflicts,
      );
      rethrow;
    } finally {
      api.close();
    }
  }

  Future<void> resolve(String id, String choice) async {
    if (!const {'local', 'remote', 'both'}.contains(choice)) {
      throw const FormatException('Scelta conflitto non valida.');
    }
    final current = await config();
    if (current == null) {
      throw const FormatException('Collega GitHub.');
    }
    final records = await _loadRecords(current);
    final record = records[id];
    if (record == null ||
        !record.conflict ||
        record.local == null ||
        record.remote == null) {
      throw const FormatException('Conflitto non più disponibile.');
    }

    if (choice == 'both') {
      await database.saveSyncCopy(record.local!);
      await database.applySyncDocument(record.remote!);
    } else if (choice == 'remote') {
      await database.applySyncDocument(record.remote!);
    } else {
      await database.applySyncDocument(record.local!);
    }

    records[id] = GitHubSyncRecord(
      base: choice == 'local' ? record.local : record.remote,
      sha: record.sha,
    );
    await _saveRecords(current, records);
    await run();
  }

  Future<void> _publishAssets(
    SyncDocument document,
    GitHubApi api,
    AttachmentStore store,
  ) async {
    if (document.sketchJson != null) return;
    final refs = Attachments.refs(document.body)
        .map((ref) => ref.key)
        .toSet();
    var bytesThisPass = 0;
    for (final key in refs) {
      final bytes = await store.read(key);
      bytesThisPass += bytes.length;
      if (bytesThisPass > 64 * 1024 * 1024) {
        throw const FormatException(
          'Allegati oltre 64 MiB nello stesso passaggio.',
        );
      }
      await api.ensureAssetUploaded(key, bytes);
    }
  }

  Future<void> _receiveAssets(
    SyncDocument document,
    GitHubApi api,
    AttachmentStore store,
    String head,
  ) async {
    if (document.sketchJson != null) return;
    final keys = Attachments.refs(document.body)
        .map((ref) => ref.key)
        .toSet();
    for (final key in keys) {
      if (await store.contains(key)) continue;
      final bytes = await api.downloadAsset(key, head);
      await store.put(key, bytes);
    }
  }

  Future<File> _stateFile(GitHubConfig config) async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'github-sync'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(
      p.join(dir.path, '${SyncCodec.hash(config.key)}.json'),
    );
  }

  Future<Map<String, GitHubSyncRecord>> _loadRecords(
    GitHubConfig config,
  ) async {
    final file = await _stateFile(config);
    if (!await file.exists()) return {};
    final bytes = await file.readAsBytes();
    if (bytes.length > 64 * 1024 * 1024) {
      throw const FormatException('Stato sync locale troppo grande.');
    }
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map || decoded['version'] != 1) {
      throw const FormatException('Stato sync locale non valido.');
    }
    final rows = decoded['records'];
    if (rows is! Map) {
      throw const FormatException('Record sync locali non validi.');
    }
    return rows.map(
      (key, value) => MapEntry(
        key.toString(),
        GitHubSyncRecord.fromJson(
          (value as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        ),
      ),
    );
  }

  Future<void> _saveRecords(
    GitHubConfig config,
    Map<String, GitHubSyncRecord> records,
  ) async {
    final file = await _stateFile(config);
    final temp = File('${file.path}.tmp');
    final text = jsonEncode({
      'version': 1,
      'records': {
        for (final entry in records.entries)
          entry.key: entry.value.toJson(),
      },
    });
    await temp.writeAsString(text, encoding: utf8, flush: true);
    await temp.rename(file.path);
  }
}
