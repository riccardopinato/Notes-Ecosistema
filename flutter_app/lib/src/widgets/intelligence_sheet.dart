import 'package:flutter/material.dart';

import '../data/derivative_store.dart';
import '../domain/derivatives.dart';
import '../domain/intelligence.dart';
import '../domain/note.dart';
import 'ui_resilience.dart';

Future<void> showIntelligenceSheet({
  required BuildContext context,
  required List<Note> notes,
  required DerivativeStore derivativeStore,
  Note? currentNote,
  ValueChanged<Note>? onOpenNote,
  ValueChanged<String>? onInsertMarkdown,
  Future<KnowledgeQueryResult> Function(String query)? unifiedSearch,
  Future<List<KnowledgeHit>> Function(Note source)? unifiedRelated,
  bool semanticEnabled = true,
}) =>
    showNotesBottomSheet<void>(
      context: context,
      expand: true,
      builder: (_) => _IntelligenceSheet(
        notes: notes,
        derivativeStore: derivativeStore,
        currentNote: currentNote,
        onOpenNote: onOpenNote,
        onInsertMarkdown: onInsertMarkdown,
        unifiedSearch: unifiedSearch,
        unifiedRelated: unifiedRelated,
        semanticEnabled: semanticEnabled,
      ),
    );

class _IntelligenceSheet extends StatefulWidget {
  const _IntelligenceSheet({
    required this.notes,
    required this.derivativeStore,
    this.currentNote,
    this.onOpenNote,
    this.onInsertMarkdown,
    this.unifiedSearch,
    this.unifiedRelated,
    this.semanticEnabled = true,
  });

  final List<Note> notes;
  final DerivativeStore derivativeStore;
  final Note? currentNote;
  final ValueChanged<Note>? onOpenNote;
  final ValueChanged<String>? onInsertMarkdown;
  final Future<KnowledgeQueryResult> Function(String query)? unifiedSearch;
  final Future<List<KnowledgeHit>> Function(Note source)? unifiedRelated;
  final bool semanticEnabled;

  @override
  State<_IntelligenceSheet> createState() => _IntelligenceSheetState();
}

