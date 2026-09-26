import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/focus.dart';
import '../domain/note.dart';
import '../domain/workday.dart';
import '../widgets/editorial.dart';

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
  final int sharedUnread;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<FocusClock?> _focus;

  @override
  void initState() {
    super.initState();
    _focus = _activeFocus();
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
              const EditorialEyebrow('IL TUO TACCUINO'),
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
