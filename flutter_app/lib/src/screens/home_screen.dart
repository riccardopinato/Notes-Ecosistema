import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_locale.dart';
import '../domain/contextual_work_insights.dart';
import '../domain/focus.dart';
import '../domain/note.dart';
import '../domain/smart_inbox_source_preview.dart';
import '../domain/workday.dart';
import '../widgets/editorial.dart';
import 'document_delta_screen.dart';
import '../domain/document_delta.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.notes,
    required this.collections,
    required this.onCreate,
    required this.onNotes,
    required this.onAgenda,
    required this.onTasks,
    required this.onSketch,
    required this.onCollection,
    required this.onOpenNote,
    this.onDraftSmartInboxTags,
    this.onCreateSmartInboxChecklistTask,
    this.onUndoSmartInboxChecklistTask,
    required this.onProjects,
    this.onStudy,
    this.onGraph,
    this.onAutomations,
    required this.projectCount,
    this.sharedUnread = 0,
    super.key,
  });

  final List<Note> notes;
  final List<NoteCollection> collections;
  final VoidCallback onCreate;
  final VoidCallback onNotes;
  final VoidCallback onAgenda;
  final VoidCallback onTasks;
  final VoidCallback onSketch;
  final ValueChanged<String> onCollection;
  final ValueChanged<Note> onOpenNote;

  /// Opens the canonical editor with user-selected tag drafts; never saves here.
  final Future<void> Function(Note source, List<String> selectedTags)?
      onDraftSmartInboxTags;

  /// A confirmed source-backed action creates exactly one canonical Task.
  final Future<String> Function(Note source, List<String> selected)?
      onCreateSmartInboxChecklistTask;
  final Future<void> Function(String taskId)? onUndoSmartInboxChecklistTask;
  final VoidCallback onProjects;
  final VoidCallback? onStudy;
  final VoidCallback? onGraph;
  final VoidCallback? onAutomations;
  final int projectCount;
  final int sharedUnread;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<FocusClock?> _focus;
  bool _reviewsReady = false;
  final Set<String> _dismissed = {};
  final Set<String> _mutedCategories = {};
  final Map<String, int> _snoozed = {};

  // Persist only hashed source identity, revision and reason. Never note text.
  String _reviewKey(InboxReviewSuggestion suggestion) => sha256
      .convert(utf8.encode(
        '${suggestion.note.id}|${suggestion.note.updatedAt}|${suggestion.reasonCode}',
      ))
      .toString();

  Future<void> _loadReviewPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!mounted) return;
      setState(() {
        _dismissed.addAll(
          prefs.getStringList('notes_review_dismissed_v1') ?? const [],
        );
        _mutedCategories.addAll(
          prefs.getStringList('notes_review_muted_v1') ?? const [],
        );
        for (final entry in prefs.getStringList('notes_review_snoozed_v1') ??
            const <String>[]) {
          final parts = entry.split(':');
          if (parts.length != 2) continue;
          final until = int.tryParse(parts[1]);
          if (until != null && until > now) _snoozed[parts[0]] = until;
        }
        _reviewsReady = true;
      });
    } catch (_) {
      // Fail closed: do not resurface muted private suggestions after a
      // preference loading error.
    }
  }

  Future<void> _previewSmartInbox(InboxReviewSuggestion suggestion) async {
    final preview = SmartInboxSourcePreview.inspect(suggestion);
    if (!mounted) return;
    if (preview == null) {
      // Unsupported empty/oversize candidates still open the canonical editor,
      // provided their original source remains uniquely visible and unchanged.
      final matches = widget.notes
          .where((note) =>
              note.id == suggestion.note.id &&
              !note.isDeleted &&
              !note.archived &&
              !note.isTask &&
              !note.isVisual &&
              note.updatedAt == suggestion.note.updatedAt &&
              note.body == suggestion.note.body &&
              note.title == suggestion.note.title &&
              note.tags.length == suggestion.note.tags.length &&
              List.generate(note.tags.length, (i) => i)
                  .every((i) => note.tags[i] == suggestion.note.tags[i]))
          .toList();
      if (matches.length == 1) widget.onOpenNote(matches.single);
      return;
    }
    if (preview.current(widget.notes) == null) return;
    final code = AppLocale.effectiveCode(Localizations.localeOf(context));
    final labels = switch (code) {
      'it' => [
          'Anteprima suggerimento',
          'Annulla',
          'Apri nell’editor',
          'Nessuna modifica automatica. Controlla e salva nell’editor.'
        ],
      'es' => [
          'Vista previa',
          'Cancelar',
          'Abrir en el editor',
          'Sin cambios automáticos. Revisa y guarda en el editor.'
        ],
      'fr' => [
          'Aperçu',
          'Annuler',
          'Ouvrir dans l’éditeur',
          'Aucune modification automatique. Vérifiez dans l’éditeur.'
        ],
      'de' => [
          'Vorschau',
          'Abbrechen',
          'Im Editor öffnen',
          'Keine automatische Änderung. Im Editor prüfen und speichern.'
        ],
      'pt' => [
          'Prévia',
          'Cancelar',
          'Abrir no editor',
          'Sem alterações automáticas. Revise e salve no editor.'
        ],
      _ => [
          'Suggestion preview',
          'Cancel',
          'Open in editor',
          'No automatic edits. Review and save in the editor.'
        ],
    };
    final selectedTags = <String>{};
    final canCreateChecklist = suggestion.kind == InboxReviewKind.checklist &&
        widget.onCreateSmartInboxChecklistTask != null;
    if (canCreateChecklist) selectedTags.addAll(preview.candidates);
    final canDraftTags = suggestion.kind == InboxReviewKind.explicitTags &&
        widget.onDraftSmartInboxTags != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(labels[0]),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preview.source.title),
                  const SizedBox(height: 8),
                  Text(preview.reasonCode,
                      style: Theme.of(dialogContext).textTheme.labelSmall),
                  const SizedBox(height: 8),
                  Text(preview.sourceExcerpt),
                  const SizedBox(height: 12),
                  ...preview.candidates
                      .map((value) => (canDraftTags || canCreateChecklist)
                          ? CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: selectedTags.contains(value),
                              title:
                                  Text(canCreateChecklist ? value : '#$value'),
                              onChanged: (checked) => setDialogState(() {
                                if (checked == true) {
                                  selectedTags.add(value);
                                } else {
                                  selectedTags.remove(value);
                                }
                              }),
                            )
                          : Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('• $value'),
                            )),
                  const SizedBox(height: 12),
                  Text(labels[3]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(labels[1])),
            FilledButton(
              key: const ValueKey('smart-inbox-preview-open-editor'),
              onPressed:
                  (canDraftTags || canCreateChecklist) && selectedTags.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, true),
              child: Text(canCreateChecklist
                  ? switch (code) {
                      'it' => 'Crea attività',
                      'es' => 'Crear tarea',
                      'fr' => 'Créer une tâche',
                      'de' => 'Aufgabe erstellen',
                      'pt' => 'Criar tarefa',
                      _ => 'Create task',
                    }
                  : canDraftTags
                      ? switch (code) {
                          'it' => 'Apri bozza con tag',
                          'es' => 'Abrir borrador con etiquetas',
                          'fr' => 'Ouvrir le brouillon avec tags',
                          'de' => 'Entwurf mit Tags öffnen',
                          'pt' => 'Abrir rascunho com tags',
                          _ => 'Open draft with tags',
                        }
                      : labels[2]),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    final current = preview.current(widget.notes);
    if (current == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Fonte non più disponibile o modificata.')),
      );
      return;
    }
    if (canCreateChecklist) {
      try {
        final id = await widget.onCreateSmartInboxChecklistTask!(
            current, preview.candidates.where(selectedTags.contains).toList());
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(switch (code) {
            'it' => 'Attività creata dalla checklist',
            'es' => 'Tarea creada desde la lista',
            'fr' => 'Tâche créée depuis la liste',
            'de' => 'Aufgabe aus Checkliste erstellt',
            'pt' => 'Tarefa criada a partir da lista',
            _ => 'Task created from checklist',
          }),
          action: widget.onUndoSmartInboxChecklistTask == null
              ? null
              : SnackBarAction(
                  label: switch (code) {
                    'it' => 'Annulla',
                    'es' => 'Deshacer',
                    'fr' => 'Annuler',
                    'de' => 'Rückgängig',
                    'pt' => 'Desfazer',
                    _ => 'Undo',
                  },
                  onPressed: () => unawaited(_undoChecklistTask(id)),
                ),
        ));
      } on Object catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(error.toString().replaceFirst('FormatException: ', ''))),
        );
      }
      return;
    }
    if (canDraftTags) {
      try {
        preview.selectedTagDraft(selectedTags);
        await widget.onDraftSmartInboxTags!(current, selectedTags.toList());
      } on Object catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Suggerimento non applicabile.')),
          );
        }
      }
      return;
    }
    widget.onOpenNote(current);
  }

  Future<void> _undoChecklistTask(String id) async {
    try {
      await widget.onUndoSmartInboxChecklistTask!(id);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(error.toString().replaceFirst('FormatException: ', ''))),
      );
    }
  }

  Future<void> _handleReview(
      InboxReviewSuggestion suggestion, String action) async {
    if (!mounted) return;
    final key = _reviewKey(suggestion);
    setState(() {
      if (action == 'dismiss') {
        _dismissed.remove(key);
        _dismissed.add(key);
        while (_dismissed.length > 200) {
          _dismissed.remove(_dismissed.first);
        }
      } else if (action == 'snooze') {
        _snoozed.remove(key);
        _snoozed[key] =
            DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch;
        final now = DateTime.now().millisecondsSinceEpoch;
        _snoozed.removeWhere((_, until) => until <= now);
        while (_snoozed.length > 200) {
          _snoozed.remove(_snoozed.keys.first);
        }
      } else if (action == 'mute') {
        _mutedCategories.add(suggestion.kind.name);
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('notes_review_dismissed_v1',
          _dismissed.take(200).toList(growable: false));
      await prefs.setStringList(
          'notes_review_muted_v1', _mutedCategories.toList(growable: false));
      await prefs.setStringList(
        'notes_review_snoozed_v1',
        _snoozed.entries
            .take(200)
            .map((entry) => '${entry.key}:${entry.value}')
            .toList(growable: false),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Impossibile salvare la preferenza locale.')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _focus = _activeFocus();
    _loadReviewPreferences();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final active = widget.notes
        .where((n) => !n.isDeleted && !n.archived && !n.isTask)
        .length;
    final pending = widget.notes
        .where((n) => !n.isDeleted && n.isTask && !n.taskCompleted)
        .length;
    final reviewSuggestions = _reviewsReady
        ? SmartInboxReview.suggest(
            widget.notes,
            limit: 3,
            include: (suggestion) {
              final key = _reviewKey(suggestion);
              return !_dismissed.contains(key) &&
                  !_mutedCategories.contains(suggestion.kind.name) &&
                  (_snoozed[key] ?? 0) <= now.millisecondsSinceEpoch;
            },
          )
        : const <InboxReviewSuggestion>[];
    final briefing = Workday.build(
      notes: widget.notes,
      now: now,
      sharedUnread: widget.sharedUnread,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
      children: [
        EditorialEyebrow(DateFormat('EEEE d MMMM', 'it_IT').format(now)),
        const SizedBox(height: 4),
        Text('Oggi, nel tuo spazio.',
            style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 16),
        _DailyBriefingCard(
          briefing: briefing,
          onOpenPlanner: widget.onAgenda,
          onOpenNote: widget.onOpenNote,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
                child: _Metric(
                    count: active,
                    label: 'Pagine salvate',
                    onTap: widget.onNotes)),
            const SizedBox(width: 12),
            Expanded(
                child: _Metric(
                    count: pending,
                    label: 'Attività da fare',
                    onTap: widget.onTasks)),
          ],
        ),
        const SizedBox(height: 16),
        _NotebookCard(onCreate: widget.onCreate, onSketch: widget.onSketch),
        const SizedBox(height: 16),
        _ProjectCard(
          count: widget.projectCount,
          onTap: widget.onProjects,
        ),
        const SizedBox(height: 16),
        if (reviewSuggestions.isNotEmpty) ...[
          ...reviewSuggestions.map((suggestion) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SmartInboxCard(
                  suggestion: suggestion,
                  onOpenNote: (_) => _previewSmartInbox(suggestion),
                  onAction: (action) => _handleReview(suggestion, action),
                ),
              )),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          key: const ValueKey('document-delta-open'),
          onPressed: () {
            final sources = widget.notes
                .where((note) =>
                    !note.isDeleted &&
                    !note.archived &&
                    !note.isTask &&
                    !note.isVisual &&
                    note.body.trim().isNotEmpty)
                .take(500)
                .map((note) => DocumentDeltaSource(
                      id: note.id,
                      title: note.title.trim().isEmpty
                          ? 'Nota senza titolo'
                          : note.title,
                      text: note.body,
                      revision: note.updatedAt.toString(),
                      provenance: 'Nota locale · revisione ${note.updatedAt}',
                    ))
                .toList(growable: false);
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DocumentDeltaScreen(sources: sources),
            ));
          },
          icon: const Icon(Icons.difference_outlined),
          label: const Text('Confronta due note'),
        ),
        const SizedBox(height: 12),
        _StudyCard(onTap: widget.onStudy),
        const SizedBox(height: 16),
        _KnowledgeGraphCard(onTap: widget.onGraph),
        const SizedBox(height: 16),
        _AutomationCard(onTap: widget.onAutomations),
        const SizedBox(height: 16),
        FutureBuilder<FocusClock?>(
          future: _focus,
          builder: (context, snapshot) => _FocusCard(
            onTap: widget.onTasks,
            active: snapshot.data != null,
          ),
        ),
        if (widget.collections.isNotEmpty) ...[
          const SizedBox(height: 8),
          const EditorialSection('Le tue raccolte'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.collections
                .map((c) => ActionChip(
                      avatar: const Icon(Icons.folder, size: 18),
                      label: Text(c.name),
                      onPressed: () => widget.onCollection(c.id),
                    ))
                .toList(),
          ),
        ],
        const EditorialSection('Tra le tue pagine',
            detail: 'Note, idee e progetti da ritrovare.'),
      ],
    );
  }

  Future<FocusClock?> _activeFocus() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('planner_focus_active_v1');
    if (raw == null || raw.isEmpty) return null;
    try {
      return FocusClock.decode(raw);
    } catch (_) {
      return null;
    }
  }
}

