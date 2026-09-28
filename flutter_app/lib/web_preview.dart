import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:uuid/uuid.dart';

import 'src/domain/diary.dart';
import 'src/domain/editing.dart';
import 'src/domain/library.dart';
import 'src/domain/note.dart';
import 'src/domain/planner.dart';
import 'src/domain/stable_links.dart';
import 'src/domain/unified_retrieval.dart';
import 'src/domain/visual_documents.dart';
import 'src/screens/diary_screen.dart';
import 'src/screens/home_screen.dart';
import 'src/screens/notes_screen.dart';
import 'src/screens/planner_screen.dart';
import 'src/screens/sketch_screen.dart';
import 'src/screens/templates_screen.dart';
import 'src/screens/whiteboard_screen.dart';
import 'src/theme/notes_theme.dart';
import 'src/widgets/editorial.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');
  runApp(const NotesWebPreview());
}

class NotesWebPreview extends StatefulWidget {
  const NotesWebPreview({super.key});

  @override
  State<NotesWebPreview> createState() => _NotesWebPreviewState();
}

class _NotesWebPreviewState extends State<NotesWebPreview> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Notes Ecosistema 0.51 · Web',
      theme: NotesTheme.light(),
      darkTheme: NotesTheme.dark(),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: _WebWorkspaceShell(
        dark: _dark,
        onDarkChanged: (value) => setState(() => _dark = value),
      ),
    );
  }
}

class _WebWorkspaceShell extends StatefulWidget {
  const _WebWorkspaceShell({
    required this.dark,
    required this.onDarkChanged,
  });

  final bool dark;
  final ValueChanged<bool> onDarkChanged;

  @override
  State<_WebWorkspaceShell> createState() => _WebWorkspaceShellState();
}

class _WebWorkspaceShellState extends State<_WebWorkspaceShell> {
  int _index = 0;
  String _query = '';
  String? _libraryCollectionId;
  String? _plannerTaskId;

  final List<NoteCollection> _collections = [
    const NoteCollection(id: 'work', name: 'Lavoro'),
    const NoteCollection(id: 'study', name: 'Studio'),
    const NoteCollection(id: 'ideas', name: 'Idee'),
  ];

  late List<Note> _notes = _seedNotes();

  static const _labels = [
    'Home',
    'Note',
    'Diario',
    'Attività',
    'Spazi',
    'Cerca',
  ];

  List<Note> get _personalNotes =>
      _notes.where((note) => !note.isDeleted).toList(growable: false);

  void _selectSection(int value) {
    setState(() {
      if (value == 1) _libraryCollectionId = null;
      if (value != 3) _plannerTaskId = null;
      _index = value;
    });
  }

  Future<void> _save(Note note) async {
    setState(() {
      final index = _notes.indexWhere((item) => item.id == note.id);
      if (index < 0) {
        _notes = [note, ..._notes];
      } else {
        final next = [..._notes];
        next[index] = note;
        _notes = next;
      }
    });
  }

