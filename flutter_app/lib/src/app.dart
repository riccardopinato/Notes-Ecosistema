import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'domain/attachments.dart';
import 'domain/backup.dart';
import 'domain/diary.dart';
import 'domain/note.dart';
import 'domain/quick_capture.dart';
import 'domain/templates.dart';
import 'domain/visual_documents.dart';
import 'platform/quick_capture_bridge.dart';
import 'platform/reminder_bridge.dart';
import 'screens/diary_screen.dart';
import 'screens/editor_screen.dart';
import 'screens/home_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/planner_screen.dart';
import 'screens/sketch_screen.dart';
import 'screens/templates_screen.dart';
import 'screens/whiteboard_screen.dart';
import 'state/workspace_controller.dart';
import 'theme/notes_theme.dart';
import 'widgets/editorial.dart';

class NotesEcosistemaApp extends ConsumerStatefulWidget {
  const NotesEcosistemaApp({super.key});

  @override
  ConsumerState<NotesEcosistemaApp> createState() => _NotesEcosistemaAppState();
}

class _NotesEcosistemaAppState extends ConsumerState<NotesEcosistemaApp> {
  bool _dark = false;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('it_IT');
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _dark = prefs.getBool('dark_mode') ?? false);
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Notes Ecosistema',
        debugShowCheckedModeBanner: false,
        theme: NotesTheme.light(),
        darkTheme: NotesTheme.dark(),
        themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
        home: WorkspaceShell(
          dark: _dark,
          onDarkChanged: (value) async {
            setState(() => _dark = value);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('dark_mode', value);
          },
        ),
      );
}

class WorkspaceShell extends ConsumerStatefulWidget {
  const WorkspaceShell({
    required this.dark,
    required this.onDarkChanged,
    super.key,
  });

  final bool dark;
  final ValueChanged<bool> onDarkChanged;

