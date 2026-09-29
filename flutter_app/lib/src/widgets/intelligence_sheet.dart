import 'package:flutter/material.dart';

import '../data/derivative_store.dart';
import '../data/local_llm_service.dart';
import '../domain/derivatives.dart';
import '../domain/intelligence.dart';
import '../domain/local_llm.dart';
import '../domain/note.dart';
import 'plus_local_ai_card.dart';
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
  final _localQuestion = TextEditingController();
  final _engine = const LocalKnowledgeRetrieval();
  final _localLlm = LocalLlmService();
  KnowledgeQueryResult? _result;
  List<KnowledgeHit> _related = const [];
  List<SourceDerivative> _derivatives = const [];
  LocalLlmStatus? _llmStatus;
  LocalLlmGeneration? _llmAnswer;
  bool _busy = false;
  bool _llmBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLocalLlmStatus();
    final note = widget.currentNote;
    if (note != null) {
      _loadRelated();
      _loadDerivatives();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _localQuestion.dispose();
    super.dispose();
  }

  Future<void> _loadLocalLlmStatus() async {
    final status = await _localLlm.status();
    if (mounted) setState(() => _llmStatus = status);
  }

  Future<void> _downloadSystemModel() async {
    setState(() {
      _llmBusy = true;
      _error = null;
    });
    try {
      final status = await _localLlm.downloadSystemModel();
      if (!mounted) return;
      setState(() => _llmStatus = status);
    } catch (error) {
      if (mounted) setState(() => _error = userErrorText(error));
    } finally {
      if (mounted) setState(() => _llmBusy = false);
    }
  }

  Future<void> _askLocalLlm({required bool workspace}) async {
    final question = _localQuestion.text.trim();
    if (question.isEmpty) {
      setState(() => _error = 'Scrivi una domanda per il modello locale.');
      return;
    }
    if (!workspace && widget.currentNote == null) {
      setState(
          () => _error = 'Apri una nota per usare “Chiedi a questa nota”.');
      return;
    }

    setState(() {
      _llmBusy = true;
      _llmAnswer = null;
      _error = null;
    });
    try {
      String prompt;
      if (workspace) {
        final unified = widget.unifiedSearch;
        final retrieval = unified == null
            ? _engine.ask(question, widget.notes)
            : await unified(question);
        if (retrieval.hits.isEmpty) {
          throw const LocalLlmException(
            'Nessuna fonte locale rilevante per questa domanda.',
          );
        }
        prompt = LocalLlmPolicy.workspacePrompt(
          question: question,
          sources: retrieval.hits.map(
            (hit) => (
              title: hit.note.title.trim().isEmpty
                  ? 'Senza titolo'
                  : hit.note.title,
              excerpt: hit.excerpt,
            ),
          ),
        );
      } else {
        final note = widget.currentNote!;
        prompt = LocalLlmPolicy.notePrompt(
          question: question,
          title: note.title,
          body: _sourceText(note),
          tags: note.tags,
        );
      }

      final answer = await _localLlm.generate(prompt: prompt);
      if (!mounted) return;
      setState(() => _llmAnswer = answer);
      await _loadLocalLlmStatus();
    } catch (error) {
      if (mounted) setState(() => _error = userErrorText(error));
    } finally {
      if (mounted) setState(() => _llmBusy = false);
    }
  }

  Future<void> _cancelLocalLlm() async {
    await _localLlm.cancel();
    if (mounted) setState(() => _llmBusy = false);
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
                const SizedBox(height: 12),
                const PlusLocalAiCard(),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.memory_outlined),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'AI locale adattiva',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (_llmStatus?.available == true)
                              const Chip(label: Text('Gemini Nano'))
                            else
                              const Chip(label: Text('Semantic fallback')),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _llmStatus == null
                              ? 'Controllo Android AICore…'
                              : _llmStatus!.available
                                  ? 'Gemini Nano è già disponibile sul dispositivo. '
                                      'Il modello è gestito da Android e non aumenta il peso di Notes.'
                                  : _llmStatus!.downloadable
                                      ? 'Gemini Nano è supportato ma non ancora pronto. '
                                          'Android può preparare il modello di sistema senza inserirlo nell’APK di Notes.'
                                      : _llmStatus!.downloading
                                          ? 'Android sta preparando Gemini Nano…'
                                          : 'Gemini Nano non è disponibile su questo dispositivo. '
                                              'Notes continua con Semantic Retrieval locale; '
                                              '${LocalLlmPolicy.lightweightFallback} resta il fallback ultraleggero candidato.',
                        ),
                        if (_llmStatus?.error != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _llmStatus!.error!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_llmStatus?.downloadable == true)
                              FilledButton.tonalIcon(
                                onPressed:
                                    _llmBusy ? null : _downloadSystemModel,
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Prepara Gemini Nano'),
                              ),
                            OutlinedButton.icon(
                              onPressed: _llmBusy ? null : _loadLocalLlmStatus,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Ricontrolla'),
                            ),
                          ],
                        ),
                        if (_llmStatus?.downloading == true || _llmBusy) ...[
                          const SizedBox(height: 10),
                          const LinearProgressIndicator(),
                        ],
                        if (_llmStatus?.available == true) ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _localQuestion,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: LocalLlmPolicy.maxQuestionChars,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.psychology_outlined),
                              hintText:
                                  'Fai una domanda all’AI locale del telefono…',
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (widget.currentNote != null)
                                FilledButton.icon(
                                  onPressed: _llmBusy
                                      ? null
                                      : () => _askLocalLlm(workspace: false),
                                  icon: const Icon(Icons.description_outlined),
                                  label: const Text('Chiedi a questa nota'),
                                ),
                              FilledButton.icon(
                                onPressed: _llmBusy
                                    ? null
                                    : () => _askLocalLlm(workspace: true),
                                icon: const Icon(Icons.hub_outlined),
                                label: const Text('Chiedi al workspace'),
                              ),
                              if (_llmBusy)
                                TextButton.icon(
                                  onPressed: _cancelLocalLlm,
                                  icon: const Icon(Icons.stop_circle_outlined),
                                  label: const Text('Interrompi'),
                                ),
                            ],
                          ),
                          if (_llmAnswer != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: SelectableText(_llmAnswer!.text),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_llmAnswer!.modelName} · '
                                    '${_llmAnswer!.backend} · '
                                    '${(_llmAnswer!.elapsedMs / 1000).toStringAsFixed(1)} s',
                                    style:
                                        Theme.of(context).textTheme.labelSmall,
                                  ),
                                ),
                                if (widget.onInsertMarkdown != null)
                                  TextButton.icon(
                                    onPressed: () {
                                      widget.onInsertMarkdown!(
                                        '\n\n${_llmAnswer!.text}\n',
                                      );
                                      Navigator.pop(context);
                                    },
                                    icon: const Icon(Icons.add),
                                    label: const Text('Inserisci'),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
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