  void _favorite(String id) {
    final note = _notes.where((item) => item.id == id).firstOrNull;
    if (note == null) return;
    unawaited(
      _save(
        note.copyWith(
          favorite: !note.favorite,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  void _pin(String id, bool value) {
    final note = _notes.where((item) => item.id == id).firstOrNull;
    if (note == null) return;
    unawaited(
      _save(
        note.copyWith(
          pinned: value,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  void _archive(String id, bool value) {
    final note = _notes.where((item) => item.id == id).firstOrNull;
    if (note == null) return;
    unawaited(
      _save(
        note.copyWith(
          archived: value,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  void _trash(String id) {
    final note = _notes.where((item) => item.id == id).firstOrNull;
    if (note == null) return;
    unawaited(
      _save(
        note.copyWith(
          deletedAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
    );
  }

  Future<void> _restore(String id) async {
    final note = _notes.where((item) => item.id == id).firstOrNull;
    if (note == null) return;
    await _save(
      note.copyWith(
        deletedAt: null,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _deleteForever(String id) async {
    setState(() => _notes = _notes.where((note) => note.id != id).toList());
  }

  Future<int> _bulkEdit(List<Note> selected, BulkChange change) async {
    final updated = planBulkEdit(
      selected,
      change,
      DateTime.now().millisecondsSinceEpoch,
    );
    final byId = {for (final note in updated) note.id: note};
    setState(() {
      _notes = [
        for (final note in _notes) byId[note.id] ?? note,
      ];
    });
    return updated.length;
  }

  Future<void> _renameCollection(
    NoteCollection collection,
    String name,
  ) async {
    final index = _collections.indexWhere((item) => item.id == collection.id);
    if (index < 0 || name.trim().isEmpty) return;
    setState(() {
      _collections[index] = NoteCollection(
        id: collection.id,
        name: name.trim(),
      );
    });
  }

  Future<void> _deleteCollection(NoteCollection collection) async {
    setState(() {
      _collections.removeWhere((item) => item.id == collection.id);
      _notes = [
        for (final note in _notes)
          if (note.collectionId == collection.id)
            note.copyWith(
              collectionId: null,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            )
          else
            note,
      ];
      if (_libraryCollectionId == collection.id) _libraryCollectionId = null;
    });
  }

  Future<void> _createCollection(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    setState(() {
      _collections.add(
        NoteCollection(id: const Uuid().v4(), name: clean),
      );
    });
  }

  Future<void> _copyStableLink(String id) async {
    await Clipboard.setData(
      ClipboardData(text: StableLinks.object(id).toString()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Collegamento Notes copiato.')),
    );
  }

  Future<void> _openEditor([Note? note]) async {
    final result = await Navigator.of(context).push<Note>(
      MaterialPageRoute(
        builder: (_) => _WebEditorScreen(
          note: note,
          collections: _collections,
        ),
      ),
    );
    if (result != null) await _save(result);
  }

  Future<void> _openNote(Note note) async {
    if (note.isTask) {
      setState(() {
        _plannerTaskId = note.id;
        _index = 3;
      });
      return;
    }
    if (note.isVisual) {
      await _openVisual(note);
      return;
    }
    await _openEditor(note);
  }

  Future<void> _openVisual(Note note) async {
    if (note.visualKind == VisualDocumentKind.whiteboard) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WhiteboardScreen(
            note: note,
            onSave: _save,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SketchScreen(
          note: note,
          onSave: _save,
        ),
      ),
    );
  }

  Future<void> _createSketch() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final note = Note(
      id: const Uuid().v4(),
      title: 'Nuovo disegno',
      body: SketchCodec.encode(SketchDocument()),
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      tags: const ['visual'],
      sketchJson: const VisualInfo(kind: VisualInfoKind.sketch).encode(),
    );
    await _save(note);
    await _openVisual(note);
  }

  Future<void> _createWhiteboard({required bool mindMap}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final document = WhiteboardOps.empty(
      mindMap ? WhiteboardMode.mindMap : WhiteboardMode.freeform,
    );
    final note = Note(
      id: const Uuid().v4(),
      title: mindMap ? 'Nuova mind map' : 'Nuova lavagna',
      body: WhiteboardCodec.encode(document),
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      tags: const ['visual'],
      sketchJson: const VisualInfo(kind: VisualInfoKind.whiteboard).encode(),
    );
    await _save(note);
    await _openVisual(note);
  }

  Future<void> _createDiary(DateTime date, String? collectionId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _openEditor(
      Note(
        id: const Uuid().v4(),
        title: 'Diario · ${dateKey(date)}',
        body: '',
        collectionId: collectionId,
        favorite: false,
        createdAt: now,
        updatedAt: now,
        pinned: false,
        archived: false,
        tags: Diary.datedTags(const [], date),
      ),
    );
  }

  Future<void> _openTemplates() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplatesScreen(
          notes: _notes,
          onUse: (template) {
            Navigator.pop(context);
            final now = DateTime.now().millisecondsSinceEpoch;
            unawaited(
              _openEditor(
                Note(
                  id: const Uuid().v4(),
                  title: template.title,
                  body: template.body,
                  favorite: false,
                  createdAt: now,
                  updatedAt: now,
                  pinned: false,
                  archived: false,
                  tags: template.tags,
                ),
              ),
            );
          },
          onEdit: (note) {
            Navigator.pop(context);
            unawaited(_openEditor(note));
          },
        ),
      ),
    );
  }

  Future<void> _createMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Crea'),
              subtitle: Text(
                'Gli stessi oggetti canonici disponibili nell’app Android.',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('Nota'),
              onTap: () => Navigator.pop(context, 'note'),
            ),
            ListTile(
              leading: const Icon(Icons.check_box_outlined),
              title: const Text('Checklist'),
              onTap: () => Navigator.pop(context, 'checklist'),
            ),
            ListTile(
              leading: const Icon(Icons.task_alt_outlined),
              title: const Text('Attività'),
              onTap: () => Navigator.pop(context, 'task'),
            ),
            ListTile(
              leading: const Icon(Icons.draw_outlined),
              title: const Text('Sketch'),
              onTap: () => Navigator.pop(context, 'sketch'),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_customize_outlined),
              title: const Text('Lavagna'),
              onTap: () => Navigator.pop(context, 'whiteboard'),
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('Mind map'),
              onTap: () => Navigator.pop(context, 'mindmap'),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_mosaic_outlined),
              title: const Text('Da modello'),
              onTap: () => Navigator.pop(context, 'template'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'note':
        await _openEditor();
        break;
      case 'checklist':
        final now = DateTime.now().millisecondsSinceEpoch;
        await _openEditor(
          Note(
            id: const Uuid().v4(),
            title: 'Nuova checklist',
            body: '- [ ] ',
            favorite: false,
            createdAt: now,
            updatedAt: now,
            pinned: false,
            archived: false,
            tags: const [],
          ),
        );
        break;
      case 'task':
        _selectSection(3);
        break;
      case 'sketch':
        await _createSketch();
        break;
      case 'whiteboard':
        await _createWhiteboard(mindMap: false);
        break;
      case 'mindmap':
        await _createWhiteboard(mindMap: true);
        break;
      case 'template':
        await _openTemplates();
        break;
    }
  }

  Future<void> _openStudy() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _WebStudyScreen(
          notes: _personalNotes,
          onOpenSource: _openNote,
        ),
      ),
    );
  }

  Future<void> _openProjects() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _WebProjectsScreen(
          notes: _personalNotes,
          onOpen: _openNote,
        ),
      ),
    );
  }

  Future<void> _openKnowledgeSearch() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.88,
        child: _WebKnowledgeSearch(
          notes: _personalNotes,
          onOpen: (note) {
            Navigator.pop(context);
            unawaited(_openNote(note));
          },
        ),
      ),
    );
  }

  Future<void> _quickSwitcher() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _WebQuickSwitcher(
        notes: _personalNotes,
        onSelectSection: (index) {
          Navigator.pop(context);
          _selectSection(index);
        },
        onOpen: (note) {
          Navigator.pop(context);
          unawaited(_openNote(note));
        },
        onProjects: () {
          Navigator.pop(context);
          unawaited(_openProjects());
        },
        onStudy: () {
          Navigator.pop(context);
          unawaited(_openStudy());
        },
      ),
    );
  }

