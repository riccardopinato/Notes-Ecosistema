import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/attachments.dart';
import '../domain/sync.dart';
import 'github_sync_service.dart';

class SharedRemoteBlob {
  const SharedRemoteBlob({
    required this.bytes,
    required this.sha,
  });

  final Uint8List bytes;
  final String sha;
}

class SharedGitHubAccount {
  const SharedGitHubAccount({
    required this.id,
    required this.login,
  });

  final String id;
  final String login;
}

class SharedGitHubApi {
  SharedGitHubApi(this.config);

  final GitHubConfig config;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  Map<String, RemoteAsset>? _assets;

  String get _root =>
      '/repos/${Uri.encodeComponent(config.owner)}/${Uri.encodeComponent(config.repo)}';

  String _path(String value) =>
      value.split('/').map(Uri.encodeComponent).join('/');

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
      ..set(HttpHeaders.userAgentHeader, 'Notes-Ecosistema-Shared-Live');
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
        throw const FormatException(
          'Risposta GitHub Shared troppo grande.',
        );
      }
      bytes.addAll(chunk);
    }
    final text = utf8.decode(bytes, allowMalformed: false);
    if (response.statusCode < 200 || response.statusCode > 299) {
      final message = switch (response.statusCode) {
        401 => 'Accesso GitHub scaduto o token non valido.',
        403 =>
          'GitHub ha rifiutato l’accesso o il limite richieste è stato raggiunto.',
        404 => 'Shared Space remoto non disponibile.',
        409 || 422 => 'Shared Space cambiato durante la sincronizzazione.',
        429 => 'Limite GitHub raggiunto.',
        _ => 'GitHub non disponibile (HTTP ${response.statusCode}).',
      };
      throw GitHubHttpFailure(response.statusCode, message);
    }
    return text;
  }

  Future<SharedGitHubAccount> authenticatedAccount() async {
    final decoded = jsonDecode(await _request('GET', '/user'));
    if (decoded is! Map) {
      throw const FormatException('Account GitHub non valido.');
    }
    final id = decoded['id']?.toString() ?? '';
    final login = decoded['login']?.toString().trim() ?? '';
    if (!RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(id) ||
        !RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$')
            .hasMatch(login)) {
      throw const FormatException('Account GitHub non valido.');
    }
    return SharedGitHubAccount(id: id, login: login);
  }

  Future<bool> verifyPrivateWritable() async {
    final decoded = jsonDecode(await _request('GET', _root));
    if (decoded is! Map) {
      throw const FormatException('Repository GitHub non valido.');
    }
    final permissions = decoded['permissions'];
    if (permissions is! Map || permissions['push'] != true) {
      throw const FormatException(
        'Shared Live Sync richiede accesso Contents: Read and write.',
      );
    }
    await head();
    return decoded['private'] == true;
  }
  Future<String> head() async {
    final branch =
        config.branch.split('/').map(Uri.encodeComponent).join('/');
    final decoded = jsonDecode(
      await _request('GET', '$_root/git/ref/heads/$branch'),
    );
    if (decoded is! Map ||
        decoded['object'] is! Map ||
        (decoded['object'] as Map)['sha'] is! String) {
      throw const FormatException('Ramo GitHub non valido.');
    }
    return (decoded['object'] as Map)['sha'] as String;
  }

  Future<List<String>> listSharedSpaceFolders(String ref) async {
    final base = '${config.folder}/shared';
    final path = _path(base);
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
        'Indice Shared Spaces remoto troppo grande o non valido.',
      );
    }

    final folders = <String>[];
    final pattern = RegExp(r'^[a-f0-9]{32}    String ref, {
    int limit = 1024 * 1024,
  }) async {
    final path = _path('${config.folder}/space.json');
    String text;
    try {
      text = await _request(
        'GET',
        '$_root/contents/$path?ref=${Uri.encodeQueryComponent(ref)}',
        limit: limit * 2 + 8192,
      );
    } on GitHubHttpFailure catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map ||
        decoded['encoding'] != 'base64' ||
        decoded['sha'] is! String) {
      throw const FormatException('Stato Shared remoto non valido.');
    }
    final sha = decoded['sha'] as String;
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(sha)) {
      throw const FormatException('SHA stato Shared non valido.');
    }
    final raw = decoded['content']?.toString() ?? '';
    final bytes = Uint8List.fromList(
      base64Decode(raw.replaceAll(RegExp(r'\s'), '')),
    );
    if (bytes.length > limit) {
      throw const FormatException('Stato Shared remoto troppo grande.');
    }
    return SharedRemoteBlob(bytes: bytes, sha: sha);
  }

  Future<String> writeState(
    Uint8List bytes, {
    String? expectedSha,
    int limit = 1024 * 1024,
  }) async {
    if (bytes.isEmpty || bytes.length > limit) {
      throw const FormatException('Stato Shared vuoto o troppo grande.');
    }
    final path = _path('${config.folder}/space.json');
    final decoded = jsonDecode(
      await _request(
        'PUT',
        '$_root/contents/$path',
        body: {
          'message': 'Notes Shared: aggiorna spazio',
          'branch': config.branch,
          'content': base64Encode(bytes),
          if (expectedSha != null) 'sha': expectedSha,
        },
        limit: limit * 2 + 8192,
      ),
    );
    if (decoded is! Map || decoded['content'] is! Map) {
      throw const FormatException('Upload stato Shared non verificabile.');
    }
    final sha = (decoded['content'] as Map)['sha']?.toString() ?? '';
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(sha)) {
      throw const FormatException('SHA upload Shared non valido.');
    }
    return sha;
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
        'Cartella Shared troppo grande o non valida.',
      );
    }

    final result = <RemoteFile>[];
    final pattern = RegExp(r'^[a-f0-9]{64}\.md$');
    for (final item in decoded) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? '';
      if (!pattern.hasMatch(name)) continue;
      final size = (item['size'] as num?)?.toInt() ?? -1;
      final sha = item['sha']?.toString() ?? '';
      if (item['type'] != 'file' ||
          size < 0 ||
          size > SyncCodec.maxBytes ||
          !RegExp(r'^[a-f0-9]{40}$').hasMatch(sha)) {
        throw const FormatException('Documento Shared remoto non valido.');
      }
      result.add(RemoteFile(name, sha));
    }
    if (result.length > 500) {
      throw const FormatException(
        'Shared Space oltre 500 documenti.',
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
      throw const FormatException(
        'Documento Shared cambiato durante la lettura.',
      );
    }
    final raw = decoded['content']?.toString() ?? '';
    final bytes = base64Decode(raw.replaceAll(RegExp(r'\s'), ''));
    if (bytes.length > SyncCodec.maxBytes) {
      throw const FormatException('Documento Shared oltre 256 KB.');
    }
    final document = SyncCodec.decode(
      utf8.decode(bytes, allowMalformed: false),
    );
    if (SyncCodec.filename(document.id) != file.name) {
      throw const FormatException(
        'ID documento Shared non corrispondente.',
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
      throw const FormatException('Documento Shared oltre 256 KB.');
    }
    final path = _path(
      '${config.folder}/${SyncCodec.filename(document.id)}',
    );
    final decoded = jsonDecode(
      await _request(
        'PUT',
        '$_root/contents/$path',
        body: {
          'message': 'Notes Shared: aggiorna contenuto',
          'branch': config.branch,
          'content': base64Encode(bytes),
          if (expectedSha != null) 'sha': expectedSha,
        },
      ),
    );
    if (decoded is! Map || decoded['content'] is! Map) {
      throw const FormatException(
        'Upload documento Shared non verificabile.',
      );
    }
    final sha = (decoded['content'] as Map)['sha']?.toString() ?? '';
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(sha)) {
      throw const FormatException('SHA documento Shared non valido.');
    }
    return sha;
  }

  Future<void> deleteNote(RemoteFile file) async {
    final path = _path('${config.folder}/${file.name}');
    await _request(
      'DELETE',
      '$_root/contents/$path',
      body: {
        'message': 'Notes Shared: rimuovi contenuto',
        'branch': config.branch,
        'sha': file.sha,
      },
    );
  }

  Future<Map<String, RemoteAsset>> listAssets(String ref) async {
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
      throw const FormatException(
        'Cartella allegati Shared troppo grande.',
      );
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
        throw const FormatException(
          'Allegato Shared remoto non valido.',
        );
      }
      result[name] = RemoteAsset(name, sha, size);
    }
    if (result.length > Attachments.maxFiles) {
      throw const FormatException(
        'Shared Space oltre 500 allegati.',
      );
    }
    _assets = result;
    return _assets!;
  }

  String _gitSha(Uint8List bytes) {
    final prefix = utf8.encode('blob ${bytes.length}\u0000');
    return sha1.convert([...prefix, ...bytes]).toString();
  }

  Future<void> ensureAssetUploaded(
    String key,
    Uint8List bytes,
    String ref,
  ) async {
    Attachments.verify(key, bytes);
    final index = await listAssets(ref);
    final existing = index[key];
    final expectedSha = _gitSha(bytes);
    if (existing != null) {
      if (existing.sha != expectedSha || existing.size != bytes.length) {
        throw const FormatException(
          'Allegato Shared remoto con contenuto diverso.',
        );
      }
      return;
    }
    if (index.length >= Attachments.maxFiles) {
      throw const FormatException(
        'Shared Space oltre 500 allegati.',
      );
    }

    final path = _path('${config.folder}/assets/$key');
    final decoded = jsonDecode(
      await _request(
        'PUT',
        '$_root/contents/$path',
        body: {
          'message': 'Notes Shared: aggiungi allegato',
          'branch': config.branch,
          'content': base64Encode(bytes),
        },
      ),
    );
    if (decoded is! Map || decoded['content'] is! Map) {
      throw const FormatException(
        'Upload allegato Shared non verificabile.',
      );
    }
    final sha = (decoded['content'] as Map)['sha']?.toString() ?? '';
    if (sha != expectedSha) {
      throw const FormatException(
        'Verifica allegato Shared caricata non riuscita.',
      );
    }
    final cache = _assets;
    if (cache != null) {
      cache[key] = RemoteAsset(key, sha, bytes.length);
    }
  }

  Future<Uint8List> downloadAsset(
    String key,
    String ref,
  ) async {
    final index = await listAssets(ref);
    final info = index[key];
    if (info == null) {
      throw const FormatException(
        'Allegato Shared remoto non disponibile.',
      );
    }
    final decoded = jsonDecode(
      await _request(
        'GET',
        '$_root/git/blobs/${Uri.encodeComponent(info.sha)}',
      ),
    );
    if (decoded is! Map ||
        decoded['encoding'] != 'base64' ||
        decoded['sha'] != info.sha) {
      throw const FormatException('Blob Shared remoto non valido.');
    }
    final bytes = Uint8List.fromList(
      base64Decode(
        (decoded['content']?.toString() ?? '')
            .replaceAll(RegExp(r'\s'), ''),
      ),
    );
    if (bytes.length != info.size) {
      throw const FormatException(
        'Dimensione allegato Shared non valida.',
      );
    }
    Attachments.verify(key, bytes);
    return bytes;
  }

  Future<void> deleteAsset(RemoteAsset asset) async {
    final path = _path('${config.folder}/assets/${asset.name}');
    await _request(
      'DELETE',
      '$_root/contents/$path',
      body: {
        'message': 'Notes Shared: rimuovi allegato orfano',
        'branch': config.branch,
        'sha': asset.sha,
      },
    );
    _assets?.remove(asset.name);
  }

  void close() => _client.close(force: true);
}
);
    for (final item in decoded) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? '';
      if (!pattern.hasMatch(name)) continue;
      if (item['type'] != 'dir') {
        throw const FormatException(
          'Indice Shared Spaces remoto non valido.',
        );
      }
      folders.add('$base/$name');
    }
    if (folders.length > 200) {
      throw const FormatException(
        'Troppi Shared Spaces remoti da indicizzare.',
      );
    }
    folders.sort();
    return folders;
  }

  Future<SharedRemoteBlob?> readState(
    String ref, {
    int limit = 1024 * 1024,
  }) async {
    final path = _path('${config.folder}/space.json');
    String text;
    try {
      text = await _request(
        'GET',
        '$_root/contents/$path?ref=${Uri.encodeQueryComponent(ref)}',
        limit: limit * 2 + 8192,
      );
    } on GitHubHttpFailure catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }

    final decoded = jsonDecode(text);
    if (decoded is! Map ||
        decoded['encoding'] != 'base64' ||
        decoded['sha'] is! String) {
      throw const FormatException('Stato Shared remoto non valido.');
    }
    final sha = decoded['sha'] as String;
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(sha)) {
      throw const FormatException('SHA stato Shared non valido.');
    }
    final raw = decoded['content']?.toString() ?? '';
    final bytes = Uint8List.fromList(
      base64Decode(raw.replaceAll(RegExp(r'\s'), '')),
    );
    if (bytes.length > limit) {
      throw const FormatException('Stato Shared remoto troppo grande.');
    }
    return SharedRemoteBlob(bytes: bytes, sha: sha);
  }

  Future<String> writeState(
    Uint8List bytes, {
    String? expectedSha,
    int limit = 1024 * 1024,
  }) async {
    if (bytes.isEmpty || bytes.length > limit) {
      throw const FormatException('Stato Shared vuoto o troppo grande.');
    }
    final path = _path('${config.folder}/space.json');
    final decoded = jsonDecode(
      await _request(
        'PUT',
        '$_root/contents/$path',
        body: {
          'message': 'Notes Shared: aggiorna spazio',
          'branch': config.branch,
          'content': base64Encode(bytes),
          if (expectedSha != null) 'sha': expectedSha,
        },
        limit: limit * 2 + 8192,
      ),
    );
    if (decoded is! Map || decoded['content'] is! Map) {
      throw const FormatException('Upload stato Shared non verificabile.');
    }
    final sha = (decoded['content'] as Map)['sha']?.toString() ?? '';
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(sha)) {
      throw const FormatException('SHA upload Shared non valido.');
    }
    return sha;
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
        'Cartella Shared troppo grande o non valida.',
      );
    }

    final result = <RemoteFile>[];
    final pattern = RegExp(r'^[a-f0-9]{64}\.md$');
    for (final item in decoded) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? '';
      if (!pattern.hasMatch(name)) continue;
      final size = (item['size'] as num?)?.toInt() ?? -1;
      final sha = item['sha']?.toString() ?? '';
      if (item['type'] != 'file' ||
          size < 0 ||
          size > SyncCodec.maxBytes ||
          !RegExp(r'^[a-f0-9]{40}$').hasMatch(sha)) {
        throw const FormatException('Documento Shared remoto non valido.');
      }
      result.add(RemoteFile(name, sha));
    }
    if (result.length > 500) {
      throw const FormatException(
        'Shared Space oltre 500 documenti.',
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
      throw const FormatException(
        'Documento Shared cambiato durante la lettura.',
      );
    }
    final raw = decoded['content']?.toString() ?? '';
    final bytes = base64Decode(raw.replaceAll(RegExp(r'\s'), ''));
    if (bytes.length > SyncCodec.maxBytes) {
      throw const FormatException('Documento Shared oltre 256 KB.');
    }
    final document = SyncCodec.decode(
      utf8.decode(bytes, allowMalformed: false),
    );
    if (SyncCodec.filename(document.id) != file.name) {
      throw const FormatException(
        'ID documento Shared non corrispondente.',
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
      throw const FormatException('Documento Shared oltre 256 KB.');
    }
    final path = _path(
      '${config.folder}/${SyncCodec.filename(document.id)}',
    );
    final decoded = jsonDecode(
      await _request(
        'PUT',
        '$_root/contents/$path',
        body: {
          'message': 'Notes Shared: aggiorna contenuto',
          'branch': config.branch,
          'content': base64Encode(bytes),
          if (expectedSha != null) 'sha': expectedSha,
        },
      ),
    );
    if (decoded is! Map || decoded['content'] is! Map) {
      throw const FormatException(
        'Upload documento Shared non verificabile.',
      );
    }
    final sha = (decoded['content'] as Map)['sha']?.toString() ?? '';
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(sha)) {
      throw const FormatException('SHA documento Shared non valido.');
    }
    return sha;
  }

  Future<void> deleteNote(RemoteFile file) async {
    final path = _path('${config.folder}/${file.name}');
    await _request(
      'DELETE',
      '$_root/contents/$path',
      body: {
        'message': 'Notes Shared: rimuovi contenuto',
        'branch': config.branch,
        'sha': file.sha,
      },
    );
  }

  Future<Map<String, RemoteAsset>> listAssets(String ref) async {
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
      throw const FormatException(
        'Cartella allegati Shared troppo grande.',
      );
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
        throw const FormatException(
          'Allegato Shared remoto non valido.',
        );
      }
      result[name] = RemoteAsset(name, sha, size);
    }
    if (result.length > Attachments.maxFiles) {
      throw const FormatException(
        'Shared Space oltre 500 allegati.',
      );
    }
    _assets = result;
    return _assets!;
  }

  String _gitSha(Uint8List bytes) {
    final prefix = utf8.encode('blob ${bytes.length}\u0000');
    return sha1.convert([...prefix, ...bytes]).toString();
  }

  Future<void> ensureAssetUploaded(
    String key,
    Uint8List bytes,
    String ref,
  ) async {
    Attachments.verify(key, bytes);
    final index = await listAssets(ref);
    final existing = index[key];
    final expectedSha = _gitSha(bytes);
    if (existing != null) {
      if (existing.sha != expectedSha || existing.size != bytes.length) {
        throw const FormatException(
          'Allegato Shared remoto con contenuto diverso.',
        );
      }
      return;
    }
    if (index.length >= Attachments.maxFiles) {
      throw const FormatException(
        'Shared Space oltre 500 allegati.',
      );
    }

    final path = _path('${config.folder}/assets/$key');
    final decoded = jsonDecode(
      await _request(
        'PUT',
        '$_root/contents/$path',
        body: {
          'message': 'Notes Shared: aggiungi allegato',
          'branch': config.branch,
          'content': base64Encode(bytes),
        },
      ),
    );
    if (decoded is! Map || decoded['content'] is! Map) {
      throw const FormatException(
        'Upload allegato Shared non verificabile.',
      );
    }
    final sha = (decoded['content'] as Map)['sha']?.toString() ?? '';
    if (sha != expectedSha) {
      throw const FormatException(
        'Verifica allegato Shared caricata non riuscita.',
      );
    }
    final cache = _assets;
    if (cache != null) {
      cache[key] = RemoteAsset(key, sha, bytes.length);
    }
  }

  Future<Uint8List> downloadAsset(
    String key,
    String ref,
  ) async {
    final index = await listAssets(ref);
    final info = index[key];
    if (info == null) {
      throw const FormatException(
        'Allegato Shared remoto non disponibile.',
      );
    }
    final decoded = jsonDecode(
      await _request(
        'GET',
        '$_root/git/blobs/${Uri.encodeComponent(info.sha)}',
      ),
    );
    if (decoded is! Map ||
        decoded['encoding'] != 'base64' ||
        decoded['sha'] != info.sha) {
      throw const FormatException('Blob Shared remoto non valido.');
    }
    final bytes = Uint8List.fromList(
      base64Decode(
        (decoded['content']?.toString() ?? '')
            .replaceAll(RegExp(r'\s'), ''),
      ),
    );
    if (bytes.length != info.size) {
      throw const FormatException(
        'Dimensione allegato Shared non valida.',
      );
    }
    Attachments.verify(key, bytes);
    return bytes;
  }

  Future<void> deleteAsset(RemoteAsset asset) async {
    final path = _path('${config.folder}/assets/${asset.name}');
    await _request(
      'DELETE',
      '$_root/contents/$path',
      body: {
        'message': 'Notes Shared: rimuovi allegato orfano',
        'branch': config.branch,
        'sha': asset.sha,
      },
    );
    _assets?.remove(asset.name);
  }

  void close() => _client.close(force: true);
}
