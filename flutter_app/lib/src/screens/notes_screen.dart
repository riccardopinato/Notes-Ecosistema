import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/library.dart';
import '../domain/note.dart';
import '../widgets/editorial.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({
    required this.notes,
    required this.collections,
    required this.query,
    required this.searchMode,
    required this.onQueryChanged,
    required this.onOpen,
    required this.onFavorite,
    required this.onPin,
    required this.onTrash,
    required this.onBulkEdit,
    required this.onRenameCollection,
    required this.onDeleteCollection,
    super.key,
  });

  final List<Note> notes;
  final List<NoteCollection> collections;
  final String query;
  final bool searchMode;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Note> onOpen;
  final ValueChanged<String> onFavorite;
  final void Function(String id, bool value) onPin;
  final ValueChanged<String> onTrash;
  final Future<int> Function(List<Note>, BulkChange) onBulkEdit;
  final Future<void> Function(NoteCollection, String) onRenameCollection;
  final Future<void> Function(NoteCollection) onDeleteCollection;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  NoteScope _scope = NoteScope.all;
  String _kind = 'Tutte';
  String? _collectionId;
  SearchOptions _options = const SearchOptions();
  NoteOrder _order = NoteOrder.recent;
  bool _grid = false;
  bool _selecting = false;
  bool _busy = false;
  final Set<String> _selected = {};
  List<SavedSearch> _saved = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final value = SavedSearchCodec.decode(
        prefs.getString('saved_searches_v1'),
      );
      if (mounted) setState(() => _saved = value);
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e.toString().replaceFirst('FormatException: ', ''));
      }
    }
  }

  Future<void> _persistSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_searches_v1',
      SavedSearchCodec.encode(_saved),
    );
  }

  List<Note> get _visible => searchNotes(
        widget.notes,
        scope: _scope,
        query: widget.searchMode ? widget.query : '',
        collectionId: _collectionId,
        options: _options,
        kind: _kind,
        order: _order,
      );

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            e.toString().replaceFirst('FormatException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() => setState(() {
        _scope = NoteScope.all;
        _kind = 'Tutte';
        _collectionId = null;
        _options = const SearchOptions();
        _order = NoteOrder.recent;
      });

  Future<void> _filters() async {
    var scope = _scope;
    var kind = _kind;
    var collectionId = _collectionId;
    var favorites = _options.favoritesOnly;
    var pinned = _options.pinnedOnly;
    var tasks = _options.tasks;
    var allTags = _options.allTags;
    final tags = TextEditingController(text: _options.tags.join(', '));

    final result = await showModalBottomSheet<_FilterState>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, local) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              8,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Affina la ricerca',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                DropdownButtonFormField<NoteScope>(
                  initialValue: scope,
                  decoration: const InputDecoration(labelText: 'Dove cercare'),
                  items: NoteScope.values
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(_scopeLabel(v)),
                          ))
                      .toList(),
                  onChanged: (v) => local(() => scope = v ?? NoteScope.all),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    'Tutte',
                    'Testo',
                    'Checklist',
                    'Disegni',
                    'Lavagne'
                  ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => local(() => kind = v ?? 'Tutte'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: collectionId,
                  decoration: const InputDecoration(labelText: 'Raccolta'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tutte le raccolte'),
                    ),
                    ...widget.collections.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(c.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => local(() => collectionId = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Solo preferite'),
                  value: favorites,
                  onChanged: (v) => local(() => favorites = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Solo fissate'),
                  value: pinned,
                  onChanged: (v) => local(() => pinned = v),
                ),
                DropdownButtonFormField<TaskPresence>(
                  initialValue: tasks,
                  decoration:
                      const InputDecoration(labelText: 'Checklist nella nota'),
                  items: TaskPresence.values
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(_taskLabel(v)),
                          ))
                      .toList(),
                  onChanged: (v) => local(() => tasks = v ?? TaskPresence.any),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tags,
                  decoration: const InputDecoration(
                    labelText: 'Tag',
                    hintText: 'lavoro, casa',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Richiedi tutti i tag'),
                  value: allTags,
                  onChanged: (v) => local(() => allTags = v),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    _FilterState(
                      scope,
                      kind,
                      collectionId,
                      SearchOptions(
                        tags: tags.text
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList(),
                        allTags: allTags,
                        favoritesOnly: favorites,
                        pinnedOnly: pinned,
                        tasks: tasks,
                      ),
                    ),
                  ),
                  child: const Text('Applica'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    tags.dispose();
    if (result == null || !mounted) return;
    try {
      searchNotes(
        widget.notes,
        scope: result.scope,
        collectionId: result.collectionId,
        options: result.options,
        kind: result.kind,
      );
      setState(() {
        _scope = result.scope;
        _kind = result.kind;
        _collectionId = result.collectionId;
        _options = result.options;
      });
    } catch (e) {
      setState(() => _error =
          e.toString().replaceFirst('FormatException: ', ''));
    }
  }

  Future<void> _savedSearches() async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Salva ricerca attuale'),
              enabled: _saved.length < 30,
              onTap: () => Navigator.pop(context, 'save'),
            ),
            ..._saved.map(
              (s) => ListTile(
                leading: const Icon(Icons.bookmark),
                title: Text(s.name),
                subtitle: Text(
                  s.query.isEmpty ? _scopeLabel(s.scope) : s.query,
                ),
                onTap: () => Navigator.pop(context, s),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => Navigator.pop(context, _DeleteSearch(s)),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (choice == 'save') {
      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Salva ricerca'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Nome'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Salva'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (name == null || !mounted) return;
      await _run(() async {
        final value = validateSavedSearch(
          SavedSearch.create(
            name: name,
            query: widget.query,
            scope: _scope,
            collectionId: _collectionId,
            options: _options,
            kind: _kind,
            order: _order,
          ),
        );
        if (_saved.any(
          (s) => s.name.toLowerCase() == value.name.toLowerCase(),
        )) {
          throw const FormatException(
            'Esiste già una ricerca con questo nome.',
          );
        }
        setState(() => _saved = [..._saved, value]);
        await _persistSaved();
      });
    } else if (choice is SavedSearch) {
      setState(() {
        _scope = choice.scope;
        _kind = choice.kind;
        _collectionId = choice.collectionId;
        _options = choice.options;
        _order = choice.order;
      });
      widget.onQueryChanged(choice.query);
    } else if (choice is _DeleteSearch) {
      await _run(() async {
        setState(() {
          _saved =
              _saved.where((s) => s.id != choice.value.id).toList();
        });
        await _persistSaved();
      });
    }
  }

  Future<void> _bulk() async {
    final rows = widget.notes
        .where((note) => _selected.contains(note.id))
        .toList();
    if (rows.isEmpty) return;

    final action = await showModalBottomSheet<BulkAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: (_scope == NoteScope.trash
                  ? const [BulkAction.restore]
                  : const [
                      BulkAction.archive,
                      BulkAction.unarchive,
                      BulkAction.pin,
                      BulkAction.unpin,
                      BulkAction.favorite,
                      BulkAction.unfavorite,
                      BulkAction.move,
                      BulkAction.addTag,
                      BulkAction.removeTag,
                      BulkAction.trash,
                    ])
              .map(
                (a) => ListTile(
                  leading: Icon(_bulkIcon(a)),
                  title: Text(_bulkLabel(a)),
                  onTap: () => Navigator.pop(context, a),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (action == null || !mounted) return;

    String? collectionId;
    String? tag;
    if (action == BulkAction.move) {
      collectionId = await showDialog<String?>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Sposta in'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Inbox'),
            ),
            ...widget.collections.map(
              (c) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, c.id),
                child: Text(c.name),
              ),
            ),
          ],
        ),
      );
      if (!mounted || collectionId == null) return;
      if (collectionId.isEmpty) collectionId = null;
    }
    if (action == BulkAction.addTag || action == BulkAction.removeTag) {
      final controller = TextEditingController();
      tag = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_bulkLabel(action)),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tag'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Applica'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (!mounted || tag == null) return;
    }

    await _run(() async {
      await widget.onBulkEdit(
        rows,
        BulkChange(
          action,
          collectionId: collectionId,
          tag: tag,
        ),
      );
      if (mounted) {
        setState(() {
          _selected.clear();
          _selecting = false;
        });
      }
    });
  }

  Future<void> _collections() async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: widget.collections
              .map(
                (c) => ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(c.name),
                  subtitle: Text(
                    widget.notes
                            .where((n) => n.collectionId == c.id)
                            .length
                            .toString() +
                        ' elementi',
                  ),
                  onTap: () => Navigator.pop(context, c.id),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'rename') {
                        Navigator.pop(context, _RenameCollection(c));
                      } else {
                        Navigator.pop(context, _DeleteCollection(c));
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text('Rinomina'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Elimina se vuota'),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (!mounted) return;
    if (choice is String) {
      setState(() => _collectionId = choice);
    } else if (choice is _RenameCollection) {
      final controller = TextEditingController(text: choice.value.name);
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rinomina raccolta'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Salva'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (name != null) {
        await _run(
          () => widget.onRenameCollection(choice.value, name),
        );
      }
    } else if (choice is _DeleteCollection) {
      await _run(() => widget.onDeleteCollection(choice.value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final names = {for (final c in widget.collections) c.id: c.name};

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
      children: [
        if (widget.searchMode) ...[
          TextFormField(
            initialValue: widget.query,
            onChanged: widget.onQueryChanged,
            decoration: InputDecoration(
              labelText: 'Cerca nel titolo, nel testo e nei tag',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: widget.query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => widget.onQueryChanged(''),
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_busy) const LinearProgressIndicator(),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _filters,
              icon: const Icon(Icons.tune),
              label: const Text('Filtri'),
            ),
            PopupMenuButton<NoteOrder>(
              onSelected: (v) => setState(() => _order = v),
              itemBuilder: (_) => NoteOrder.values
                  .map(
                    (v) => PopupMenuItem(
                      value: v,
                      child: Text(_orderLabel(v)),
                    ),
                  )
                  .toList(),
              child: Chip(
                avatar: const Icon(Icons.sort, size: 18),
                label: Text(_orderLabel(_order)),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _savedSearches,
              icon: const Icon(Icons.bookmarks_outlined),
              label: Text(
                _saved.isEmpty
                    ? 'Ricerche salvate'
                    : 'Ricerche · ' + _saved.length.toString(),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _collections,
              icon: const Icon(Icons.folder_outlined),
              label: const Text('Raccolte'),
            ),
            IconButton(
              onPressed: () => setState(() => _grid = !_grid),
              icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
            ),
            TextButton(
              onPressed: _reset,
              child: const Text('Azzera'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          visible.length.toString() + ' risultati',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        Row(
          children: [
            const Spacer(),
            TextButton.icon(
              onPressed: visible.isEmpty
                  ? null
                  : () => setState(() {
                        _selecting = !_selecting;
                        if (!_selecting) _selected.clear();
                      }),
              icon: const Icon(Icons.select_all),
              label: Text(_selecting ? 'Fine selezione' : 'Seleziona'),
            ),
          ],
        ),
        if (_selecting && _selected.isNotEmpty)
          Card(
            child: ListTile(
              title: Text(
                _selected.length.toString() + ' selezionate',
              ),
              trailing: FilledButton(
                onPressed: _busy ? null : _bulk,
                child: const Text('Azioni'),
              ),
            ),
          ),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Text('Nessun risultato. Modifica filtri o ricerca.'),
          )
        else if (_grid)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 420,
              mainAxisExtent: 280,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: visible.length,
            itemBuilder: (_, index) => _card(
              visible[index],
              names[visible[index].collectionId] ?? 'Inbox',
            ),
          )
        else
          ...visible.map(
            (note) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(
                note,
                names[note.collectionId] ?? 'Inbox',
              ),
            ),
          ),
      ],
    );
  }

  Widget _card(Note note, String collection) => _NoteCard(
        note: note,
        collection: collection,
        selected: _selected.contains(note.id),
        selecting: _selecting,
        onSelect: () => setState(() {
          if (!_selected.add(note.id)) _selected.remove(note.id);
        }),
        onOpen: () => widget.onOpen(note),
        onFavorite: () => widget.onFavorite(note.id),
        onPin: () => widget.onPin(note.id, !note.pinned),
        onTrash: () => widget.onTrash(note.id),
      );
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.collection,
    required this.selected,
    required this.selecting,
    required this.onSelect,
    required this.onOpen,
    required this.onFavorite,
    required this.onPin,
    required this.onTrash,
  });

  final Note note;
  final String collection;
  final bool selected;
  final bool selecting;
  final VoidCallback onSelect;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;
  final VoidCallback onPin;
  final VoidCallback onTrash;

  @override
  Widget build(BuildContext context) {
    final preview = note.isVisual
        ? ''
        : note.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Card(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: InkWell(
        onTap: selecting ? onSelect : onOpen,
        onLongPress: onSelect,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (selecting)
                    Checkbox(
                      value: selected,
                      onChanged: (_) => onSelect(),
                    ),
                  Expanded(
                    child: Text(
                      collection,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  if (note.pinned) const Icon(Icons.push_pin, size: 16),
                  if (note.favorite) const Icon(Icons.star, size: 16),
                  if (!selecting)
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'favorite') onFavorite();
                        if (v == 'pin') onPin();
                        if (v == 'trash') onTrash();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'favorite',
                          child: Text(
                            note.favorite
                                ? 'Rimuovi dai preferiti'
                                : 'Aggiungi ai preferiti',
                          ),
                        ),
                        PopupMenuItem(
                          value: 'pin',
                          child: Text(
                            note.pinned
                                ? 'Non fissare più'
                                : 'Fissa in alto',
                          ),
                        ),
                        if (!note.isDeleted)
                          const PopupMenuItem(
                            value: 'trash',
                            child: Text('Sposta nel cestino'),
                          ),
                      ],
                    ),
                ],
              ),
              Text(
                note.title.isEmpty ? 'Senza titolo' : note.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontFamily: 'serif'),
              ),
              if (note.tags.isNotEmpty)
                Text(
                  note.tags.map((e) => '#' + e).join(' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              if (preview.isNotEmpty)
                Text(
                  preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              const Spacer(),
              Text(
                'Modificata · ' + editorialDate(note.updatedAt),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterState {
  const _FilterState(
    this.scope,
    this.kind,
    this.collectionId,
    this.options,
  );
  final NoteScope scope;
  final String kind;
  final String? collectionId;
  final SearchOptions options;
}

class _DeleteSearch {
  const _DeleteSearch(this.value);
  final SavedSearch value;
}

class _RenameCollection {
  const _RenameCollection(this.value);
  final NoteCollection value;
}

class _DeleteCollection {
  const _DeleteCollection(this.value);
  final NoteCollection value;
}

String _scopeLabel(NoteScope value) => switch (value) {
      NoteScope.all => 'Note attive',
      NoteScope.inbox => 'Inbox',
      NoteScope.favorites => 'Preferite',
      NoteScope.trash => 'Cestino',
      NoteScope.archive => 'Archivio',
    };

String _taskLabel(TaskPresence value) => switch (value) {
      TaskPresence.any => 'Qualsiasi',
      TaskPresence.hasTasks => 'Con attività',
      TaskPresence.openTasks => 'Da completare',
      TaskPresence.noTasks => 'Senza attività',
    };

String _orderLabel(NoteOrder value) => switch (value) {
      NoteOrder.recent => 'Ultima modifica',
      NoteOrder.created => 'Più recenti',
      NoteOrder.oldest => 'Meno recenti',
      NoteOrder.title => 'Titolo A–Z',
    };

String _bulkLabel(BulkAction value) => switch (value) {
      BulkAction.archive => 'Archivia',
      BulkAction.unarchive => 'Rimuovi da archivio',
      BulkAction.pin => 'Fissa',
      BulkAction.unpin => 'Non fissare più',
      BulkAction.favorite => 'Preferite',
      BulkAction.unfavorite => 'Rimuovi preferite',
      BulkAction.move => 'Sposta raccolta',
      BulkAction.addTag => 'Aggiungi tag',
      BulkAction.removeTag => 'Rimuovi tag',
      BulkAction.trash => 'Cestino',
      BulkAction.restore => 'Ripristina',
    };

IconData _bulkIcon(BulkAction value) => switch (value) {
      BulkAction.archive => Icons.archive_outlined,
      BulkAction.unarchive => Icons.unarchive,
      BulkAction.pin => Icons.push_pin_outlined,
      BulkAction.unpin => Icons.push_pin,
      BulkAction.favorite => Icons.star_outline,
      BulkAction.unfavorite => Icons.star,
      BulkAction.move => Icons.drive_file_move,
      BulkAction.addTag => Icons.sell_outlined,
      BulkAction.removeTag => Icons.label_off,
      BulkAction.trash => Icons.delete_outline,
      BulkAction.restore => Icons.restore,
    };