  Future<void> _settings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Notes Ecosistema 0.51'),
              subtitle: Text(
                'Web Preview fedele · stato demo locale alla sessione browser.',
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Tema scuro'),
              value: widget.dark,
              onChanged: widget.onDarkChanged,
            ),
            const ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text('Local-first e private-by-default'),
              subtitle: Text(
                'La preview non usa il database Android: simula lo stato in memoria.',
              ),
            ),
            const ListTile(
              leading: Icon(Icons.file_download_outlined),
              title: Text('Import / Export / Disaster Recovery'),
              subtitle: Text(
                'Flussi presenti nella release Android. Nel browser restano in modalità dimostrativa.',
              ),
            ),
            const ListTile(
              leading: Icon(Icons.sync_outlined),
              title: Text('GitHub Sync e integrazioni native'),
              subtitle: Text(
                'Richiedono l’APK o il relativo provider nativo; la UI Web non finge una connessione reale.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final personalNotes = _personalNotes;
    final section = _labels[_index];
    final body = switch (_index) {
      0 => HomeScreen(
          notes: personalNotes,
          collections: _collections,
          onCreate: _createMenu,
          onNotes: () => _selectSection(1),
          onAgenda: () => _selectSection(3),
          onTasks: () => _selectSection(3),
          onSketch: _createSketch,
          onCollection: (id) => setState(() {
            _libraryCollectionId = id;
            _index = 1;
          }),
          onOpenNote: _openNote,
          onProjects: _openProjects,
          onStudy: _openStudy,
          projectCount: 3,
          sharedUnread: 2,
        ),
      1 => NotesScreen(
          notes: _notes,
          collections: _collections,
          query: _query,
          searchMode: false,
          onQueryChanged: (value) => setState(() => _query = value),
          onOpen: _openNote,
          onFavorite: _favorite,
          onPin: _pin,
          onArchive: _archive,
          onTrash: _trash,
          onRestore: _restore,
          onDeleteForever: _deleteForever,
          onCopyLink: _copyStableLink,
          onBulkEdit: _bulkEdit,
          onRenameCollection: _renameCollection,
          onDeleteCollection: _deleteCollection,
          initialCollectionId: _libraryCollectionId,
        ),
      2 => DiaryScreen(
          notes: personalNotes,
          collections: _collections,
          onOpen: _openNote,
          onCreate: _createDiary,
          onOpenTask: (note) => setState(() {
            _plannerTaskId = note.id;
            _index = 3;
          }),
          onCreateCollection: _createCollection,
        ),
      3 => PlannerScreen(
          notes: _notes,
          onSave: _save,
          onTrash: (id) async => _trash(id),
          onOpenNote: _openNote,
          initialTaskId: _plannerTaskId,
        ),
      4 => _WebSpacesScreen(
          notes: personalNotes,
          onProjects: _openProjects,
          onOpen: _openNote,
        ),
      _ => NotesScreen(
          notes: _notes,
          collections: _collections,
          query: _query,
          searchMode: true,
          onQueryChanged: (value) => setState(() => _query = value),
          onOpen: _openNote,
          onFavorite: _favorite,
          onPin: _pin,
          onArchive: _archive,
          onTrash: _trash,
          onRestore: _restore,
          onDeleteForever: _deleteForever,
          onCopyLink: _copyStableLink,
          onBulkEdit: _bulkEdit,
          onRenameCollection: _renameCollection,
          onDeleteCollection: _deleteCollection,
        ),
    };

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _quickSwitcher,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _createMenu,
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
          shift: true,
        ): () => _selectSection(5),
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            return Scaffold(
              appBar: AppBar(
                title: EditorialAppTitle(
                  section == 'Home' ? 'Il tuo spazio' : section,
                  eyebrow: 'NOTES · WEB PREVIEW 0.51',
                ),
                actions: [
                  IconButton(
                    tooltip: 'Knowledge Search',
                    onPressed: _openKnowledgeSearch,
                    icon: const Icon(Icons.auto_awesome_outlined),
                  ),
                  IconButton(
                    tooltip: 'Quick Switcher · Ctrl+K',
                    onPressed: _quickSwitcher,
                    icon: const Icon(Icons.bolt_outlined),
                  ),
                  IconButton(
                    tooltip: 'Impostazioni',
                    onPressed: _settings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              body: wide
                  ? Row(
                      children: [
                        NavigationRail(
                          selectedIndex: _index,
                          onDestinationSelected: _selectSection,
                          labelType: NavigationRailLabelType.selected,
                          destinations: const [
                            NavigationRailDestination(
                              icon: Icon(Icons.home_outlined),
                              selectedIcon: Icon(Icons.home),
                              label: Text('Home'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.description_outlined),
                              selectedIcon: Icon(Icons.description),
                              label: Text('Note'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.calendar_month_outlined),
                              selectedIcon: Icon(Icons.calendar_month),
                              label: Text('Diario'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.check_circle_outline),
                              selectedIcon: Icon(Icons.check_circle),
                              label: Text('Attività'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.group_work_outlined),
                              selectedIcon: Icon(Icons.group_work),
                              label: Text('Spazi'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.search),
                              label: Text('Cerca'),
                            ),
                          ],
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: body),
                      ],
                    )
                  : body,
              floatingActionButton: (_index == 4 || _index == 5 || _index == 2)
                  ? null
                  : FloatingActionButton.extended(
                      onPressed: _createMenu,
                      icon: const Icon(Icons.add),
                      label: const Text('Crea'),
                    ),
              bottomNavigationBar: wide
                  ? null
                  : NavigationBar(
                      selectedIndex: _index,
                      onDestinationSelected: _selectSection,
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home),
                          label: 'Home',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.description_outlined),
                          selectedIcon: Icon(Icons.description),
                          label: 'Note',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.calendar_month_outlined),
                          selectedIcon: Icon(Icons.calendar_month),
                          label: 'Diario',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.check_circle_outline),
                          selectedIcon: Icon(Icons.check_circle),
                          label: 'Attività',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.group_work_outlined),
                          selectedIcon: Icon(Icons.group_work),
                          label: 'Spazi',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.search),
                          label: 'Cerca',
                        ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  static List<Note> _seedNotes() {
    final now = DateTime.now();
    final millis = now.millisecondsSinceEpoch;
    final today = dateKey(now);
    final tomorrow = dateKey(now.add(const Duration(days: 1)));
    final yesterday = now.subtract(const Duration(days: 1));

    TaskDetails task({
      required String due,
      required int priority,
      required String time,
      required int minutes,
    }) {
      return TaskDetails.empty().withEditorValues(
        due: due,
        priority: priority,
        repeat: 'NONE',
        linkedNoteId: null,
        plannedDate: due,
        plannedTime: time,
        plannedMinutes: minutes,
      );
    }

    var mindMap = WhiteboardOps.empty(WhiteboardMode.mindMap);
    final root = mindMap.nodes.first.id;
    mindMap = WhiteboardOps.addMindChild(
      mindMap,
      root,
      text: 'Ricerca unificata',
    );
    mindMap = WhiteboardOps.addMindChild(
      mindMap,
      root,
      text: 'Document Workspace',
    );
    mindMap = WhiteboardOps.addMindChild(
      mindMap,
      root,
      text: 'Study Core',
    );
    mindMap = WhiteboardOps.autoLayoutMindMap(mindMap);

    return [
      Note(
        id: 'strategy',
        title: 'Product strategy · Notes',
        body:
            '# Obiettivo\n\nRendere Notes il centro di lavoro e conoscenza.\n\n'
            '## Prossimi passi\n- [ ] Validare flussi Web\n- [ ] Rifinire collaborazione\n'
            '- [x] Unified Retrieval\n\n> Local-first, private-by-default.',
        collectionId: 'work',
        favorite: true,
        createdAt: millis - 86400000 * 9,
        updatedAt: millis - 120000,
        pinned: true,
        archived: false,
        tags: const ['prodotto', 'roadmap', 'knowledge'],
      ),
      Note(
        id: 'retrieval',
        title: 'Unified Retrieval',
        body:
            'FTS, metadata, relazioni, OCR, Study e annotazioni PDF convergono '
            'in un unico livello di retrieval deterministico.\n\n'
            'Il ranking privilegia titolo, tag, contenuto e recenza.',
        collectionId: 'work',
        favorite: false,
        createdAt: millis - 86400000 * 5,
        updatedAt: millis - 3600000,
        pinned: false,
        archived: false,
        tags: const ['search', 'architecture'],
      ),
      Note(
        id: 'study-note',
        title: 'Economia internazionale · ripasso',
        body: '## Vantaggio comparato\n\nIl costo opportunità determina la '
            'specializzazione relativa.\n\n## Domande\n- Perché il commercio '
            'può aumentare il benessere?\n- Quali sono i limiti del modello?',
        collectionId: 'study',
        favorite: true,
        createdAt: millis - 86400000 * 14,
        updatedAt: millis - 7200000,
        pinned: false,
        archived: false,
        tags: const ['studio', 'economia'],
      ),
      Note(
        id: 'diary-today',
        title: 'Decisioni di oggi',
        body: 'Ho chiuso il ciclo 0.47 → 0.51. La preview Web deve essere '
            'una rappresentazione credibile del prodotto, non una demo separata.',
        collectionId: 'ideas',
        favorite: false,
        createdAt: millis - 5400000,
        updatedAt: millis - 1800000,
        pinned: false,
        archived: false,
        tags: Diary.datedTags(const ['decisioni'], now),
      ),
      Note(
        id: 'diary-yesterday',
        title: 'Retrospettiva',
        body: 'La lavagna e la mind map devono sempre aprirsi centrate sul '
            'punto logico in cui nascono le nuove idee.',
        collectionId: 'ideas',
        favorite: false,
        createdAt: millis - 86400000,
        updatedAt: millis - 86400000,
        pinned: false,
        archived: false,
        tags: Diary.datedTags(const ['retro'], yesterday),
      ),
      Note(
        id: 'task-design',
        title: 'Rifinire Product & UX Polish',
        body:
            'Verificare gerarchia, navigazione responsive e desktop shortcuts.',
        collectionId: 'work',
        favorite: false,
        createdAt: millis - 7200000,
        updatedAt: millis - 1800000,
        pinned: false,
        archived: false,
        tags: const ['ux'],
        taskJson: task(
          due: today,
          priority: 3,
          time: '14:30',
          minutes: 60,
        ).encode(),
      ),
      Note(
        id: 'task-study',
        title: 'Ripasso Study Core',
        body: 'Rivedere LearningItem e source snapshot.',
        collectionId: 'study',
        favorite: false,
        createdAt: millis - 3600000,
        updatedAt: millis - 1200000,
        pinned: false,
        archived: false,
        tags: const ['studio'],
        taskJson: task(
          due: tomorrow,
          priority: 2,
          time: '10:00',
          minutes: 45,
        ).encode(),
      ),
      Note(
        id: 'mindmap',
        title: 'Architettura Notes',
        body: WhiteboardCodec.encode(mindMap),
        collectionId: 'ideas',
        favorite: true,
        createdAt: millis - 86400000 * 3,
        updatedAt: millis - 2400000,
        pinned: false,
        archived: false,
        tags: const ['visual', 'architecture'],
        sketchJson: const VisualInfo(kind: VisualInfoKind.whiteboard).encode(),
      ),
      Note(
        id: 'sketch',
        title: 'Wireframe Home',
        body: SketchCodec.encode(SketchDocument()),
        collectionId: 'ideas',
        favorite: false,
        createdAt: millis - 86400000 * 2,
        updatedAt: millis - 6000000,
        pinned: false,
        archived: false,
        tags: const ['visual', 'wireframe'],
        sketchJson: const VisualInfo(kind: VisualInfoKind.sketch).encode(),
      ),
      Note(
        id: 'template-weekly',
        title: 'Review personale',
        body:
            '# Settimana {{data}}\n\n## Completato\n\n## Da riprendere\n- [ ] '
            '\n\n## Priorità prossima settimana',
        collectionId: 'work',
        favorite: false,
        createdAt: millis - 86400000 * 20,
        updatedAt: millis - 86400000 * 6,
        pinned: false,
        archived: false,
        tags: const ['modello', 'review'],
      ),
      Note(
        id: 'archive-example',
        title: 'Spec precedente',
        body: 'Documento archiviato mantenuto per consultazione.',
        collectionId: 'work',
        favorite: false,
        createdAt: millis - 86400000 * 40,
        updatedAt: millis - 86400000 * 30,
        pinned: false,
        archived: true,
        tags: const ['archive'],
      ),
      Note(
        id: 'trash-example',
        title: 'Bozza eliminata',
        body: 'Esempio nel cestino universale.',
        favorite: false,
        createdAt: millis - 86400000 * 4,
        updatedAt: millis - 86400000 * 4,
        deletedAt: millis - 86400000,
        pinned: false,
        archived: false,
        tags: const ['bozza'],
      ),
    ];
  }
}

