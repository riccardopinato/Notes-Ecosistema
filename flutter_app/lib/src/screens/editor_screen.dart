import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/diary.dart';
import '../domain/editing.dart';
import '../domain/note.dart';
import '../state/workspace_controller.dart';
import '../widgets/editorial.dart';

enum _EditorMode { text, checklist }

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({
    required this.collections,
    this.note,
    super.key,
  });

  final Note? note;
  final List<NoteCollection> collections;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late final String _id;
  late final TextEditingController _title;
  late final TextEditingController _body;
  late String? _collectionId;
  late List<String> _tags;
  _EditorMode _mode = _EditorMode.text;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  bool get _readOnlyVisual => widget.note?.isVisual == true;
  DateTime? get _diaryDate => Diary.date(_tags);

  @override
  void initState() {
    super.initState();
    _id = widget.note?.id ?? const Uuid().v4();
    _title = TextEditingController(text: widget.note?.title ?? '');
    _body = TextEditingController(text: widget.note?.body ?? '');
    _collectionId = widget.note?.collectionId;
    _tags = List<String>.from(widget.note?.tags ?? const []);
    if (Checklist.hasMarker(_body.text)) {
      _mode = _EditorMode.checklist;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (_saving || _readOnlyVisual) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final normalizedTags = NoteTags.normalize(_tags);
      final now = DateTime.now().millisecondsSinceEpoch;
      final old = widget.note;
      final note = old == null
          ? Note(
              id: _id,
              title: _title.text,
              body: _body.text,
              collectionId: _collectionId,
              favorite: false,
              createdAt: now,
              updatedAt: now,
              pinned: false,
              archived: false,
              tags: normalizedTags,
            )
          : old.copyWith(
              title: _title.text,
              body: _body.text,
              collectionId: _collectionId,
              tags: normalizedTags,
              updatedAt: now,
            );

      await ref.read(workspaceProvider.notifier).save(note);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString().replaceFirst('FormatException: ', '');
        });
      }
    }
  }

  void _applyMarkdown(MarkdownAction action) {
    final selection = _body.selection;
    final start = selection.isValid ? selection.start : _body.text.length;
    final end = selection.isValid ? selection.end : start;
    try {
      final edit = MarkdownEditing.apply(
        _body.text,
        start,
        end,
        action,
      );
      _body.value = TextEditingValue(
        text: edit.text,
        selection: TextSelection(
          baseOffset: edit.start,
          extentOffset: edit.end,
        ),
      );
      _changed();
      setState(() => _error = null);
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  Future<void> _insertLink() async {
    final selection = _body.selection;
    final start = selection.isValid ? selection.start : _body.text.length;
    final end = selection.isValid ? selection.end : start;
    final a = start < end ? start : end;
    final b = start < end ? end : start;
    final selected = _body.text.substring(
      a.clamp(0, _body.text.length).toInt(),
      b.clamp(0, _body.text.length).toInt(),
    );
    final label = TextEditingController(text: selected);
    final url = TextEditingController(text: 'https://');
    String? error;

    final edit = await showDialog<MarkdownEdit>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Inserisci link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Testo'),
              ),
              TextField(
                controller: url,
                decoration:
                    const InputDecoration(labelText: 'Indirizzo https://'),
              ),
              if (error != null)
                Text(
                  error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(
                    context,
                    MarkdownEditing.link(
                      _body.text,
                      start,
                      end,
                      label.text,
                      url.text,
                    ),
                  );
                } catch (e) {
                  setLocal(() {
                    error =
                        e.toString().replaceFirst('FormatException: ', '');
                  });
                }
              },
              child: const Text('Inserisci'),
            ),
          ],
        ),
      ),
    );

    label.dispose();
    url.dispose();
    if (edit == null || !mounted) return;
    _body.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.end),
    );
    _changed();
    setState(() => _error = null);
  }

  Future<void> _addChecklistItem() async {
    final controller = TextEditingController();
    String? error;
    final body = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Nuova attività'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Testo'),
                onSubmitted: (_) {},
              ),
              if (error != null)
                Text(
                  error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(
                    context,
                    Checklist.append(_body.text, controller.text),
                  );
                } catch (e) {
                  setLocal(() {
                    error =
                        e.toString().replaceFirst('FormatException: ', '');
                  });
                }
              },
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (body == null || !mounted) return;
    _body.text = body;
    _body.selection = TextSelection.collapsed(offset: body.length);
    _changed();
    setState(() => _error = null);
  }

  Future<void> _chooseCollection() async {
    final selected = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Raccolta'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: const ListTile(
              leading: Icon(Icons.inbox),
              title: Text('Inbox'),
            ),
          ),
          ...widget.collections.map(
            (collection) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, collection.id),
              child: ListTile(
                leading: const Icon(Icons.folder),
                title: Text(collection.name),
                trailing: collection.id == _collectionId
                    ? const Icon(Icons.check)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted || selected == null) return;
    setState(() {
      _collectionId = selected.isEmpty ? null : selected;
      _dirty = true;
    });
  }

  Future<void> _chooseDiaryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _diaryDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
    );
    if (picked == null || !mounted) return;
    try {
      final next = Diary.datedTags(_tags, picked);
      NoteTags.normalize(next);
      setState(() {
        _tags = next;
        _dirty = true;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  void _removeDiaryDate() {
    final next = Diary.datedTags(_tags, null);
    setState(() {
      _tags = next;
      _dirty = true;
    });
  }

  Future<void> _editTags() async {
    var tags = Diary.userTags(_tags);
    final date = _diaryDate;
    final controller = TextEditingController();
    String? error;

    final updated = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Tag della nota'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Fino a 20 tag complessivi, incluso il collegamento al Diario.',
                  ),
                  const SizedBox(height: 8),
                  ...tags.map(
                    (tag) => ListTile(
                      dense: true,
                      title: Text('#$tag'),
                      trailing: IconButton(
                        onPressed: () => setLocal(
                          () => tags =
                              tags.where((value) => value != tag).toList(),
                        ),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Nuovo tag, es. lavoro',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      try {
                        var next = NoteTags.add(tags, controller.text);
                        next = Diary.datedTags(next, date);
                        NoteTags.normalize(next);
                        setLocal(() {
                          tags = Diary.userTags(next);
                          controller.clear();
                          error = null;
                        });
                      } catch (e) {
                        setLocal(() {
                          error = e
                              .toString()
                              .replaceFirst('FormatException: ', '');
                        });
                      }
                    },
                    child: const Text('Aggiungi'),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                Diary.datedTags(tags, date),
              ),
              child: const Text('Chiudi'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    if (updated == null || !mounted) return;
    setState(() {
      _tags = updated;
      _dirty = true;
    });
  }

  Future<void> _history() async {
    if (_dirty) {
      setState(() {
        _error =
            'Salva o riapri la nota prima di ripristinare una versione precedente.';
      });
      return;
    }
    final rows =
        await ref.read(databaseProvider).loadHistory(_id);
    if (!mounted) return;

    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna versione precedente.')),
      );
      return;
    }

    final row = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Cronologia'),
        children: rows
            .map(
              (item) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, item),
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                    (item['title']?.toString().isNotEmpty ?? false)
                        ? item['title'].toString()
                        : 'Senza titolo',
                  ),
                  subtitle: Text(
                    editorialDate(
                      (item['savedAt'] as num?)?.toInt() ?? 0,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (row == null || !mounted) return;

    List<String> tags = const [];
    try {
      tags = (jsonDecode(row['tagsJson']?.toString() ?? '[]') as List)
          .map((e) => e.toString())
          .toList();
    } catch (_) {}

    setState(() {
      _title.text = row['title']?.toString() ?? '';
      _body.text = row['body']?.toString() ?? '';
      _collectionId = row['collectionId']?.toString();
      _tags = tags;
      _dirty = true;
      _mode = Checklist.hasMarker(_body.text)
          ? _EditorMode.checklist
          : _EditorMode.text;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_readOnlyVisual) {
      return Scaffold(
        appBar: AppBar(
          title: const EditorialAppTitle(
            'Documento visuale',
            eyebrow: 'SKETCHBOOK / WHITEBOARD',
          ),
        ),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Questo documento usa il formato visuale della 0.25. '
            'Non viene aperto nell’editor di testo per evitare modifiche al payload. '
            'Il relativo editor Flutter viene portato nello step visuale.',
          ),
        ),
      );
    }

    final collectionName = widget.collections
        .where((item) => item.id == _collectionId)
        .map((item) => item.name)
        .firstOrNull;
    final visibleTags = Diary.userTags(_tags);
    final checklist = Checklist.parse(_body.text);

    return Scaffold(
      appBar: AppBar(
        title: const EditorialAppTitle(
          'La tua pagina',
          eyebrow: 'IL TUO TACCUINO',
        ),
        actions: [
          IconButton(
            onPressed: _saving ? null : _history,
            tooltip: 'Cronologia',
            icon: const Icon(Icons.history),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Salvataggio…' : 'Salva'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_saving) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
                children: [
                  TextField(
                    controller: _title,
                    onChanged: (_) => _changed(),
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontFamily: 'serif'),
                    decoration: const InputDecoration(
                      hintText: 'Titolo',
                      border: InputBorder.none,
                      filled: false,
                    ),
                    maxLines: null,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.folder, size: 18),
                        label: Text(collectionName ?? 'Inbox'),
                        onPressed: _saving ? null : _chooseCollection,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.sell, size: 18),
                        label: Text(
                          visibleTags.isEmpty
                              ? 'Aggiungi tag'
                              : 'Tag (${visibleTags.length})',
                        ),
                        onPressed: _saving ? null : _editTags,
                      ),
                      ActionChip(
                        avatar:
                            const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          _diaryDate == null
                              ? 'Giorno'
                              : dateKey(_diaryDate!),
                        ),
                        onPressed: _saving ? null : _chooseDiaryDate,
                      ),
                      if (_diaryDate != null)
                        IconButton(
                          onPressed:
                              _saving ? null : _removeDiaryDate,
                          tooltip: 'Rimuovi dal Diario',
                          icon: const Icon(Icons.event_busy),
                        ),
                    ],
                  ),
                  if (visibleTags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      visibleTags.map((tag) => '#$tag').join(' '),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        selected: _mode == _EditorMode.text,
                        onSelected: _saving
                            ? null
                            : (_) =>
                                setState(() => _mode = _EditorMode.text),
                        label: const Text('Testo'),
                      ),
                      ChoiceChip(
                        selected: _mode == _EditorMode.checklist,
                        onSelected: _saving
                            ? null
                            : (_) => setState(
                                () => _mode = _EditorMode.checklist,
                              ),
                        label: Text('Checklist (${checklist.length})'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_mode == _EditorMode.text) ...[
                    _MarkdownToolbar(
                      enabled: !_saving,
                      onAction: _applyMarkdown,
                      onLink: _insertLink,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _body,
                      onChanged: (_) {
                        _changed();
                        setState(() {});
                      },
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: const InputDecoration(
                        hintText: 'Comincia da un pensiero…',
                        border: InputBorder.none,
                        filled: false,
                      ),
                      minLines: 18,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                    ),
                  ] else ...[
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _saving ? null : _addChecklistItem,
                          icon: const Icon(Icons.add_task),
                          label: const Text('Aggiungi attività'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(
                                  () => _mode = _EditorMode.text,
                                ),
                          child: const Text('Modifica Markdown'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (checklist.isEmpty)
                      const Text('Aggiungi la prima attività.')
                    else
                      ...checklist.map(
                        (item) => Padding(
                          padding: EdgeInsets.only(
                            left: item.depth * 20.0,
                            bottom: 4,
                          ),
                          child: CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: item.completed,
                            controlAffinity:
                                ListTileControlAffinity.leading,
                            title: Text(item.label),
                            onChanged: _saving
                                ? null
                                : (value) {
                                    try {
                                      final body =
                                          Checklist.setCompleted(
                                        _body.text,
                                        item.lineIndex,
                                        value ?? false,
                                      );
                                      _body.text = body;
                                      _changed();
                                      setState(() => _error = null);
                                    } catch (error) {
                                      setState(() {
                                        _error = error
                                            .toString()
                                            .replaceFirst(
                                              'FormatException: ',
                                              '',
                                            );
                                      });
                                    }
                                  },
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkdownToolbar extends StatelessWidget {
  const _MarkdownToolbar({
    required this.enabled,
    required this.onAction,
    required this.onLink,
  });

  final bool enabled;
  final ValueChanged<MarkdownAction> onAction;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              _button(
                Icons.format_bold,
                'Grassetto',
                MarkdownAction.bold,
              ),
              _button(
                Icons.format_italic,
                'Corsivo',
                MarkdownAction.italic,
              ),
              _button(Icons.title, 'Titolo', MarkdownAction.heading),
              _button(
                Icons.format_list_bulleted,
                'Elenco',
                MarkdownAction.bullet,
              ),
              _button(
                Icons.format_list_numbered,
                'Elenco numerato',
                MarkdownAction.numbered,
              ),
              _button(
                Icons.format_quote,
                'Citazione',
                MarkdownAction.quote,
              ),
              _button(Icons.code, 'Codice', MarkdownAction.code),
              _button(
                Icons.developer_mode,
                'Blocco codice',
                MarkdownAction.codeBlock,
              ),
              IconButton(
                onPressed: enabled ? onLink : null,
                tooltip: 'Inserisci link',
                icon: const Icon(Icons.link),
              ),
            ],
          ),
        ),
      );

  Widget _button(
    IconData icon,
    String tooltip,
    MarkdownAction action,
  ) =>
      IconButton(
        onPressed: enabled ? () => onAction(action) : null,
        tooltip: tooltip,
        icon: Icon(icon),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
