import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/diary.dart';
import '../domain/note.dart';
import '../domain/planner.dart';
import '../widgets/editorial.dart';

enum _DiaryMode { calendar, gallery, book }

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({
    required this.notes,
    required this.collections,
    required this.onOpen,
    required this.onCreate,
    required this.onOpenTask,
    required this.onCreateCollection,
    super.key,
  });

  final List<Note> notes;
  final List<NoteCollection> collections;
  final ValueChanged<Note> onOpen;
  final Future<void> Function(DateTime date, String? collectionId) onCreate;
  final ValueChanged<Note> onOpenTask;
  final Future<void> Function(String name) onCreateCollection;

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  DateTime _selected = dateOnly(DateTime.now());
  late DateTime _month = DateTime(_selected.year, _selected.month);
  _DiaryMode _mode = _DiaryMode.calendar;
  String? _collectionId;
  bool _busy = false;
  String? _error;

  NoteCollection? get _selectedCollection {
    for (final collection in widget.collections) {
      if (collection.id == _collectionId) return collection;
    }
    return null;
  }

  DiaryIndex get _index => Diary.index(
        widget.notes,
        collectionId: _selectedCollection?.id,
      );

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
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createBook() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuovo book'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nome del book'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('Crea'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    await _run(() => widget.onCreateCollection(name));
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
      children: [
        const EditorialSection(
          'I giorni, le tue storie.',
          detail: 'Pensieri, ricordi e impegni, ognuno al suo posto.',
        ),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              selected: _mode == _DiaryMode.calendar,
              onSelected: _busy
                  ? null
                  : (_) => setState(() => _mode = _DiaryMode.calendar),
              label: const Text('Calendario'),
            ),
            ChoiceChip(
              selected: _mode == _DiaryMode.gallery,
              onSelected: _busy
                  ? null
                  : (_) => setState(() => _mode = _DiaryMode.gallery),
              label: const Text('Galleria'),
            ),
            ChoiceChip(
              selected: _mode == _DiaryMode.book,
              onSelected:
                  _busy ? null : (_) => setState(() => _mode = _DiaryMode.book),
              label: const Text('Book'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                selected: _selectedCollection == null,
                onSelected:
                    _busy ? null : (_) => setState(() => _collectionId = null),
                label: const Text('Tutti i ricordi'),
              ),
              const SizedBox(width: 8),
              ...widget.collections.map((collection) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: _selectedCollection?.id == collection.id,
                      onSelected: _busy
                          ? null
                          : (_) =>
                              setState(() => _collectionId = collection.id),
                      label: Text(collection.name),
                    ),
                  )),
            ],
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        if (_mode == _DiaryMode.calendar)
          _calendar(index)
        else if (_mode == _DiaryMode.book && _selectedCollection == null)
          _books(index)
        else
          _gallery(index),
      ],
    );
  }

  Widget _calendar(DiaryIndex index) {
    final dayKey = dateKey(_selected);
    final entries = index.days[dayKey] ?? const <DiaryEntry>[];
    final tasks = index.tasks[dayKey] ?? const <Note>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _busy ? null : () => _moveMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton(
                onPressed: _busy ? null : _pickDate,
                child: Text(
                  DateFormat('MMMM yyyy', 'it_IT').format(_month),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            IconButton(
              onPressed: _busy ? null : () => _moveMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        _MonthGrid(
          month: _month,
          selected: _selected,
          today: dateOnly(DateTime.now()),
          index: index,
          onSelect: (date) => setState(() => _selected = date),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          children: const [
            _LegendDot(label: 'Ricordi', icon: Icons.circle),
            _LegendDot(label: 'Impegni', icon: Icons.check_circle),
          ],
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _selected = dateOnly(DateTime.now());
                    _month = DateTime(_selected.year, _selected.month);
                  }),
          child: const Text('Torna a oggi'),
        ),
        EditorialSection(
          DateFormat('d MMMM yyyy', 'it_IT').format(_selected),
          detail: _selectedCollection == null
              ? null
              : 'Ricordi in ${_selectedCollection!.name} · impegni di tutti i book',
        ),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _run(
                  () => widget.onCreate(_selected, _selectedCollection?.id)),
          icon: const Icon(Icons.edit),
          label: const Text('Scrivi un pensiero'),
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty && tasks.isEmpty)
          const Text('Questo giorno aspetta la sua prima storia.'),
        ...entries.map(_entryCard),
        if (tasks.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Impegni', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ...tasks.map((task) {
            final details = TaskDetails.tryDecode(task.taskJson);
            return Card(
              child: ListTile(
                onTap: () => widget.onOpenTask(task),
                title: Text(task.title.isEmpty ? 'Attività' : task.title),
                subtitle:
                    Text(details?.completed == true ? 'Completato' : 'Da fare'),
                trailing: const Icon(Icons.chevron_right),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _books(DiaryIndex index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Un book usa una raccolta: le note datate diventano le sue pagine. Le altre note della raccolta restano nella libreria.',
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _busy ? null : _createBook,
          icon: const Icon(Icons.add),
          label: const Text('Crea book'),
        ),
        const SizedBox(height: 12),
        if (widget.collections.isEmpty)
          const Text(
              'Vacanze, noi due, un anno da ricordare: scegli il nome del primo book.')
        else
          ...widget.collections.map((collection) {
            final entries =
                Diary.index(widget.notes, collectionId: collection.id).entries;
            return Card(
              child: ListTile(
                onTap: () => setState(() => _collectionId = collection.id),
                leading: const Icon(Icons.book),
                title: Text(collection.name),
                subtitle: Text('${entries.length} pagine'),
                trailing: const Icon(Icons.chevron_right),
              ),
            );
          }),
      ],
    );
  }

  Widget _gallery(DiaryIndex index) {
    final entries = index.entries.where((entry) {
      if (_mode != _DiaryMode.gallery) return true;
      return _attachmentCount(entry.note.body) > 0;
    }).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EditorialSection(
          _selectedCollection?.name ?? 'La tua galleria',
          detail: _mode == _DiaryMode.gallery
              ? 'I ricordi con allegati immagine, dal più recente.'
              : 'Le pagine del book, dal più recente.',
        ),
        if (_mode == _DiaryMode.book)
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() => _mode = _DiaryMode.calendar),
            icon: const Icon(Icons.calendar_month),
            label: const Text('Aggiungi una pagina: scegli il giorno'),
          ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const Text(
              'Nessun ricordo qui. Apri il calendario per aggiungerne uno.')
        else
          ...entries.map(_entryCard),
      ],
    );
  }

  Widget _entryCard(DiaryEntry entry) {
    final preview = entry.note.body
        .replaceAll(RegExp(r'\[[^\]]*\]\(notes-asset://[^)]*\)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final attachments = _attachmentCount(entry.note.body);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          onTap: () => widget.onOpen(entry.note),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('d MMMM yyyy', 'it_IT').format(entry.date),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  entry.note.title.isEmpty ? 'Un ricordo' : entry.note.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
                if (attachments > 0) ...[
                  const SizedBox(height: 8),
                  Text('$attachments allegati immagine · Apri la pagina',
                      style: Theme.of(context).textTheme.labelMedium),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _moveMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final maxDay = DateTime(next.year, next.month + 1, 0).day;
    setState(() {
      _month = next;
      _selected = DateTime(
          next.year, next.month, _selected.day.clamp(1, maxDay).toInt());
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selected = dateOnly(picked);
      _month = DateTime(picked.year, picked.month);
    });
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.index,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final DiaryIndex index;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final cells = Diary.monthCells(month);
    return Column(
      children: [
        Row(
          children: const ['L', 'M', 'M', 'G', 'V', 'S', 'D']
              .map((label) => Expanded(child: Center(child: Text(label))))
              .toList(),
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cells.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 62,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemBuilder: (_, i) {
            final date = cells[i];
            if (date == null) return const SizedBox.shrink();
            final entries = index.days[dateKey(date)] ?? const <DiaryEntry>[];
            final tasks = index.tasks[dateKey(date)] ?? const <Note>[];
            final chosen = dateKey(date) == dateKey(selected);
            final isToday = dateKey(date) == dateKey(today);
            return Material(
              color: chosen
                  ? Theme.of(context).colorScheme.primaryContainer
                  : isToday
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelect(date),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                  child: Column(
                    children: [
                      Text('${date.day}'),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (entries.isNotEmpty)
                            Icon(Icons.circle,
                                size: 7,
                                color: Theme.of(context).colorScheme.primary),
                          if (entries.isNotEmpty && tasks.isNotEmpty)
                            const SizedBox(width: 3),
                          if (tasks.isNotEmpty)
                            Icon(Icons.circle,
                                size: 7,
                                color: Theme.of(context).colorScheme.tertiary),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      );
}

int _attachmentCount(String body) =>
    RegExp(r'notes-asset://[^)\s]+').allMatches(body).length;