class _WebEditorScreen extends StatefulWidget {
  const _WebEditorScreen({
    required this.note,
    required this.collections,
  });

  final Note? note;
  final List<NoteCollection> collections;

  @override
  State<_WebEditorScreen> createState() => _WebEditorScreenState();
}

enum _WebEditorMode { text, preview, checklist }

class _WebEditorScreenState extends State<_WebEditorScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.note?.title ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.note?.body ?? '');
  late final TextEditingController _tags =
      TextEditingController(text: (widget.note?.tags ?? const []).join(', '));
  late String? _collectionId = widget.note?.collectionId;
  _WebEditorMode _mode = _WebEditorMode.text;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _save() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final original = widget.note;
    Navigator.pop(
      context,
      Note(
        id: original?.id ?? const Uuid().v4(),
        title: _title.text.trim(),
        body: _body.text,
        collectionId: _collectionId,
        favorite: original?.favorite ?? false,
        createdAt: original?.createdAt ?? now,
        updatedAt: now,
        deletedAt: original?.deletedAt,
        pinned: original?.pinned ?? false,
        archived: original?.archived ?? false,
        tags: NoteTags.normalize(
          _tags.text
              .split(',')
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty),
        ),
        taskJson: original?.taskJson,
        sketchJson: original?.sketchJson,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checklist = Checklist.parse(_body.text);
    return Scaffold(
      appBar: AppBar(
        title: const EditorialAppTitle('Editor',
            eyebrow: 'UNIVERSAL BLOCK EDITOR'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salva'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          final editor = ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                controller: _title,
                style: Theme.of(context).textTheme.headlineMedium,
                decoration: const InputDecoration(
                  hintText: 'Titolo',
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SegmentedButton<_WebEditorMode>(
                    segments: const [
                      ButtonSegment(
                        value: _WebEditorMode.text,
                        icon: Icon(Icons.edit_note),
                        label: Text('Testo'),
                      ),
                      ButtonSegment(
                        value: _WebEditorMode.preview,
                        icon: Icon(Icons.visibility_outlined),
                        label: Text('Preview'),
                      ),
                      ButtonSegment(
                        value: _WebEditorMode.checklist,
                        icon: Icon(Icons.checklist),
                        label: Text('Checklist'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (values) =>
                        setState(() => _mode = values.first),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_mode == _WebEditorMode.text)
                TextField(
                  controller: _body,
                  minLines: 18,
                  maxLines: null,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Scrivi in Markdown…',
                    alignLabelWithHint: true,
                  ),
                )
              else if (_mode == _WebEditorMode.preview)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: MarkdownBody(
                      data: _body.text.trim().isEmpty
                          ? '_Nessun contenuto_'
                          : _body.text,
                      selectable: true,
                    ),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: checklist.isEmpty
                        ? const Text(
                            'Nessuna checklist. Usa la sintassi “- [ ] attività”.',
                          )
                        : Column(
                            children: [
                              for (final item in checklist)
                                CheckboxListTile(
                                  value: item.completed,
                                  onChanged: null,
                                  title: Text(item.label),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                ),
                            ],
                          ),
                  ),
                ),
            ],
          );

          final inspector = ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const EditorialSection(
                'Proprietà',
                detail: 'Metadata e organizzazione della pagina.',
              ),
              DropdownButtonFormField<String?>(
                initialValue: _collectionId,
                decoration: const InputDecoration(labelText: 'Raccolta'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Inbox'),
                  ),
                  ...widget.collections.map(
                    (collection) => DropdownMenuItem<String?>(
                      value: collection.id,
                      child: Text(collection.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _collectionId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tags,
                decoration: const InputDecoration(
                  labelText: 'Tag',
                  hintText: 'lavoro, ricerca, idea',
                ),
              ),
              const SizedBox(height: 20),
              const _CapabilityTile(
                icon: Icons.view_agenda_outlined,
                title: 'Blocchi',
                detail: 'Il motore a blocchi resta il modello canonico.',
              ),
              const _CapabilityTile(
                icon: Icons.article_outlined,
                title: 'Document Workspace',
                detail: 'PDF, annotazioni e OCR sono integrati nella release.',
              ),
              const _CapabilityTile(
                icon: Icons.hub_outlined,
                title: 'Knowledge',
                detail:
                    'Relazioni, fonti e retrieval condividono la stessa nota.',
              ),
            ],
          );

          return wide
              ? Row(
                  children: [
                    Expanded(flex: 3, child: editor),
                    const VerticalDivider(width: 1),
                    SizedBox(width: 340, child: inspector),
                  ],
                )
              : editor;
        },
      ),
    );
  }
}