class _DailyBriefingCard extends StatelessWidget {
  const _DailyBriefingCard({
    required this.briefing,
    required this.onOpenPlanner,
    required this.onOpenNote,
  });

  final WorkdayBriefing briefing;
  final VoidCallback onOpenPlanner;
  final ValueChanged<Note> onOpenNote;

  @override
  Widget build(BuildContext context) => _SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const EditorialEyebrow('DAILY WORK BRIEFING'),
            const SizedBox(height: 6),
            Text(
              'Oggi',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            if (briefing.items.isEmpty)
              Text(
                'Nessun blocco pianificato oggi.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...briefing.items.take(5).map(
                    (item) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: SizedBox(
                        width: 54,
                        child: Text(
                          item.time ?? '—',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      title: Text(
                        item.note.title.trim().isEmpty
                            ? 'Attività'
                            : item.note.title,
                      ),
                      onTap: onOpenPlanner,
                    ),
                  ),
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (briefing.dueToday > 0)
                  Chip(
                    avatar: const Icon(Icons.today, size: 18),
                    label: Text(
                      '${briefing.dueToday} task in scadenza',
                    ),
                  ),
                if (briefing.overdue > 0)
                  Chip(
                    avatar: const Icon(Icons.warning_amber, size: 18),
                    label: Text('${briefing.overdue} task arretrati'),
                  ),
                if (briefing.sharedUnread > 0)
                  Chip(
                    avatar: const Icon(Icons.group_work_outlined, size: 18),
                    label: Text(
                      'Workspace · ${briefing.sharedUnread} novità',
                    ),
                  ),
              ],
            ),
            if (briefing.inbox.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Inbox da smistare',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ...briefing.inbox.take(3).map(
                    (note) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.inbox_outlined),
                      title: Text(
                        note.title.trim().isEmpty ? 'Senza titolo' : note.title,
                      ),
                      subtitle: const Text('Apri e assegna raccolta/tag'),
                      onTap: () => onOpenNote(note),
                    ),
                  ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onOpenPlanner,
                child: const Text('Apri Planner'),
              ),
            ),
          ],
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.count, required this.label, required this.onTap});
  final int count;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$count',
                style: Theme.of(context)
                    .textTheme
                    .headlineLarge
                    ?.copyWith(color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      );
}

