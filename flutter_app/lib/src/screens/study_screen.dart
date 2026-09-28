import 'package:flutter/material.dart';

import '../data/study_store.dart';
import '../domain/note.dart';
import '../domain/study.dart';
import '../widgets/ui_resilience.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({
    required this.notes,
    required this.store,
    required this.onOpenNote,
    super.key,
  });

  final List<Note> notes;
  final StudyStore store;
  final ValueChanged<String> onOpenNote;

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  StudySnapshot? _snapshot;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final data = await widget.store.snapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = data;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userErrorText(error);
      });
    }
  }

  Note? _source(String id) {
    for (final note in widget.notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  Future<void> _create() async {
    final candidates = widget.notes
        .where((note) => !note.isDeleted && !note.isTask && !note.isVisual)
        .toList(growable: false);
    if (candidates.isEmpty) {
      setState(() => _error = 'Crea prima una nota sorgente.');
      return;
    }
    Note selected = candidates.first;
    final prompt = TextEditingController();
    final answer = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, local) => AlertDialog(
          title: const Text('Nuovo elemento di studio'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Note>(
                    initialValue: selected,
                    decoration: const InputDecoration(labelText: 'Fonte'),
                    items: candidates
                        .map(
                          (note) => DropdownMenuItem(
                            value: note,
                            child: Text(
                              note.title.trim().isEmpty
                                  ? 'Senza titolo'
                                  : note.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (note) {
                      if (note != null) local(() => selected = note);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: prompt,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Domanda / prompt',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: answer,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Risposta',
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
              child: const Text('Crea'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) {
      prompt.dispose();
      answer.dispose();
      return;
    }
    try {
      await widget.store.createFromNote(
        note: selected,
        prompt: prompt.text,
        answer: answer.text,
      );
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = userErrorText(error));
    } finally {
      prompt.dispose();
      answer.dispose();
    }
  }

  Future<void> _review(LearningItem item) async {
    var revealed = false;
    final rating = await showDialog<StudyRating>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, local) => AlertDialog(
          title: Text(item.prompt),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!revealed)
                  FilledButton.tonal(
                    onPressed: () => local(() => revealed = true),
                    child: const Text('Mostra risposta'),
                  )
                else ...[
                  SelectableText(item.answer),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () =>
                            Navigator.pop(context, StudyRating.again),
                        child: const Text('Ancora'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            Navigator.pop(context, StudyRating.hard),
                        child: const Text('Difficile'),
                      ),
                      FilledButton.tonal(
                        onPressed: () =>
                            Navigator.pop(context, StudyRating.good),
                        child: const Text('Bene'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, StudyRating.easy),
                        child: const Text('Facile'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (rating == null) return;
    await widget.store.review(item.id, rating);
    await _reload();
  }

  Future<void> _refreshSource(LearningItem item, Note source) async {
    try {
      await widget.store.updateFromSource(item, source);
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = userErrorText(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: AppBar(title: Text('Studio')),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final snapshot =
        _snapshot ?? const StudySnapshot(items: [], states: [], logs: []);
    final states = {for (final state in snapshot.states) state.itemId: state};
    final now = DateTime.now().millisecondsSinceEpoch;
    final queue = StudyQueue.build(
      items: snapshot.items,
      states: states,
      now: now,
    );
    final due = snapshot.items.where((item) {
      final state = states[item.id];
      return !item.suspended && state != null && state.dueAt <= now;
    }).length;
    final fresh =
        snapshot.items.where((item) => states[item.id] == null).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Studio')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Aggiungi'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('${snapshot.items.length} elementi')),
              Chip(label: Text('$due da ripassare')),
              Chip(label: Text('$fresh nuovi')),
              Chip(label: Text('${snapshot.logs.length} review')),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Coda di oggi',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (queue.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Nessun elemento dovuto. I nuovi elementi appariranno qui.',
                ),
              ),
            )
          else
            ...queue.map((item) {
              final source = _source(item.sourceNoteId);
              final changed = StudyRules.sourceChanged(item, source);
              final state = states[item.id];
              return Card(
                child: ListTile(
                  title: Text(item.prompt),
                  subtitle: Text(
                    source == null
                        ? 'Fonte non disponibile'
                        : changed
                            ? 'Fonte modificata dopo la creazione'
                            : state == null
                                ? 'Nuovo · ${source.title}'
                                : 'Ripasso · ${source.title}',
                  ),
                  onTap: () => _review(item),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'source' && source != null) {
                        widget.onOpenNote(source.id);
                      } else if (value == 'refresh' && source != null) {
                        await _refreshSource(item, source);
                      } else if (value == 'suspend') {
                        await widget.store.setSuspended(
                          item.id,
                          !item.suspended,
                        );
                        await _reload();
                      } else if (value == 'delete') {
                        await widget.store.delete(item.id);
                        await _reload();
                      }
                    },
                    itemBuilder: (_) => [
                      if (source != null)
                        const PopupMenuItem(
                          value: 'source',
                          child: Text('Apri fonte'),
                        ),
                      if (source != null && changed)
                        const PopupMenuItem(
                          value: 'refresh',
                          child: Text('Aggiorna snapshot fonte'),
                        ),
                      PopupMenuItem(
                        value: 'suspend',
                        child: Text(item.suspended ? 'Riattiva' : 'Sospendi'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Elimina elemento'),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