class _WebSpacesScreen extends StatelessWidget {
  const _WebSpacesScreen({
    required this.notes,
    required this.onProjects,
    required this.onOpen,
  });

  final List<Note> notes;
  final VoidCallback onProjects;
  final ValueChanged<Note> onOpen;

  @override
  Widget build(BuildContext context) {
    final recent = notes.where((note) => !note.isTask).take(3).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
      children: [
        const EditorialEyebrow('COLLABORATIVE WORKSPACE'),
        const SizedBox(height: 6),
        Text(
          'Spazi, progetti e contenuti condivisi.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'La Web Preview mostra il modello di lavoro; sincronizzazione live e '
          'membership reale richiedono la configurazione del provider.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _FeaturePanel(
          icon: Icons.work_outline,
          title: 'Project Workspace',
          subtitle:
              '3 progetti attivi · Lista · Board · Tabella · Calendario · Timeline',
          onTap: onProjects,
        ),
        const SizedBox(height: 12),
        _FeaturePanel(
          icon: Icons.group_work_outlined,
          title: 'Shared Space · Product',
          subtitle:
              '4 membri · 2 novità · note e task restano oggetti canonici',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _WebSharedSpaceDetail(
                title: 'Product',
                notes: recent,
                onOpen: onOpen,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _FeaturePanel(
          icon: Icons.school_outlined,
          title: 'Shared Space · Studio',
          subtitle: '2 membri · materiali, attività e fonti condivise',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _WebSharedSpaceDetail(
                title: 'Studio',
                notes: notes
                    .where((note) => note.tags.contains('studio'))
                    .toList(),
                onOpen: onOpen,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const EditorialSection(
          'Regole di ownership',
          detail: 'Collaborazione senza duplicare la source of truth.',
        ),
        const _CapabilityTile(
          icon: Icons.link,
          title: 'Link, non copie',
          detail: 'I progetti proiettano Note e Task canonici.',
        ),
        const _CapabilityTile(
          icon: Icons.security_outlined,
          title: 'Lifecycle esplicito',
          detail:
              'Rimuovi dallo spazio, lascia lo spazio o elimina con semantica distinta.',
        ),
      ],
    );
  }
}

class _WebSharedSpaceDetail extends StatelessWidget {
  const _WebSharedSpaceDetail({
    required this.title,
    required this.notes,
    required this.onOpen,
  });

  final String title;
  final List<Note> notes;
  final ValueChanged<Note> onOpen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Shared Space · $title')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const EditorialEyebrow('ATTIVITÀ RECENTE'),
          const SizedBox(height: 8),
          const _ActivityRow(
            icon: Icons.edit_note,
            title: 'Marta ha aggiornato una nota',
            detail: '12 min fa',
          ),
          const _ActivityRow(
            icon: Icons.task_alt,
            title: 'Luca ha completato un’attività',
            detail: '38 min fa',
          ),
          const SizedBox(height: 18),
          const EditorialSection('Contenuti'),
          for (final note in notes)
            Card(
              child: ListTile(
                leading: Icon(note.isTask ? Icons.task_alt : Icons.description),
                title: Text(note.title),
                subtitle: Text(
                  note.body.replaceAll('\n', ' '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onOpen(note),
              ),
            ),
        ],
      ),
    );
  }
}

class _WebProjectsScreen extends StatefulWidget {
  const _WebProjectsScreen({
    required this.notes,
    required this.onOpen,
  });

