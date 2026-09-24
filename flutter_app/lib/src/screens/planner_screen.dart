import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../domain/focus.dart';
import '../domain/note.dart';
import '../domain/planner.dart';
import '../platform/reminder_bridge.dart';
import '../widgets/editorial.dart';
import 'focus_screen.dart';

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({
    required this.notes,
    required this.onSave,
    required this.onTrash,
    required this.onOpenNote,
    this.initialTaskId,
    super.key,
  });

  final List<Note> notes;
  final Future<void> Function(Note note) onSave;
  final Future<void> Function(String id) onTrash;
  final ValueChanged<Note> onOpenNote;
  final String? initialTaskId;

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  PlannerView _view = PlannerView.agenda;
  PlannerScope _scope = PlannerScope.today;
  DateTime _selected = dateOnly(DateTime.now());
  bool _busy = false;
  String? _error;
  String? _openedInitialTaskId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialTask());
  }

  @override
  void didUpdateWidget(covariant PlannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTaskId != widget.initialTaskId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialTask());
    }
  }

  Future<void> _openInitialTask() async {
    final id = widget.initialTaskId;
    if (!mounted ||
        id == null ||
        id.isEmpty ||
        id == _openedInitialTaskId ||
        _busy) {
      return;
    }
    final note = widget.notes
        .where((item) => item.id == id && item.isTask && !item.isDeleted)
        .firstOrNull;
    if (note == null) return;
    _openedInitialTaskId = id;
    setState(() {
      _scope = PlannerScope.all;
      _view = PlannerView.agenda;
    });
    await _editTask(note);
  }

  PlannerIndex get _index => PlannerPro.index(widget.notes);

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
        setState(() =>
            _error = error.toString().replaceFirst('FormatException: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _editTask(Note? note, {String? initialDue}) async {
    final result = await _taskDialog(note, initialDue: initialDue);
    if (result == null || !mounted) return;
    await _run(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final existing = note;
      final saved = existing == null
          ? Note(
              id: const Uuid().v4(),
              title: result.title,
              body: result.body,
              favorite: false,
              createdAt: now,
              updatedAt: now,
              pinned: false,
              archived: false,
              tags: const [],
              taskJson: result.details.encode(),
            )
          : existing.copyWith(
              title: result.title,
              body: result.body,
              taskJson: result.details.encode(),
              updatedAt: now,
            );
      await widget.onSave(saved);
      if (result.details.reminderAt != null) {
        await ReminderBridge.requestPermission();
      }
    });
  }

  Future<void> _toggle(Note note, bool completed) async {
    final task = TaskDetails.tryDecode(note.taskJson);
    if (task == null) return;
    await _run(() async {
      final updated = task.toggleCompleted(
        completed: completed,
        today: DateTime.now(),
      );
      await widget.onSave(note.copyWith(
        taskJson: updated.encode(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    });
  }

  Future<void> _plan(Note note) async {
    final task = TaskDetails.tryDecode(note.taskJson);
    if (task == null) return;
    final updated = await _planDialog(note, task);
    if (updated == null || !mounted) return;
    await _run(() => widget.onSave(note.copyWith(
          taskJson: updated.encode(),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        )));
  }

  Future<void> _focus(Note note) async {
    if (TaskDetails.tryDecode(note.taskJson) == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FocusSessionScreen(
          note: note,
          onSave: widget.onSave,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _moveStatus(Note note, TaskStatus status) async {
    final task = TaskDetails.tryDecode(note.taskJson);
    if (task == null) return;
    await _run(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final updated = changeTaskStatus(
        task,
        status,
        now: now,
        today: DateTime.now(),
      );
      await widget.onSave(
        note.copyWith(taskJson: updated.encode(), updatedAt: now),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
      children: [
        const EditorialSection(
          'Planner Pro',
          detail:
              'Scadenze e pianificazione restano separate. Costruisci la giornata senza perdere il contesto.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PlannerView.values
              .map((view) => ChoiceChip(
                    selected: _view == view,
                    onSelected:
                        _busy ? null : (_) => setState(() => _view = view),
                    label: Text(_viewLabel(view)),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        if (_view != PlannerView.kanban && _view != PlannerView.focus)
          _DateNavigator(
            view: _view,
            selected: _selected,
            enabled: !_busy,
            onChanged: (value) => setState(() => _selected = value),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (_busy) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 12),
        if (_view == PlannerView.agenda)
          _agenda(index)
        else if (_view == PlannerView.day)
          _day(index)
        else if (_view == PlannerView.week)
          _week(index)
        else if (_view == PlannerView.month)
          _month(index)
        else if (_view == PlannerView.kanban)
          _kanban()
        else
          _focusInsights(),
      ],
    );
  }

  Widget _agenda(PlannerIndex index) {
    final tasks = PlannerPro.agenda(widget.notes, _scope, DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: PlannerScope.values
              .map((scope) => FilterChip(
                    selected: _scope == scope,
                    onSelected:
                        _busy ? null : (_) => setState(() => _scope = scope),
                    label: Text(_scopeLabel(scope)),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : () => _editTask(null),
          icon: const Icon(Icons.add),
          label: const Text('Nuova attività'),
        ),
        const SizedBox(height: 12),
        if (tasks.isEmpty)
          Text(_emptyScope(_scope),
              style: Theme.of(context).textTheme.bodyLarge)
        else
          ...tasks.map(_taskCard),
      ],
    );
  }

  Widget _day(PlannerIndex index) {
    final blocks = PlannerPro.timeBlocks(index, _selected);
    final collisions = PlannerPro.collisions(blocks);
    final collisionIds = <String>{
      for (final c in collisions) c.firstTaskId,
      for (final c in collisions) c.secondTaskId,
    };
    final allDay = blocks.where((b) => b.startMinutes == null);
    final timed = blocks.where((b) => b.startMinutes != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (collisions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Chip(
              avatar: const Icon(Icons.schedule, size: 18),
              label: Text('${collisions.length} sovrapposizioni nel piano'),
            ),
          ),
        if (allDay.isNotEmpty) ...[
          Text('Nel giorno', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...allDay.map((b) => _blockCard(b, false)),
          const SizedBox(height: 12),
        ],
        Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (timed.isEmpty)
          const Text(
              'Nessun blocco orario. Pianifica un’attività per costruire la giornata.')
        else
          ...timed.map((b) => _blockCard(b, collisionIds.contains(b.note.id))),
        if (index.unplanned.isNotEmpty) ...[
          const Divider(height: 28),
          Text('Da pianificare',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...index.unplanned.take(12).map((note) => Card(
                child: ListTile(
                  onTap: _busy ? null : () => _plan(note),
                  title: Text(note.title.isEmpty ? 'Attività' : note.title),
                  subtitle: TaskDetails.tryDecode(note.taskJson)?.due == null
                      ? null
                      : Text(
                          'Scadenza ${TaskDetails.tryDecode(note.taskJson)!.due}'),
                  trailing: const Icon(Icons.event),
                ),
              )),
        ],
      ],
    );
  }

  Widget _week(PlannerIndex index) {
    final days = PlannerPro.weekDays(_selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 142,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final day = days[i];
              final planned = PlannerPro.dayNotes(index, day);
              final due = PlannerPro.dueOn(index, day);
              final selected = dateKey(day) == dateKey(_selected);
              return SizedBox(
                width: 132,
                child: Card(
                  color: selected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: InkWell(
                    onTap: _busy ? null : () => setState(() => _selected = day),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(DateFormat('EEE d', 'it_IT').format(day),
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 6),
                          Text('${planned.length} pianificate'),
                          if (due.isNotEmpty)
                            Text('${due.length} in scadenza',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                          const Spacer(),
                          if (planned.isNotEmpty)
                            Text(
                              planned
                                  .take(2)
                                  .map((n) =>
                                      n.title.isEmpty ? 'Attività' : n.title)
                                  .join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Text('Dettaglio ${DateFormat('EEE d MMM', 'it_IT').format(_selected)}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _day(index),
      ],
    );
  }

  Widget _month(PlannerIndex index) {
    final days = PlannerPro.monthGrid(_selected);
    final month = _selected.month;
    final planned = PlannerPro.dayNotes(index, _selected);
    final due = PlannerPro.dueOn(index, _selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          itemCount: days.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 68,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemBuilder: (_, i) {
            final day = days[i];
            final plannedCount = PlannerPro.dayNotes(index, day).length;
            final dueCount = PlannerPro.dueOn(index, day).length;
            final chosen = dateKey(day) == dateKey(_selected);
            return Material(
              color: chosen
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _busy ? null : () => setState(() => _selected = day),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          color: day.month == month
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (plannedCount > 0)
                        Text('$plannedCount pian.',
                            style: Theme.of(context).textTheme.labelSmall),
                      if (dueCount > 0)
                        Text('$dueCount scad.',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const Divider(height: 28),
        Text(
            'Attività per ${DateFormat('EEE d MMM', 'it_IT').format(_selected)}',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (planned.isEmpty && due.isEmpty)
          const Text(
              'Nessuna attività pianificata o in scadenza per questo giorno.')
        else ...[
          ...planned.map(_taskCard),
          if (due.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text('In scadenza',
                  style: Theme.of(context).textTheme.labelLarge),
            ),
          ...due.where((n) => !planned.any((p) => p.id == n.id)).map(_taskCard),
        ],
      ],
    );
  }

  Widget _kanban() {
    final tasks = widget.notes
        .where((note) => note.isTask && !note.isDeleted)
        .toList(growable: false);
    return SizedBox(
      height: 470,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: TaskStatus.values.map((status) {
          final group = tasks.where((note) {
            final details = TaskDetails.tryDecode(note.taskJson);
            return details != null && taskStatus(details) == status;
          }).toList();
          return SizedBox(
            width: 285,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${_taskStatusLabel(status)} · ${group.length}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: group.isEmpty
                            ? const Center(child: Text('Nessuna attività'))
                            : ListView.builder(
                                itemCount: group.length,
                                itemBuilder: (_, index) {
                                  final note = group[index];
                                  final task =
                                      TaskDetails.tryDecode(note.taskJson)!;
                                  return Card(
                                    child: ListTile(
                                      title: Text(
                                        note.title.isEmpty
                                            ? 'Attività'
                                            : note.title,
                                      ),
                                      subtitle: task.due == null
                                          ? null
                                          : Text('Scadenza ${task.due}'),
                                      onTap:
                                          _busy ? null : () => _editTask(note),
                                      trailing: PopupMenuButton<TaskStatus>(
                                        enabled: !_busy,
                                        onSelected: (value) =>
                                            _moveStatus(note, value),
                                        itemBuilder: (_) => TaskStatus.values
                                            .where((value) => value != status)
                                            .map(
                                              (value) => PopupMenuItem(
                                                value: value,
                                                child: Text(
                                                  _taskStatusLabel(value),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _focusInsights() {
    final days = weeklyFocus(widget.notes, DateTime.now());
    final history = focusHistory(widget.notes);
    final total = days.fold<int>(0, (sum, row) => sum + row.value);
    final maxSeconds = days.fold<int>(
      1,
      (value, row) => row.value > value ? row.value : value,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Il tempo che ti sei dedicato',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  '${total ~/ 60} minuti negli ultimi 7 giorni',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: days.map((row) {
                    final fraction = row.value / maxSeconds;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 100,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor:
                                      fraction.clamp(0.03, 1).toDouble(),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('dd/MM').format(row.key),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            Text(
                              '${row.value ~/ 60}m',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Sessioni Focus',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (history.isEmpty)
          const Text('Nessuna sessione datata registrata.')
        else
          ...history.take(50).map(
                (row) => Card(
                  child: ListTile(
                    title: Text(
                      row.title.isEmpty ? 'Attività' : row.title,
                    ),
                    subtitle: Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(
                        DateTime.fromMillisecondsSinceEpoch(row.endedAt),
                      ),
                    ),
                    trailing: Text(
                      '${row.seconds ~/ 60}m ${row.seconds % 60}s',
                    ),
                  ),
                ),
              ),
      ],
    );
  }

  Widget _blockCard(TimeBlock block, bool overlap) {
    final task = TaskDetails.tryDecode(block.note.taskJson)!;
    final time = block.startMinutes == null
        ? 'Senza orario'
        : '${timeLabel(block.startMinutes!)} – ${timeLabel(block.endMinutes!)}';
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          width: overlap ? 2 : 1,
          color: overlap
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: ListTile(
        onTap: _busy ? null : () => _editTask(block.note),
        title: Text(block.note.title.isEmpty ? 'Attività' : block.note.title),
        subtitle: Text(task.due == null ? time : '$time\nScadenza ${task.due}'),
        isThreeLine: task.due != null,
        trailing: IconButton(
          onPressed: _busy ? null : () => _focus(block.note),
          icon: const Icon(Icons.timer),
          tooltip: 'Avvia focus',
        ),
      ),
    );
  }

  Widget _taskCard(Note note) {
    final task = TaskDetails.tryDecode(note.taskJson)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _busy ? null : () => _editTask(note),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: task.completed,
                      onChanged: _busy
                          ? null
                          : (value) => _toggle(note, value ?? false),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              note.title.isEmpty
                                  ? 'Attività senza titolo'
                                  : note.title,
                              style: Theme.of(context).textTheme.titleMedium),
                          if (task.due != null) Text('Scadenza: ${task.due}'),
                          if (task.plannedDate != null)
                            Text(
                              'Pianificata: ${task.plannedDate}'
                              '${task.plannedTime == null ? '' : ' · ${task.plannedTime} · ${task.plannedMinutes} min'}',
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.tertiary),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _busy ? null : () => _focus(note),
                      icon: const Icon(Icons.timer),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (task.priority > 0)
                      Chip(label: Text(_priorityLabel(task.priority))),
                    if (task.repeat != 'NONE') ...[
                      const SizedBox(width: 6),
                      Chip(label: Text(_repeatLabel(task.repeat))),
                    ],
                    const Spacer(),
                    TextButton(
                      onPressed:
                          _busy || task.completed ? null : () => _plan(note),
                      child: Text(
                          task.plannedDate == null ? 'Pianifica' : 'Sposta'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<_TaskDraft?> _taskDialog(Note? note, {String? initialDue}) async {
    final initial =
        TaskDetails.tryDecode(note?.taskJson) ?? TaskDetails.empty();
    final title = TextEditingController(text: note?.title ?? '');
    final body = TextEditingController(text: note?.body ?? '');
    final due = TextEditingController(text: initial.due ?? initialDue ?? '');
    final plannedDate = TextEditingController(text: initial.plannedDate ?? '');
    final plannedTime = TextEditingController(text: initial.plannedTime ?? '');
    final reminderInstant = initial.reminderAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(initial.reminderAt!);
    final reminderDate = TextEditingController(
      text: reminderInstant == null ? '' : dateKey(reminderInstant),
    );
    final reminderTime = TextEditingController(
      text: reminderInstant == null
          ? ''
          : '${reminderInstant.hour.toString().padLeft(2, '0')}:${reminderInstant.minute.toString().padLeft(2, '0')}',
    );
    final reminderZone = initial.reminderZone ?? await ReminderBridge.zoneId();
    if (!mounted) {
      title.dispose();
      body.dispose();
      due.dispose();
      plannedDate.dispose();
      plannedTime.dispose();
      reminderDate.dispose();
      reminderTime.dispose();
      return null;
    }
    var priority = initial.priority;
    var repeat = initial.repeat;
    var plannedMinutes = initial.plannedMinutes;
    String? error;

    return showDialog<_TaskDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(note == null ? 'Nuova attività' : 'Modifica attività'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: title,
                      decoration: const InputDecoration(labelText: 'Titolo')),
                  TextField(
                    controller: body,
                    decoration:
                        const InputDecoration(labelText: 'Note o descrizione'),
                    maxLines: 3,
                  ),
                  TextField(
                    controller: due,
                    decoration: const InputDecoration(
                        labelText: 'Scadenza (AAAA-MM-GG)'),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final item in const [
                        (0, 'Nessuna'),
                        (3, 'Alta'),
                        (2, 'Media'),
                        (1, 'Bassa')
                      ])
                        ChoiceChip(
                          selected: priority == item.$1,
                          onSelected: (_) => setLocal(() => priority = item.$1),
                          label: Text(item.$2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final item in const [
                        ('NONE', 'Nessuna'),
                        ('DAILY', 'Ogni giorno'),
                        ('WEEKLY', 'Ogni settimana'),
                        ('MONTHLY', 'Ogni mese'),
                      ])
                        ChoiceChip(
                          selected: repeat == item.$1,
                          onSelected: (_) => setLocal(() => repeat = item.$1),
                          label: Text(item.$2),
                        ),
                    ],
                  ),
                  const Divider(height: 28),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Pianificazione'),
                  ),
                  TextField(
                    controller: plannedDate,
                    decoration: const InputDecoration(
                        labelText: 'Giorno pianificato (AAAA-MM-GG)'),
                  ),
                  TextField(
                    controller: plannedTime,
                    decoration: const InputDecoration(
                        labelText: 'Ora opzionale (HH:MM)'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [15, 25, 30, 45, 60, 90]
                        .map((value) => ChoiceChip(
                              selected: plannedMinutes == value,
                              onSelected: (_) =>
                                  setLocal(() => plannedMinutes = value),
                              label: Text('${value}m'),
                            ))
                        .toList(),
                  ),
                  const Divider(height: 28),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Promemoria'),
                  ),
                  TextField(
                    controller: reminderDate,
                    decoration: const InputDecoration(
                      labelText: 'Data promemoria (AAAA-MM-GG)',
                    ),
                  ),
                  TextField(
                    controller: reminderTime,
                    decoration: const InputDecoration(
                      labelText: 'Ora promemoria (HH:MM)',
                    ),
                  ),
                  if (initial.reminderAt != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          reminderDate.clear();
                          reminderTime.clear();
                        },
                        child: const Text('Rimuovi promemoria'),
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (note != null)
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _run(() => widget.onTrash(note.id));
                },
                child: Text('Elimina',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annulla')),
            FilledButton(
              onPressed: () {
                try {
                  if (title.text.trim().isEmpty) {
                    throw const FormatException('Inserisci un titolo.');
                  }
                  var details = initial.withEditorValues(
                    due: due.text,
                    priority: priority,
                    repeat: repeat,
                    linkedNoteId: initial.linkedNoteId,
                    plannedDate: plannedDate.text,
                    plannedTime: plannedTime.text,
                    plannedMinutes: plannedMinutes,
                  );

                  final reminderDayText = reminderDate.text.trim();
                  final reminderClockText = reminderTime.text.trim();
                  if (reminderDayText.isEmpty && reminderClockText.isEmpty) {
                    details = details.copyWith(
                      reminderAt: null,
                      reminderTime: null,
                      reminderZone: null,
                    );
                  } else {
                    final reminderDay = parseDate(reminderDayText);
                    final reminderMinutes = parseTimeMinutes(reminderClockText);
                    if (reminderDay == null || reminderMinutes == null) {
                      throw const FormatException(
                        'Promemoria: inserisci data e ora valide.',
                      );
                    }
                    final reminderAt = DateTime(
                      reminderDay.year,
                      reminderDay.month,
                      reminderDay.day,
                      reminderMinutes ~/ 60,
                      reminderMinutes % 60,
                    ).millisecondsSinceEpoch;
                    if (reminderAt < 946684800000 ||
                        reminderAt > 7258118399999) {
                      throw const FormatException(
                        'Data promemoria non supportata.',
                      );
                    }
                    details = details.copyWith(
                      reminderAt: reminderAt,
                      reminderTime: reminderClockText,
                      reminderZone: reminderZone,
                    );
                  }

                  Navigator.pop(
                    context,
                    _TaskDraft(title.text.trim(), body.text, details),
                  );
                } catch (e) {
                  setLocal(() => error =
                      e.toString().replaceFirst('FormatException: ', ''));
                }
              },
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      title.dispose();
      body.dispose();
      due.dispose();
      plannedDate.dispose();
      plannedTime.dispose();
      reminderDate.dispose();
      reminderTime.dispose();
    });
  }

  Future<TaskDetails?> _planDialog(Note note, TaskDetails task) {
    final date =
        TextEditingController(text: task.plannedDate ?? dateKey(_selected));
    final time = TextEditingController(text: task.plannedTime ?? '');
    var minutes = task.plannedMinutes;
    String? error;
    return showDialog<TaskDetails>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Pianifica attività'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(note.title.isEmpty ? 'Attività' : note.title),
              TextField(
                  controller: date,
                  decoration:
                      const InputDecoration(labelText: 'Giorno (AAAA-MM-GG)')),
              TextField(
                  controller: time,
                  decoration: const InputDecoration(
                      labelText: 'Ora opzionale (HH:MM)')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [15, 25, 30, 45, 60, 90]
                    .map((value) => ChoiceChip(
                          selected: minutes == value,
                          onSelected: (_) => setLocal(() => minutes = value),
                          label: Text('${value}m'),
                        ))
                    .toList(),
              ),
              if (error != null)
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
          actions: [
            if (task.plannedDate != null)
              TextButton(
                onPressed: () => Navigator.pop(context, task.unschedule()),
                child: const Text('Rimuovi piano'),
              ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annulla')),
            FilledButton(
              onPressed: () {
                try {
                  final day = parseDate(date.text.trim());
                  if (day == null) {
                    throw const FormatException('Data non valida.');
                  }
                  Navigator.pop(
                    context,
                    task.schedule(date: day, time: time.text, minutes: minutes),
                  );
                } catch (e) {
                  setLocal(() => error =
                      e.toString().replaceFirst('FormatException: ', ''));
                }
              },
              child: const Text('Pianifica'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      date.dispose();
      time.dispose();
    });
  }
}

class _DateNavigator extends StatelessWidget {
  const _DateNavigator({
    required this.view,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final PlannerView view;
  final DateTime selected;
  final bool enabled;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    DateTime shift(int direction) {
      if (view == PlannerView.month) {
        return DateTime(
          selected.year,
          selected.month + direction,
          selected.day.clamp(1, 28).toInt(),
        );
      }
      if (view == PlannerView.week) {
        return selected.add(Duration(days: 7 * direction));
      }
      return selected.add(Duration(days: direction));
    }

    final label = view == PlannerView.month
        ? DateFormat('MMMM yyyy', 'it_IT').format(selected)
        : view == PlannerView.week
            ? '${DateFormat('d MMM', 'it_IT').format(PlannerPro.weekDays(selected).first)} – '
                '${DateFormat('d MMM yyyy', 'it_IT').format(PlannerPro.weekDays(selected).last)}'
            : DateFormat('EEEE d MMMM yyyy', 'it_IT').format(selected);

    return Row(
      children: [
        IconButton(
          onPressed: enabled ? () => onChanged(shift(-1)) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Column(
            children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              TextButton(
                onPressed:
                    enabled && dateKey(selected) != dateKey(DateTime.now())
                        ? () => onChanged(dateOnly(DateTime.now()))
                        : null,
                child: const Text('Oggi'),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: enabled ? () => onChanged(shift(1)) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _TaskDraft {
  const _TaskDraft(this.title, this.body, this.details);
  final String title;
  final String body;
  final TaskDetails details;
}

class _FocusDialog extends StatefulWidget {
  const _FocusDialog({required this.title, required this.suggestedMinutes});
  final String title;
  final int suggestedMinutes;

  @override
  State<_FocusDialog> createState() => _FocusDialogState();
}

class _FocusDialogState extends State<_FocusDialog> {
  Timer? _timer;
  late int _remaining;
  int _elapsed = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.suggestedMinutes.clamp(1, 120).toInt() * 60;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _remaining <= 0) {
        timer.cancel();
        if (mounted) setState(() => _running = false);
        return;
      }
      setState(() {
        _remaining--;
        _elapsed++;
      });
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Sessione di focus · ${widget.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${(_remaining ~/ 60).toString().padLeft(2, '0')}:${(_remaining % 60).toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _toggle,
              child: Text(_running ? 'Pausa' : 'Avvia'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Chiudi')),
          FilledButton(
            onPressed: _elapsed == 0
                ? null
                : () => Navigator.pop(context, _elapsed.clamp(1, 7200).toInt()),
            child: Text('Salva ${_elapsed ~/ 60}m'),
          ),
        ],
      );
}

String _viewLabel(PlannerView view) => switch (view) {
      PlannerView.agenda => 'Agenda',
      PlannerView.day => 'Giorno',
      PlannerView.week => 'Settimana',
      PlannerView.month => 'Mese',
      PlannerView.kanban => 'Kanban',
      PlannerView.focus => 'Focus',
    };

String _taskStatusLabel(TaskStatus status) => switch (status) {
      TaskStatus.todo => 'Da fare',
      TaskStatus.doing => 'In corso',
      TaskStatus.waiting => 'In attesa',
      TaskStatus.done => 'Completata',
    };

String _scopeLabel(PlannerScope scope) => switch (scope) {
      PlannerScope.today => 'Oggi',
      PlannerScope.upcoming => 'Prossime',
      PlannerScope.all => 'Tutte',
      PlannerScope.completed => 'Completate',
    };

String _emptyScope(PlannerScope scope) => switch (scope) {
      PlannerScope.today =>
        'Nessuna attività prevista per oggi. Un momento per te.',
      PlannerScope.upcoming =>
        'Nessuna attività programmata per i prossimi giorni.',
      PlannerScope.completed => 'Nessuna attività completata.',
      PlannerScope.all =>
        'Nessuna attività creata. Tocca Nuova attività per iniziare.',
    };

String _priorityLabel(int priority) => switch (priority) {
      3 => 'Alta',
      2 => 'Media',
      1 => 'Bassa',
      _ => 'Priorità $priority',
    };

String _repeatLabel(String repeat) => switch (repeat) {
      'DAILY' => 'Ogni giorno',
      'WEEKLY' => 'Ogni settimana',
      'MONTHLY' => 'Ogni mese',
      _ => repeat,
    };

extension _PlannerFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
