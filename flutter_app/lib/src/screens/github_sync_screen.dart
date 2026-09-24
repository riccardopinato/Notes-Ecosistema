import 'package:flutter/material.dart';

import '../data/legacy_notes_database.dart';
import '../sync/github_sync_service.dart';

class GitHubSyncScreen extends StatefulWidget {
  const GitHubSyncScreen({
    required this.database,
    required this.onLocalChanged,
    super.key,
  });

  final LegacyNotesDatabase database;
  final Future<void> Function() onLocalChanged;

  @override
  State<GitHubSyncScreen> createState() => _GitHubSyncScreenState();
}

class _GitHubSyncScreenState extends State<GitHubSyncScreen> {
  late final GitHubSyncService _sync;

  final _owner = TextEditingController();
  final _repo = TextEditingController();
  final _branch = TextEditingController(text: 'main');
  final _folder = TextEditingController(text: 'notes-ecosystem');
  final _token = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  bool _consent = false;
  bool _allowPublic = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sync = GitHubSyncService(widget.database);
    _load();
  }

  Future<void> _load() async {
    try {
      await _sync.loadStatus();
      final config = await _sync.config();
      if (config != null) {
        _owner.text = config.owner;
        _repo.text = config.repo;
        _branch.text = config.branch;
        _folder.text = config.folder;
        _allowPublic = config.allowPublic;
      }
    } catch (error) {
      _error = error.toString().replaceFirst('FormatException: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _owner.dispose();
    _repo.dispose();
    _branch.dispose();
    _folder.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('FormatException: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() => _run(() async {
        if (!_consent) {
          throw const FormatException(
            'Conferma l’autorizzazione allo scambio con GitHub.',
          );
        }
        final config = GitHubConfig(
          owner: _owner.text.trim(),
          repo: _repo.text.trim(),
          branch: _branch.text.trim(),
          folder: _folder.text.trim(),
          token: _token.text.trim(),
          allowPublic: _allowPublic,
        );
        await _sync.connect(config);
        _token.clear();
        await _sync.run();
        await widget.onLocalChanged();
      });

  Future<void> _syncNow() => _run(() async {
        await _sync.run();
        await widget.onLocalChanged();
      });

  Future<void> _disconnect() => _run(() async {
        await _sync.disconnect();
        _token.clear();
      });

  Future<void> _resolve(String id, String choice) => _run(() async {
        await _sync.resolve(id, choice);
        await widget.onLocalChanged();
      });

  @override
  Widget build(BuildContext context) {
    final status = _sync.status;
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('GitHub Sync')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
        children: [
          Text(
            'Le tue note, anche su GitHub',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(status.message),
          if (_busy) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          if (status.connection == null)
            _connectionForm(context)
          else ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_done_outlined),
                title: Text(status.connection!),
                subtitle: const Text(
                  'Note, attività, disegni, stati Planner e allegati vengono '
                  'sincronizzati nel repository configurato.',
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _syncNow,
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizza ora'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _disconnect,
              child: const Text('Scollega GitHub'),
            ),
            if (status.conflicts.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                '${status.conflicts.length} conflitti da risolvere',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ...status.conflicts.entries.map(
                (entry) => _ConflictCard(
                  id: entry.key,
                  record: entry.value,
                  enabled: !_busy,
                  onResolve: (choice) => _resolve(entry.key, choice),
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),
          Text(
            'Limiti di compatibilità 0.25: massimo 500 elementi, 256 KB per '
            'documento e 8 MiB per allegato. I contenuti GitHub sono Markdown '
            'non cifrato: usa un repository privato per dati personali.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _connectionForm(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Crea o usa un repository GitHub esistente e un token fine-grained '
            'limitato a quel repository con Contents: Read and write.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _owner,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Proprietario GitHub'),
          ),
          TextField(
            controller: _repo,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Nome repository'),
          ),
          TextField(
            controller: _branch,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Ramo esistente'),
          ),
          TextField(
            controller: _folder,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Cartella delle note'),
          ),
          TextField(
            controller: _token,
            enabled: !_busy,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Token GitHub'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _consent,
            onChanged: _busy
                ? null
                : (value) => setState(() => _consent = value ?? false),
            title: const Text(
              'Autorizzo lo scambio delle note con questo repository.',
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _allowPublic,
            onChanged: _busy
                ? null
                : (value) => setState(() => _allowPublic = value ?? false),
            title: const Text(
              'Consento anche un repository pubblico.',
            ),
            subtitle: const Text(
              'Se attivo, note e allegati possono diventare pubblici.',
            ),
          ),
          FilledButton(
            onPressed: !_busy && _consent && _token.text.trim().isNotEmpty
                ? _connect
                : null,
            child: const Text('Collega e sincronizza'),
          ),
        ],
      );
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.id,
    required this.record,
    required this.enabled,
    required this.onResolve,
  });

  final String id;
  final GitHubSyncRecord record;
  final bool enabled;
  final ValueChanged<String> onResolve;

  @override
  Widget build(BuildContext context) {
    final local = record.local;
    final remote = record.remote;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              local?.title.isNotEmpty == true
                  ? local!.title
                  : remote?.title.isNotEmpty == true
                      ? remote!.title
                      : id,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Telefono · ${_summary(local)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              'GitHub · ${_summary(remote)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                OutlinedButton(
                  onPressed: enabled ? () => onResolve('both') : null,
                  child: const Text('Conserva entrambe'),
                ),
                TextButton(
                  onPressed: enabled ? () => onResolve('local') : null,
                  child: const Text('Usa telefono'),
                ),
                TextButton(
                  onPressed: enabled ? () => onResolve('remote') : null,
                  child: const Text('Usa GitHub'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _summary(dynamic document) {
    if (document == null) return 'assente';
    final body = document.body.toString().replaceAll('\n', ' ').trim();
    final preview = body.length > 160 ? '${body.substring(0, 160)}…' : body;
    return '${document.deletedAt != null ? 'Cestino · ' : ''}'
        '${document.updatedAt} · $preview';
  }
}