  final List<Note> notes;
  final ValueChanged<Note> onOpen;

  @override
  State<_WebProjectsScreen> createState() => _WebProjectsScreenState();
}

class _WebProjectsScreenState extends State<_WebProjectsScreen> {
  String _view = 'Board';

  @override
  Widget build(BuildContext context) {
    final tasks = widget.notes.where((note) => note.isTask).toList();
    final pages =
        widget.notes.where((note) => !note.isTask && !note.isVisual).toList();
    return Scaffold(
      appBar: AppBar(
        title: const EditorialAppTitle(
          'Progetti',
          eyebrow: 'PROJECT WORKSPACE',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
        children: [
          Text(
            'Notes Ecosistema 0.51',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Uno stesso lavoro, più viste. Nessuna duplicazione dei contenuti.',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in const [
                'Lista',
                'Board',
                'Tabella',
                'Calendario',
                'Timeline',
              ])
                ChoiceChip(
                  label: Text(value),
                  selected: _view == value,
                  onSelected: (_) => setState(() => _view = value),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _ProjectPreview(
            view: _view,
            tasks: tasks,
            pages: pages,
            onOpen: widget.onOpen,
          ),
        ],
      ),
    );
  }
}

class _ProjectPreview extends StatelessWidget {
  const _ProjectPreview({
    required this.view,
    required this.tasks,
    required this.pages,
    required this.onOpen,
  });

