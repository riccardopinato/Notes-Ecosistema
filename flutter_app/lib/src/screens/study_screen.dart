import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/note.dart';
import '../domain/study.dart';
import '../state/study_controller.dart';
import '../widgets/editorial.dart';
import '../widgets/ui_resilience.dart';

class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({
    required this.notes,
    required this.onOpenSource,
    super.key,
  });

  final List<Note> notes;
  final ValueChanged<Note> onOpenSource;

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  final Set<String> _revealed = {};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studyProvider);
    final notesById = {for (final note in widget.notes) note.id: note};
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = StudyQueue.due(
      items: state.items,
      logs: state.logs,
      now: now,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Study'),
        actions: [
          IconButton(
            tooltip: 'Aggiungi elemento',
            onPressed: state.loading ? null : _addItem,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(studyProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          children: [
            const EditorialEyebrow('STUDY CORE'),
            const SizedBox(height: 4),
            Text(
              'Ripassa ciò che hai già studiato.',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Gli elementi restano collegati alla nota sorgente, ma conservano '
              'anche lo snapshot storico studiato.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    value: due.length,
                    label: 'Da ripassare oggi',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricCard(
                    value: state.items.length,
                    label: 'Elementi totali',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (state.loading)
              const Center(child: CircularProgressIndicator())
            else if (state.error != null)
              _ErrorCard(
                onRetry: () => ref.read(studyProvider.notifier).refresh(),
              )
            else if (due.isEmpty)
              _EmptyStudy(onAdd: _addItem)
            else ...[
              const EditorialSection(
                'Coda di oggi',
                detail: 'Massimo 30 elementi: niente debito infinito.',
              ),
              ...due.map((item) {
                final source = notesById[item.sourceNoteId];
                final sourceChanged =
                    source != null && source.updatedAt > item.sourceUpdatedAt;
                return _StudyCard(
                  item: item,
                  revealed: _revealed.contains(item.id),
                  sourceMissing: source == null || source.isDeleted,
                  sourceChanged: sourceChanged,
                  onReveal: () => setState(() => _revealed.add(item.id)),
                  onOpenSource: source == null || source.isDeleted
                      ? null
                      : () => widget.onOpenSource(source),
                  onReview: (rating) async {
                    await ref.read(studyProvider.notifier).review(item, rating);
                    if (mounted) setState(() => _revealed.remove(item.id));
                  },
                  onDelete: () => _delete(item),
                );
              }),
            ],
            if (state.items.isNotEmpty && due.length < state.items.length) ...[
              const SizedBox(height: 16),
              const EditorialSection(
                'In programma',
                detail: 'Lo stato è derivato dal ReviewLog canonico.',
              ),
              ...state.items
                  .where((item) => !due.any((dueItem) => dueItem.id == item.id))
                  .take(20)
                  .map(
                    (item) => ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text(item.prompt),
                      subtitle: Text(
                        notesById[item.sourceNoteId]?.title ??
                            'Sorgente non disponibile · snapshot preservato',
                      ),
                      trailing: IconButton(
                        tooltip: 'Elimina',
                        onPressed: () => _delete(item),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addItem() async {
    final candidates = widget.notes
        .where(
          (note) =>
              !note.isDeleted &&
              !note.isTask &&
              !note.isVisual &&
              note.body.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      _message('Non ci sono note testuali utilizzabili come sorgente.');
      return;
    }

    final source = await showNotesBottomSheet<Note>(
      context: context,
      expand: true,
      builder: (context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const EditorialAppTitle('Scegli la sorgente'),
          const SizedBox(height: 12),
          ...candidates.map(
            (note) => ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(
                note.title.trim().isEmpty ? 'Senza titolo' : note.title,
              ),
              subtitle: Text(
                note.body.replaceAll('\n', ' '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.pop(context, note),
            ),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;

    final prompt = TextEditingController(
      text: source.title.trim().isEmpty
          ? 'Cosa devo ricordare?'
          : source.title.trim(),
    );
    final answer = TextEditingController(
      text: source.body.length <= 1500
          ? source.body
          : source.body.substring(0, 1500),
    );
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuovo elemento di studio'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: prompt,
                  maxLength: StudyRules.maxPrompt,
                  decoration: const InputDecoration(
                    labelText: 'Domanda / prompt',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: answer,
                  maxLength: StudyRules.maxAnswer,
                  minLines: 4,
                  maxLines: 10,
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
            child: const Text('Aggiungi'),
          ),
        ],
      ),
    );
    if (created != true) return;
    try {
      await ref.read(studyProvider.notifier).createFromNote(
            source: source,
            prompt: prompt.text,
            answer: answer.text,
          );
    } catch (error) {
      _message(userErrorText(error));
    } finally {
      prompt.dispose();
      answer.dispose();
    }
  }

  Future<void> _delete(LearningItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare elemento di studio?'),
        content: const Text(
          'Verranno eliminati anche i suoi ReviewLog. '
          'La nota sorgente non verrà modificata.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(studyProvider.notifier).delete(item.id);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({
    required this.item,
    required this.revealed,
    required this.sourceMissing,
    required this.sourceChanged,
    required this.onReveal,
    required this.onOpenSource,
    required this.onReview,
    required this.onDelete,
  });

  final LearningItem item;
  final bool revealed;
  final bool sourceMissing;
  final bool sourceChanged;
  final VoidCallback onReveal;
  final VoidCallback? onOpenSource;
  final ValueChanged<StudyRating> onReview;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.prompt, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (sourceMissing)
                const Text('Sorgente non disponibile · snapshot preservato')
              else if (sourceChanged)
                const Text('La sorgente è cambiata dopo questo studio.')
              else
                const Text('Sorgente aggiornata allo snapshot studiato.'),
              const SizedBox(height: 12),
              if (!revealed)
                FilledButton.tonal(
                  onPressed: onReveal,
                  child: const Text('Mostra risposta'),
                )
              else ...[
                SelectableText(item.answer),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => onReview(StudyRating.again),
                      child: const Text('Ancora'),
                    ),
                    OutlinedButton(
                      onPressed: () => onReview(StudyRating.hard),
                      child: const Text('Difficile'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => onReview(StudyRating.good),
                      child: const Text('Bene'),
                    ),
                    FilledButton(
                      onPressed: () => onReview(StudyRating.easy),
                      child: const Text('Facile'),
                    ),
                  ],
                ),
              ],
              const Divider(height: 28),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onOpenSource,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Sorgente'),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Elimina',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(label),
            ],
          ),
        ),
      );
}

class _EmptyStudy extends StatelessWidget {
  const _EmptyStudy({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.school_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                'Nessun ripasso in coda.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Crea un elemento partendo da una nota già studiata.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: onAdd,
                child: const Text('Aggiungi da nota'),
              ),
            ],
          ),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text('Study non disponibile.'),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Riprova'),
              ),
            ],
          ),
        ),
      );
}
