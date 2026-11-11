// QA-only Flutter Web entrypoint. This file is never used by production
// web_preview.dart and exposes only a synthetic local-storage test bridge.
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/data/web_workspace_storage.dart';
import 'src/domain/note.dart';

@JS('notesWorkspaceQa')
external set notesWorkspaceQa(JSFunction callback);

late WebWorkspaceStore _store;
WebWorkspaceSnapshot? _current;

Note _syntheticNote(String title, String body) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return Note(
    id: 'browser-qa-synthetic-note',
    title: title,
    body: body,
    favorite: false,
    createdAt: now,
    updatedAt: now,
    pinned: false,
    archived: false,
    tags: const ['browser-qa-synthetic'],
  );
}

Future<String> _handle(String raw) async {
  try {
    final request = jsonDecode(raw);
    if (request is! Map) {
      throw const FormatException('QA request must be an object');
    }
    final action = request['action'];
    if (action is! String) {
      throw const FormatException('QA request action missing');
    }
    switch (action) {
      case 'load':
        final snapshot = await _store.loadFresh();
        _current = snapshot;
        return jsonEncode({
          'ok': true,
          'count': snapshot.notes.length,
          'title': snapshot.notes.isEmpty ? null : snapshot.notes.first.title,
          'body': snapshot.notes.isEmpty ? null : snapshot.notes.first.body,
          'recoveredPrevious': _store.recoveredPrevious,
        });
      case 'save':
        final title = request['title'];
        if (title is! String || title.length > 120) {
          throw const FormatException('Invalid synthetic title');
        }
        final snapshot = _current ?? await _store.loadFresh();
        final updated = snapshot.copyWith(
          notes: [_syntheticNote(title, 'Local browser QA sample')],
        );
        await _store.save(updated);
        _current = updated;
        return jsonEncode({'ok': true, 'title': title});
      case 'export':
        final snapshot = await _store.loadFresh();
        _current = snapshot;
        return jsonEncode({
          'ok': true,
          'backup': WebWorkspaceStore.exportJson(snapshot),
          'count': snapshot.notes.length,
        });
      case 'import':
        final data = request['backup'];
        if (data is! String) {
          throw const FormatException('Backup missing');
        }
        final candidate = WebWorkspaceStore.importJson(data);
        await _store.loadFresh();
        await _store.save(candidate);
        _current = candidate;
        return jsonEncode({'ok': true, 'count': candidate.notes.length});
      case 'recover':
        final data = request['backup'];
        if (data is! String) {
          throw const FormatException('Recovery backup missing');
        }
        final candidate = WebWorkspaceStore.importJson(data);
        await _store.recoverVerifiedBackup(candidate);
        _current = candidate;
        return jsonEncode({'ok': true, 'count': candidate.notes.length});
      case 'quota':
        final snapshot = _current ?? await _store.loadFresh();
        final oversized = snapshot.copyWith(
          notes: [
            _syntheticNote(
              'Oversized QA',
              'x' * WebWorkspaceStore.maxSnapshotBytes,
            ),
          ],
        );
        await _store.save(oversized);
        return jsonEncode({'ok': true, 'unexpectedWrite': true});
      default:
        throw FormatException('Unknown QA action: $action');
    }
  } catch (error) {
    return jsonEncode({'ok': false, 'error': error.toString()});
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  _store = WebWorkspaceStore(prefs);
  notesWorkspaceQa = ((JSString request) {
    return _handle(request.toDart).then((response) => response.toJS).toJS;
  }).toJS;
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Notes Web Storage QA — synthetic only')),
      ),
    ),
  );
}