  final String view;
  final List<Note> tasks;
  final List<Note> pages;
  final ValueChanged<Note> onOpen;

  @override
  Widget build(BuildContext context) {
    if (view == 'Board') {
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = [
            ('TODO', tasks),
            ('PAGINE', pages.take(3).toList()),
            ('DONE', <Note>[]),
          ];
          if (constraints.maxWidth < 760) {
            return Column(
              children: [
                for (final column in columns) ...[
                  _BoardColumn(
                    title: column.$1,
                    notes: column.$2,
                    onOpen: onOpen,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final column in columns)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _BoardColumn(
                      title: column.$1,
                      notes: column.$2,
                      onOpen: onOpen,
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              switch (view) {
                'Lista' => Icons.view_list,
                'Tabella' => Icons.table_chart_outlined,
                'Calendario' => Icons.calendar_month_outlined,
                _ => Icons.timeline,
              },
            ),
            title: Text('Vista $view'),
            subtitle: const Text(
              'La stessa base di Note e Task viene proiettata senza creare copie.',
            ),
          ),
          const Divider(height: 1),
          for (final note in [...tasks, ...pages].take(7))
            ListTile(
              title: Text(note.title),
              subtitle: Text(note.isTask ? 'Attività' : 'Pagina'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpen(note),
            ),
        ],
      ),
    );
  }
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.title,
    required this.notes,
    required this.onOpen,
  });

  final String title;
  final List<Note> notes;
  final ValueChanged<Note> onOpen;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EditorialEyebrow(title),
            const SizedBox(height: 10),
            if (notes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Nessun elemento'),
              )
            else
              for (final note in notes)
                Card(
                  child: ListTile(
                    dense: true,
                    title: Text(note.title),
                    subtitle: Text(note.isTask ? 'Task' : 'Pagina'),
                    onTap: () => onOpen(note),
                  ),
                ),
          ],
        ),
      );
}

class _WebStudyScreen extends StatefulWidget {
  const _WebStudyScreen({
    required this.notes,
    required this.onOpenSource,
  });

  final List<Note> notes;
  final ValueChanged<Note> onOpenSource;

  @override
  State<_WebStudyScreen> createState() => _WebStudyScreenState();
}

class _WebStudyScreenState extends State<_WebStudyScreen> {
  final Set<String> _revealed = {};