  @override
  ConsumerState<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends ConsumerState<WorkspaceShell> {
  int _index = 0;
  String _query = '';
  String _reminderSignature = '';

  static const labels = ['Home', 'Note', 'Diario', 'Attività', 'Cerca'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      QuickCaptureBridge.initialize(_handleIncomingCapture);
    });
  }

  Future<void> _handleIncomingCapture(IncomingCapture capture) async {
    if (!mounted) return;

    if (capture.error != null && capture.error!.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(capture.error!)),
      );
      return;
    }

    try {
      var body = capture.seed.body;
      if (capture.seed.checklist && body.trim().isEmpty) {
        body = '- [ ] ';
      }

      if (capture.files.isNotEmpty) {
        final store = await AttachmentStore.open();
        for (final shared in capture.files.take(20)) {
          final file = File(shared.path);
          if (!await file.exists()) continue;
          final bytes = await file.readAsBytes();
          final type = Attachments.typeFromName(shared.name) ??
              switch (shared.mime.toLowerCase()) {
                'application/pdf' => AttachmentType.pdf,
                'image/png' => AttachmentType.png,
                'image/webp' => AttachmentType.webp,
                _ => AttachmentType.jpeg,
              };
          final key = await store.ingest(bytes, type);
          body = Attachments.append(body, key, shared.name);
          await file.delete().catchError((_) => file);
        }
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await _openEditor(
        Note(
          id: const Uuid().v4(),
          title: capture.seed.title,
          body: body,
          favorite: false,
          createdAt: now,
          updatedAt: now,
          pinned: false,
          archived: false,
          tags: const [],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _openEditor([Note? note]) async {
    if (note?.isVisual == true) {
      await _openVisual(note!);
      return;
    }

    final collections = ref.read(workspaceProvider).collections;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          note: note,
          collections: collections,
          allNotes: ref.read(workspaceProvider).notes,
        ),
      ),
    );
    await ref.read(workspaceProvider.notifier).refresh();
  }

  Future<void> _openVisual(Note note) async {
    if (note.visualKind == VisualDocumentKind.whiteboard) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WhiteboardScreen(
            note: note,
            onSave: (updated) =>
                ref.read(workspaceProvider.notifier).save(updated),
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SketchScreen(
            note: note,
            onSave: (updated) =>
                ref.read(workspaceProvider.notifier).save(updated),
          ),
        ),
      );
    }
    await ref.read(workspaceProvider.notifier).refresh();
  }

  Future<void> _openTemplates() async {
    final workspace = ref.read(workspaceProvider);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplatesScreen(
          notes: workspace.notes,
          onUse: (content) {
            Navigator.pop(context);
            _openTemplateDraft(content);
          },
          onEdit: (note) {
            Navigator.pop(context);
            _openEditor(note);
          },
        ),
      ),
    );
    await ref.read(workspaceProvider.notifier).refresh();
  }

  Future<void> _openTemplateDraft(TemplateContent content) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _openEditor(
      Note(
        id: const Uuid().v4(),
        title: content.title,
        body: content.body,
        favorite: false,
        createdAt: now,
        updatedAt: now,
        pinned: false,
        archived: false,
        tags: content.tags,
      ),
    );
  }

  Future<void> _createVisual({
    required VisualInfoKind kind,
    WhiteboardMode whiteboardMode = WhiteboardMode.freeform,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = const Uuid().v4();
    final note = kind == VisualInfoKind.sketch
        ? Note(
            id: id,
            title: 'Nuovo disegno',
            body: SketchCodec.encode(SketchDocument()),
            favorite: false,
            createdAt: now,
            updatedAt: now,
            pinned: false,
            archived: false,
            tags: const [],
            sketchJson: const VisualInfo(
              kind: VisualInfoKind.sketch,
            ).encode(),
          )
        : Note(
            id: id,
            title: whiteboardMode == WhiteboardMode.mindMap
                ? 'Nuova mind map'
                : 'Nuova lavagna',
            body: WhiteboardCodec.encode(
              WhiteboardOps.empty(whiteboardMode),
            ),
            favorite: false,
            createdAt: now,
            updatedAt: now,
            pinned: false,
            archived: false,
            tags: const [],
            sketchJson: const VisualInfo(
              kind: VisualInfoKind.whiteboard,
            ).encode(),
          );

    await ref.read(workspaceProvider.notifier).save(note);
    await _openVisual(note);
  }

  Future<void> _createDiaryEntry(
    DateTime date,
    String? collectionId,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final draft = Note(
      id: const Uuid().v4(),
      title: '',
      body: '',
      collectionId: collectionId,
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      tags: Diary.datedTags(const [], date),
    );
    await _openEditor(draft);
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final section = labels[_index];

    if (!workspace.loading) {
      final reminderSignature = workspace.notes
          .where((note) => note.isTask)
          .map(
            (note) =>
                '${note.id}|${note.title}|${note.taskJson}|${note.deletedAt}|${note.archived}',
          )
          .join('\n');
      if (reminderSignature != _reminderSignature) {
        _reminderSignature = reminderSignature;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ReminderBridge.sync(workspace.notes).catchError((_) {});
          }
        });
      }
    }

    Widget body;
    if (workspace.loading && workspace.notes.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (workspace.error != null && workspace.notes.isEmpty) {
      body = _ErrorState(
        onRetry: () => ref.read(workspaceProvider.notifier).refresh(),
      );
    } else if (_index == 0) {
      body = HomeScreen(
        notes: workspace.notes,
        collections: workspace.collections,
        onCreate: _openEditor,
        onNotes: () => setState(() => _index = 1),
        onAgenda: () => setState(() => _index = 3),
        onTasks: () => setState(() => _index = 3),
        onSketch: () => _createVisual(kind: VisualInfoKind.sketch),
      );
    } else if (_index == 1 || _index == 4) {
      body = NotesScreen(
        notes: workspace.notes,
        collections: workspace.collections,
        query: _query,
        searchMode: _index == 4,
        onQueryChanged: (value) => setState(() => _query = value),
        onOpen: _openEditor,
        onFavorite: (id) =>
            ref.read(workspaceProvider.notifier).favorite(id),
        onPin: (id, value) =>
            ref.read(workspaceProvider.notifier).pin(id, value),
        onTrash: (id) => ref.read(workspaceProvider.notifier).trash(id),
      );
    } else if (_index == 2) {
      body = DiaryScreen(
        notes: workspace.notes,
        collections: workspace.collections,
        onOpen: _openEditor,
        onCreate: _createDiaryEntry,
        onOpenTask: (_) => setState(() => _index = 3),
        onCreateCollection: (name) =>
            ref.read(workspaceProvider.notifier).createCollection(name),
      );
    } else {
      body = PlannerScreen(
        notes: workspace.notes,
        onSave: (note) => ref.read(workspaceProvider.notifier).save(note),
        onTrash: (id) => ref.read(workspaceProvider.notifier).trash(id),
        onOpenNote: _openEditor,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: EditorialAppTitle(section == 'Home' ? 'Il tuo spazio' : section),
        actions: [
          IconButton(
            tooltip: 'Impostazioni',
            onPressed: () => _settings(context),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: body,
      floatingActionButton: (_index == 4 || _index == 2 || _index == 3)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _createMenu(context),
              icon: const Icon(Icons.add),
              label: const Text('Crea'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.description), label: 'Note'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Diario'),
          NavigationDestination(icon: Icon(Icons.check_circle), label: 'Attività'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Cerca'),
        ],
      ),
    );
  }

  Future<void> _createMenu(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.note_add),
              title: const Text('Nuova nota'),
              onTap: () => Navigator.pop(context, 'note'),
            ),
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('Diario di oggi'),
              onTap: () => Navigator.pop(context, 'diary'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Nuova attività'),
              onTap: () => Navigator.pop(context, 'task'),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_customize),
              title: const Text('Modelli'),
              onTap: () => Navigator.pop(context, 'templates'),
            ),
            ListTile(
              leading: const Icon(Icons.draw),
              title: const Text('Nuovo disegno'),
              onTap: () => Navigator.pop(context, 'sketch'),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Nuova lavagna'),
              onTap: () => Navigator.pop(context, 'board'),
            ),
            ListTile(
              leading: const Icon(Icons.account_tree),
              title: const Text('Nuova mind map'),
              onTap: () => Navigator.pop(context, 'mind'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'note') {
      await _openEditor();
    } else if (action == 'diary') {
      await _createDiaryEntry(DateTime.now(), null);
    } else if (action == 'task') {
      setState(() => _index = 3);
    } else if (action == 'templates') {
      await _openTemplates();
    } else if (action == 'sketch') {
      await _createVisual(kind: VisualInfoKind.sketch);
    } else if (action == 'board') {
      await _createVisual(kind: VisualInfoKind.whiteboard);
    } else if (action == 'mind') {
      await _createVisual(
        kind: VisualInfoKind.whiteboard,
        whiteboardMode: WhiteboardMode.mindMap,
      );
    } else {
      _showPending(action);
    }
  }

  void _showPending(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature: porting Flutter in corso.')),
    );
  }

  Future<void> _exportBackup() async {
    try {
      final snapshot = await ref.read(workspaceProvider.notifier).snapshot();
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await FilePicker.platform.saveFile(
        dialogTitle: 'Esporta backup Notes',
        fileName: 'notes-ecosistema-$stamp.json',
        bytes: backupUtf8(snapshot),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup esportato.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('Impossibile leggere il backup.');
      }
      final snapshot = BackupCodec.decode(
        utf8.decode(bytes, allowMalformed: false),
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importare il backup?'),
          content: Text(
            'Verranno create copie separate: '
            '${snapshot.notes.length} elementi, '
            '${snapshot.collections.length} raccolte e '
            '${snapshot.drafts.length} bozze. '
            'I dati esistenti non verranno sovrascritti.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importa copie'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await ref.read(workspaceProvider.notifier).importCopies(snapshot);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup importato come copie.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('FormatException: ', ''),
          ),
        ),
      );
    }
  }

  Future<void> _settings(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EditorialAppTitle('Impostazioni'),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Tema scuro'),
                  value: widget.dark,
                  onChanged: widget.onDarkChanged,
                ),
                ListTile(
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('Esporta backup'),
                  subtitle: const Text('Backup JSON v6 compatibile con la versione Kotlin.'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportBackup();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Importa backup'),
                  subtitle: const Text('Importa come copie senza sovrascrivere i dati attuali.'),
                  onTap: () {
                    Navigator.pop(context);
                    _importBackup();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifiche promemoria'),
                  subtitle: const Text(
                    'Abilita le notifiche Android per i promemoria delle attività.',
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    final allowed =
                        await ReminderBridge.requestPermission();
                    if (!mounted) return;
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          allowed
                              ? 'Notifiche promemoria abilitate.'
                              : 'Notifiche non abilitate. I promemoria restano salvati.',
                        ),
                      ),
                    );
                  },
                ),
                const ListTile(
                  title: Text('Notes · Flutter port 0.25.0'),
                  subtitle: Text(
                    'Database locale compatibile con Notes Ecosistema Kotlin / Room v8.',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const Icon(Icons.error_outline, size: 42),
          const SizedBox(height: 12),
          Text(
            'Database non disponibile.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Il port Flutter non ha modificato i dati. Riprova ad aprire il database locale.',
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Riprova')),
        ],
      );
}