class _IntelligenceSheetState extends State<_IntelligenceSheet> {
  final _query = TextEditingController();
  final _engine = const LocalKnowledgeRetrieval();
  KnowledgeQueryResult? _result;
  List<KnowledgeHit> _related = const [];
  List<SourceDerivative> _derivatives = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final note = widget.currentNote;
    if (note != null) {
      _loadRelated();
      _loadDerivatives();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadRelated() async {
    final note = widget.currentNote;
    if (note == null) return;
    try {
      final unified = widget.unifiedRelated;
      final values = unified == null
          ? _engine.related(note, widget.notes)
          : await unified(note);
      if (!mounted) return;
      setState(() => _related = values);
    } catch (error) {
      if (mounted) {
        setState(() => _error = userErrorText(error));
      }
    }
  }

  Future<void> _loadDerivatives() async {
    final note = widget.currentNote;
    if (note == null) return;
    try {
      final values = await widget.derivativeStore.forNote(note.id);
      if (!mounted) return;
      setState(() => _derivatives = values);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userErrorText(error),
        );
      }
    }
  }

  Future<void> _ask() async {
    final query = _query.text.trim();
    if (query.isEmpty) {
      setState(() {
        _result = null;
        _error = 'Scrivi una domanda o alcune parole chiave.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final unified = widget.unifiedSearch;
      final result = unified == null
          ? _engine.ask(query, widget.notes)
          : await unified(query);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _error = userErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createDerivative(DerivativeKind kind) async {
    final note = widget.currentNote;
    if (note == null) return;
    final source = _sourceText(note);
    if (source.trim().isEmpty) {
      setState(() => _error = 'Nessun testo sorgente disponibile.');
      return;
    }

    String content;
    switch (kind) {
      case DerivativeKind.transcript:
        content = source;
        break;
      case DerivativeKind.cleanedTranscript:
        content = LocalDerivation.cleanTranscript(source);
        break;
      case DerivativeKind.summary:
        content = LocalDerivation.summarize(source);
        break;
      case DerivativeKind.extractedTasks:
        content = LocalDerivation.tasksAsMarkdown(
          LocalDerivation.extractTasks(source),
        );
        break;
      case DerivativeKind.ocrText:
      case DerivativeKind.ocrCorrected:
        content = source;
        break;
    }
    if (content.trim().isEmpty) {
      setState(
        () => _error = kind == DerivativeKind.extractedTasks
            ? 'Nessun task esplicito trovato nel testo.'
            : 'Il derivato risulta vuoto.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.derivativeStore.add(
        sourceNoteId: note.id,
        kind: kind,
        content: content,
        sourceText: source,
      );
      await _loadDerivatives();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userErrorText(error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _sourceText(Note note) {
    final transcript = _derivatives
        .where((item) => item.kind == DerivativeKind.transcript)
        .firstOrNull;
    return transcript?.content ?? note.body;
  }

  String _kindLabel(DerivativeKind kind) => switch (kind) {
        DerivativeKind.transcript => 'Trascrizione originale',
        DerivativeKind.cleanedTranscript => 'Trascrizione pulita',
        DerivativeKind.summary => 'Riassunto',
        DerivativeKind.extractedTasks => 'Task estratti',
        DerivativeKind.ocrText => 'OCR originale',
        DerivativeKind.ocrCorrected => 'OCR corretto',
      };

  Future<void> _addOriginalTranscript() async {
    final note = widget.currentNote;
    if (note == null) return;
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aggiungi trascrizione originale'),
        content: SizedBox(
          width: 620,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 8,
            maxLines: 18,
            decoration: const InputDecoration(
              hintText:
                  'Incolla qui la trascrizione grezza. Non sostituirà audio o nota originale.',
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
            child: const Text('Conserva come derivato'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted && controller.text.trim().isNotEmpty) {
      try {
        await widget.derivativeStore.add(
          sourceNoteId: note.id,
          kind: DerivativeKind.transcript,
          content: controller.text.trim(),
          sourceText: note.body,
          engine: 'user-source-v1',
        );
        await _loadDerivatives();
      } catch (error) {
        if (mounted) {
          setState(
            () => _error = userErrorText(error),
          );
        }
      }
    }
    controller.dispose();
  }

  Widget _hitTile(KnowledgeHit hit, int index) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: Text(
          hit.note.title.trim().isEmpty ? 'Senza titolo' : hit.note.title,
        ),
        subtitle: Text(
          hit.excerpt,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(hit.score.toStringAsFixed(2)),
        onTap: widget.onOpenNote == null
            ? null
            : () {
                Navigator.pop(context);
                widget.onOpenNote!(hit.note);
              },
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: SizedBox.expand(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.currentNote == null
                      ? 'Knowledge Search'
                      : 'Intelligence · opzionale',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  widget.semanticEnabled
                      ? 'Ricerca ibrida locale: ranking classico + indice semantico ricostruibile. Nessuna rete richiesta.'
                      : 'Ricerca classica locale. L’indice semantico è disattivato nelle Impostazioni.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _query,
                        onSubmitted: (_) => _ask(),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Chiedi alle tue note…',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _ask,
                      child: const Text('Cerca'),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      if (_result != null) ...[
                        Text(
                          'Risultati con fonti',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_result!.empty)
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Nessuna fonte rilevante trovata.'),
                          )
                        else
                          ..._result!.hits.indexed.map(
                            (row) => _hitTile(row.$2, row.$1),
                          ),
                        const Divider(height: 28),
                      ],
                      if (widget.currentNote != null) ...[
                        Text(
                          'Note correlate',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_related.isEmpty)
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Nessuna correlazione locale forte.'),
                          )
                        else
                          ..._related.indexed.map(
                            (row) => _hitTile(row.$2, row.$1),
                          ),
                        const Divider(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Originale → derivati',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _busy ? null : _addOriginalTranscript,
                              icon: const Icon(Icons.transcribe_outlined),
                              label: const Text('Transcript grezzo'),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _createDerivative(
                                        DerivativeKind.cleanedTranscript,
                                      ),
                              child: const Text('Pulisci transcript'),
                            ),
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _createDerivative(
                                        DerivativeKind.summary,
                                      ),
                              child: const Text('Riassumi'),
                            ),
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _createDerivative(
                                        DerivativeKind.extractedTasks,
                                      ),
                              child: const Text('Estrai task'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_derivatives.isEmpty)
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Nessun derivato salvato.'),
                            subtitle: Text(
                              'Audio e testo originale restano comunque invariati.',
                            ),
                          ),
                        ..._derivatives.map(
                          (item) => Card(
                            child: ListTile(
                              title: Text(_kindLabel(item.kind)),
                              subtitle: Text(
                                item.content,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: widget.onInsertMarkdown == null
                                  ? null
                                  : () {
                                      widget.onInsertMarkdown!(
                                        '\n\n${item.content}\n',
                                      );
                                      Navigator.pop(context);
                                    },
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'insert' &&
                                      widget.onInsertMarkdown != null) {
                                    widget.onInsertMarkdown!(
                                      '\n\n${item.content}\n',
                                    );
                                    if (mounted) Navigator.pop(context);
                                  } else if (value == 'delete') {
                                    await widget.derivativeStore
                                        .delete(item.id);
                                    await _loadDerivatives();
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (widget.onInsertMarkdown != null)
                                    const PopupMenuItem(
                                      value: 'insert',
                                      child: Text('Inserisci nella nota'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Elimina derivato'),
                                  ),
                                ],
                              ),
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
        ),
      );
}