  @override
  Widget build(BuildContext context) {
    final sources = widget.notes
        .where((note) => !note.isTask && !note.isVisual)
        .take(4)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Study')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
        children: [
          const EditorialEyebrow('STUDY CORE'),
          const SizedBox(height: 4),
          Text(
            'Ripassa ciò che hai già studiato.',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'LearningItem source-linked con snapshot storico e review log.',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MetricPreview(
                  value: sources.length,
                  label: 'Da ripassare oggi',
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: _MetricPreview(
                  value: 12,
                  label: 'Elementi totali',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final source in sources)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _revealed.contains(source.id)
                          ? source.body
                          : 'Domanda: qual è il concetto chiave di questa nota?',
                      maxLines: _revealed.contains(source.id) ? 8 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => setState(() {
                            if (!_revealed.add(source.id)) {
                              _revealed.remove(source.id);
                            }
                          }),
                          child: Text(
                            _revealed.contains(source.id)
                                ? 'Nascondi risposta'
                                : 'Mostra risposta',
                          ),
                        ),
                        TextButton(
                          onPressed: () => widget.onOpenSource(source),
                          child: const Text('Apri sorgente'),
                        ),
                        if (_revealed.contains(source.id))
                          for (final label in const [
                            'Difficile',
                            'Buono',
                            'Facile',
                          ])
                            ActionChip(
                              label: Text(label),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Review “$label” registrata nella preview.',
                                    ),
                                  ),
                                );
                              },
                            ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WebKnowledgeSearch extends StatefulWidget {
  const _WebKnowledgeSearch({
    required this.notes,
    required this.onOpen,
  });

  final List<Note> notes;
  final ValueChanged<Note> onOpen;

  @override
  State<_WebKnowledgeSearch> createState() => _WebKnowledgeSearchState();
}

class _WebKnowledgeSearchState extends State<_WebKnowledgeSearch> {
  final TextEditingController _query = TextEditingController(text: 'retrieval');

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<RetrievalHit> get _hits {
    final documents = <RetrievalDocument>[
      ...UnifiedRetrieval.noteDocuments(widget.notes),
      const RetrievalDocument(
        id: 'ocr:strategy',
        noteId: 'strategy',
        kind: RetrievalKind.ocr,
        title: 'Product strategy · Notes',
        text: 'OCR: schema architetturale, roadmap e knowledge workspace.',
      ),
      const RetrievalDocument(
        id: 'study:study-note',
        noteId: 'study-note',
        kind: RetrievalKind.study,
        title: 'Vantaggio comparato',
        text: 'LearningItem: costo opportunità e specializzazione relativa.',
      ),
      const RetrievalDocument(
        id: 'pdf:retrieval',
        noteId: 'retrieval',
        kind: RetrievalKind.pdfAnnotation,
        title: 'Unified Retrieval',
        text: 'Annotazione PDF: ranking deterministico prima degli embeddings.',
      ),
      const RetrievalDocument(
        id: 'metadata:strategy',
        noteId: 'strategy',
        kind: RetrievalKind.metadata,
        title: 'Product strategy · Notes',
        text: 'Stato: attivo · Area: prodotto · Priorità: alta',
      ),
      const RetrievalDocument(
        id: 'relation:strategy',
        noteId: 'strategy',
        kind: RetrievalKind.relation,
        title: 'Product strategy · Notes',
        text: 'Relazione: collegato a Unified Retrieval e Study Core.',
      ),
    ];
    return UnifiedRetrieval.search(_query.text, documents, limit: 20);
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final note in widget.notes) note.id: note};
    final hits = _hits;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EditorialEyebrow('UNIFIED RETRIEVAL'),
          const SizedBox(height: 4),
          Text(
            'Knowledge Search',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _query,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText:
                  'Cerca in note, OCR, Study, PDF, proprietà e relazioni…',
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: hits.isEmpty
                ? const Center(child: Text('Nessun risultato'))
                : ListView.separated(
                    itemCount: hits.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final hit = hits[index];
                      final note = byId[hit.document.noteId];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(_retrievalIcon(hit.document.kind)),
                        ),
                        title: Text(note?.title ?? hit.document.title),
                        subtitle: Text(
                          '${_retrievalLabel(hit.document.kind)} · ${hit.excerpt}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(hit.score.toStringAsFixed(0)),
                        onTap: note == null ? null : () => widget.onOpen(note),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WebQuickSwitcher extends StatefulWidget {
  const _WebQuickSwitcher({
    required this.notes,
    required this.onSelectSection,
    required this.onOpen,
    required this.onProjects,
    required this.onStudy,
  });

  final List<Note> notes;
  final ValueChanged<int> onSelectSection;
  final ValueChanged<Note> onOpen;
  final VoidCallback onProjects;
  final VoidCallback onStudy;

  @override
  State<_WebQuickSwitcher> createState() => _WebQuickSwitcherState();
}

class _WebQuickSwitcherState extends State<_WebQuickSwitcher> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = UnifiedRetrieval.normalize(_query.text);
    final notes = widget.notes
        .where((note) {
          if (query.isEmpty) return true;
          return UnifiedRetrieval.scoreText(
                query: query,
                title: note.title,
                text: note.isVisual ? '' : note.body,
                tags: note.tags,
              ) >
              0;
        })
        .take(8)
        .toList();

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      title: const Text('Quick Switcher'),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.bolt),
                hintText: 'Vai a una pagina o esegui un comando…',
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  if (query.isEmpty) ...[
                    ListTile(
                      leading: const Icon(Icons.search),
                      title: const Text('Cerca ovunque'),
                      onTap: () => widget.onSelectSection(5),
                    ),
                    ListTile(
                      leading: const Icon(Icons.work_outline),
                      title: const Text('Apri Project Workspace'),
                      onTap: widget.onProjects,
                    ),
                    ListTile(
                      leading: const Icon(Icons.school_outlined),
                      title: const Text('Apri Study'),
                      onTap: widget.onStudy,
                    ),
                    const Divider(),
                  ],
                  for (final note in notes)
                    ListTile(
                      leading: Icon(
                        note.isTask
                            ? Icons.task_alt
                            : note.isVisual
                                ? Icons.draw_outlined
                                : Icons.description_outlined,
                      ),
                      title: Text(note.title),
                      subtitle: Text(
                        note.tags.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => widget.onOpen(note),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeaturePanel extends StatelessWidget {
  const _FeaturePanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  child: Icon(icon),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle),
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

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        subtitle: Text(detail),
      );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(title),
        subtitle: Text(detail),
      );
}

class _MetricPreview extends StatelessWidget {
  const _MetricPreview({
    required this.value,
    required this.label,
  });

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 4),
              Text(label),
            ],
          ),
        ),
      );
}

IconData _retrievalIcon(RetrievalKind kind) => switch (kind) {
      RetrievalKind.note => Icons.description_outlined,
      RetrievalKind.task => Icons.task_alt,
      RetrievalKind.ocr => Icons.document_scanner_outlined,
      RetrievalKind.derivative => Icons.auto_awesome_outlined,
      RetrievalKind.study => Icons.school_outlined,
      RetrievalKind.pdfAnnotation => Icons.picture_as_pdf_outlined,
      RetrievalKind.research => Icons.source_outlined,
      RetrievalKind.metadata => Icons.tune,
      RetrievalKind.relation => Icons.hub_outlined,
    };

String _retrievalLabel(RetrievalKind kind) => switch (kind) {
      RetrievalKind.note => 'Nota',
      RetrievalKind.task => 'Attività',
      RetrievalKind.ocr => 'OCR',
      RetrievalKind.derivative => 'Derivato',
      RetrievalKind.study => 'Study',
      RetrievalKind.pdfAnnotation => 'Annotazione PDF',
      RetrievalKind.research => 'Fonte',
      RetrievalKind.metadata => 'Proprietà',
      RetrievalKind.relation => 'Relazione',
    };