class _KnowledgeGraphCard extends StatelessWidget {
  const _KnowledgeGraphCard({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _SurfaceCard(
        onTap: onTap,
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.hub_outlined)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Knowledge Graph',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Esplora link, relazioni, progetti, Study e documenti come una rete navigabile.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      );
}

class _AutomationCard extends StatelessWidget {
  const _AutomationCard({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return _SurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          const CircleAvatar(child: Icon(Icons.auto_mode_outlined)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.automations,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  strings.automationsSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _NotebookCard extends StatelessWidget {
  const _NotebookCard({required this.onCreate, required this.onSketch});
  final VoidCallback onCreate;
  final VoidCallback onSketch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primary,
      borderRadius: BorderRadius.circular(32),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: colors.onPrimary),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EditorialEyebrow(
                'IL TUO TACCUINO',
                color: colors.onPrimary,
              ),
              const SizedBox(height: 8),
              Text('Scrivi. Disegna.\nDai forma alle idee.',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: colors.onPrimary)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                      onPressed: onCreate, child: const Text('Nuova nota')),
                  FilledButton.tonal(
                      onPressed: onSketch, child: const Text('Sketchbook')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: const Icon(Icons.work_outline),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project Workspace',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      count == 0
                          ? 'Crea il primo progetto'
                          : '$count progetti attivi · 5 viste universali',
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmartInboxCard extends StatelessWidget {
  const _SmartInboxCard({
    required this.suggestion,
    required this.onOpenNote,
    required this.onAction,
  });

  final InboxReviewSuggestion suggestion;
  final ValueChanged<Note> onOpenNote;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final code = AppLocale.effectiveCode(Localizations.localeOf(context));
    final title = switch (code) {
      'it' => 'Da organizzare',
      'es' => 'Para organizar',
      'fr' => 'À organiser',
      'de' => 'Zum Organisieren',
      'pt' => 'Para organizar',
      _ => 'Needs organizing',
    };
    final detail = switch ((code, suggestion.kind)) {
      ('it', InboxReviewKind.checklist) =>
        'Questa nota contiene una checklist esplicita. Rivedila prima '
            'di trasformarla in attività.',
      ('it', _) =>
        'Questa nota contiene hashtag. Rivedili prima di aggiungere tag.',
      ('es', _) => 'Revisa la nota antes de aplicar cualquier cambio.',
      ('fr', _) => 'Vérifiez la note avant toute modification.',
      ('de', _) => 'Prüfe die Notiz, bevor du Änderungen vornimmst.',
      ('pt', _) => 'Revise a nota antes de aplicar mudanças.',
      _ => 'Review this note before applying any changes.',
    };
    final actions = switch (code) {
      'it' => const ['Ignora', 'Domani', 'Non suggerire più'],
      'es' => const ['Ignorar', 'Mañana', 'No sugerir más'],
      'fr' => const ['Ignorer', 'Demain', 'Ne plus suggérer'],
      'de' => const ['Ignorieren', 'Morgen', 'Nicht mehr vorschlagen'],
      'pt' => const ['Ignorar', 'Amanhã', 'Não sugerir mais'],
      _ => const ['Dismiss', 'Tomorrow', 'Stop suggesting'],
    };
    return Card(
      child: Column(
        children: [
          ListTile(
            key: const ValueKey('smart-inbox-review'),
            leading: const Icon(Icons.tips_and_updates_outlined),
            title: Text(title),
            subtitle: Text(
              '${suggestion.note.title.isEmpty ? title : suggestion.note.title}'
              ' · $detail',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onOpenNote(suggestion.note),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => onAction('dismiss'),
                  child: Text(actions[0]),
                ),
                TextButton(
                  onPressed: () => onAction('snooze'),
                  child: Text(actions[1]),
                ),
                TextButton(
                  onPressed: () => onAction('mute'),
                  child: Text(actions[2]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudyCard extends StatelessWidget {
  const _StudyCard({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = colors.onTertiary;
    return Material(
      color: colors.tertiaryContainer,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.school_outlined, size: 28, color: foreground),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EditorialEyebrow('STUDY', color: foreground),
                    Text(
                      'Ripassa dalle tue note.',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(color: foreground),
                    ),
                    Text(
                      'LearningItem source-linked e coda giornaliera semplice.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: foreground),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.onTap, required this.active});
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.secondaryContainer,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const Icon(Icons.timer, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const EditorialEyebrow('FOCUS'),
                    Text(
                      active
                          ? 'Riprendi il tuo momento.'
                          : 'Una cosa, fatta bene.',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      active
                          ? 'Apri Attività per continuare la sessione Focus.'
                          : 'Scegli un’attività e dedicagli il tuo tempo.',
                      style: Theme.of(context).textTheme.bodyMedium,
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

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard(
      {required this.child,
      this.onTap,
      this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onTap,
            child: Padding(padding: padding, child: child)),
      );
}
