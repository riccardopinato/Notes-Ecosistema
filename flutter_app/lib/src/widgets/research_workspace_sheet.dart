import 'package:flutter/material.dart';

import '../data/knowledge_store.dart';
import '../domain/note.dart';
import '../domain/research.dart';

Future<void> showResearchWorkspace({
  required BuildContext context,
  required String noteId,
  required List<Note> notes,
  required KnowledgeStore store,
  required ValueChanged<String> onInsertMarkdown,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ResearchWorkspaceSheet(
        noteId: noteId,
        notes: notes,
        store: store,
        onInsertMarkdown: onInsertMarkdown,
      ),
    );

class _ResearchWorkspaceSheet extends StatefulWidget {
  const _ResearchWorkspaceSheet({
    required this.noteId,
    required this.notes,
    required this.store,
    required this.onInsertMarkdown,
  });

  final String noteId;
  final List<Note> notes;
  final KnowledgeStore store;
  final ValueChanged<String> onInsertMarkdown;

  @override
  State<_ResearchWorkspaceSheet> createState() =>
      _ResearchWorkspaceSheetState();
}

class _ResearchWorkspaceSheetState extends State<_ResearchWorkspaceSheet> {
  List<ResearchSource> _sources = const [];
  List<NoteRelation> _relations = const [];
  Map<String, SyncedBlock> _blocks = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final sources = await widget.store.sourcesFor(widget.noteId);
      final relations = await widget.store.relationsFor(widget.noteId);
      final blocks = await widget.store.syncedBlocks();
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _relations = relations;
        _blocks = blocks;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  Future<void> _addSource() async {
    final title = TextEditingController();
    final url = TextEditingController();
    final author = TextEditingController();
    final quote = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aggiungi fonte'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Titolo *'),
                ),
                TextField(
                  controller: url,
                  decoration: const InputDecoration(labelText: 'URL'),
                ),
                TextField(
                  controller: author,
                  decoration: const InputDecoration(labelText: 'Autore'),
                ),
                TextField(
                  controller: quote,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Estratto / citazione',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      title.dispose();
      url.dispose();
      author.dispose();
      quote.dispose();
      return;
    }
    try {
      await widget.store.addSource(
        noteId: widget.noteId,
        title: title.text,
        url: url.text,
        author: author.text,
        quote: quote.text,
      );
      await _reload();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('FormatException: ', ''),
        );
      }
    } finally {
      title.dispose();
      url.dispose();
      author.dispose();
      quote.dispose();
    }
  }

  Future<void> _addRelation() async {
    final candidates = widget.notes
        .where(
          (note) =>
              note.id != widget.noteId &&
              !note.isDeleted &&
              !note.isVisual &&
              !note.isTask,
        )
        .toList(growable: false)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final selected = await showDialog<Note>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Collega una nota'),
        children: candidates
            .take(100)
            .map(
              (note) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, note),
                child: Text(
                  note.title.trim().isEmpty ? 'Senza titolo' : note.title,
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (selected == null || !mounted) return;
    try {
      await widget.store.addRelation(
        sourceId: widget.noteId,
        targetId: selected.id,
      );
      await _reload();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('FormatException: ', ''),
        );
      }
    }
  }

  Future<void> _newSyncedBlock() async {
    final text = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuovo blocco sincronizzato'),
        content: TextField(
          controller: text,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'Markdown condiviso fra più note…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crea e inserisci'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      text.dispose();
      return;
    }
    try {
      final block = await widget.store.upsertSyncedBlock(markdown: text.text);
      widget.onInsertMarkdown(SyncedBlockCodec.reference(block.id));
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('FormatException: ', ''),
        );
      }
    } finally {
      text.dispose();
    }
  }

  Future<void> _editSyncedBlock(SyncedBlock block) async {
    final text = TextEditingController(text: block.markdown);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifica blocco sincronizzato'),
        content: TextField(
          controller: text,
          autofocus: true,
          minLines: 3,
          maxLines: 10,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aggiorna ovunque'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      try {
        await widget.store.upsertSyncedBlock(
          id: block.id,
          markdown: text.text,
        );
        await _reload();
      } catch (error) {
        if (mounted) {
          setState(
            () =>
                _error = error.toString().replaceFirst('FormatException: ', ''),
          );
        }
      }
    }
    text.dispose();
  }

  String _relationTitle(NoteRelation relation) {
    final other = relation.sourceId == widget.noteId
        ? relation.targetId
        : relation.sourceId;
    final note = widget.notes.where((item) => item.id == other).firstOrNull;
    return note?.title.trim().isNotEmpty == true
        ? note!.title
        : 'Nota collegata';
  }

  @override
  Widget build(BuildContext context) {
    final rollup = RelationRollup.fromRelations(_relations);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Research Workspace',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Text(
                'Fonti, relazioni, rollup e blocchi sincronizzati restano separati dal Markdown originale.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _loading ? null : _addSource,
                    icon: const Icon(Icons.library_add_outlined),
                    label: const Text('Fonte'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _loading ? null : _addRelation,
                    icon: const Icon(Icons.link),
                    label: const Text('Relazione'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _loading ? null : _newSyncedBlock,
                    icon: const Icon(Icons.sync_alt),
                    label: const Text('Synced block'),
                  ),
                  Chip(
                    label: Text(
                      'Rollup relazioni · ${rollup.total}',
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: [
                          Text(
                            'Fonti',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_sources.isEmpty)
                            const ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('Nessuna fonte collegata.'),
                            ),
                          ..._sources.indexed.map(
                            (row) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.menu_book_outlined),
                              title: Text(row.$2.title),
                              subtitle: Text(
                                [
                                  if (row.$2.author != null) row.$2.author!,
                                  if (row.$2.url != null) row.$2.url!,
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'footnote') {
                                    widget.onInsertMarkdown(
                                      '\n\n${row.$2.footnote(row.$1 + 1)}',
                                    );
                                    if (mounted) Navigator.pop(context);
                                  } else if (value == 'delete') {
                                    await widget.store.deleteSource(row.$2.id);
                                    await _reload();
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'footnote',
                                    child: Text('Inserisci footnote'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Rimuovi fonte'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 24),
                          Text(
                            'Relazioni',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_relations.isEmpty)
                            const ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('Nessuna relazione.'),
                            ),
                          ..._relations.map(
                            (relation) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.hub_outlined),
                              title: Text(_relationTitle(relation)),
                              subtitle: Text(relation.label),
                              trailing: IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () async {
                                  await widget.store
                                      .deleteRelation(relation.id);
                                  await _reload();
                                },
                              ),
                            ),
                          ),
                          const Divider(height: 24),
                          Text(
                            'Synced blocks',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_blocks.isEmpty)
                            const ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Nessun blocco sincronizzato. Creane uno e inseriscilo in più note.',
                              ),
                            ),
                          ..._blocks.values.map(
                            (block) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.sync_alt),
                              title: Text(
                                block.markdown.replaceAll('\n', ' '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: const Text(
                                'Tocca per inserire · modifica aggiorna ogni riferimento',
                              ),
                              onTap: () {
                                widget.onInsertMarkdown(
                                  SyncedBlockCodec.reference(block.id),
                                );
                                Navigator.pop(context);
                              },
                              trailing: IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editSyncedBlock(block),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
