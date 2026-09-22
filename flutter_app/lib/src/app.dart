import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'domain/note.dart';
import 'screens/editor_screen.dart';
import 'screens/home_screen.dart';
import 'screens/notes_screen.dart';
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
  const WorkspaceShell({required this.dark, required this.onDarkChanged, super.key});
  final bool dark;
  final ValueChanged<bool> onDarkChanged;

  @override
  ConsumerState<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends ConsumerState<WorkspaceShell> {
  int _index = 0;
  String _query = '';

  static const labels = ['Home', 'Note', 'Diario', 'Attività', 'Cerca'];

  Future<void> _openEditor([Note? note]) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorScreen(note: note)));
    await ref.read(workspaceProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceProvider);
    final section = labels[_index];

    Widget body;
    if (workspace.loading && workspace.notes.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (workspace.error != null && workspace.notes.isEmpty) {
      body = _ErrorState(onRetry: () => ref.read(workspaceProvider.notifier).refresh());
    } else if (_index == 0) {
      body = HomeScreen(
        notes: workspace.notes,
        collections: workspace.collections,
        onCreate: _openEditor,
        onNotes: () => setState(() => _index = 1),
        onAgenda: () => setState(() => _index = 3),
        onTasks: () => setState(() => _index = 3),
        onSketch: () => _showPending('Sketchbook'),
      );
    } else if (_index == 1 || _index == 4) {
      body = NotesScreen(
        notes: workspace.notes,
        collections: workspace.collections,
        query: _query,
        searchMode: _index == 4,
        onQueryChanged: (value) => setState(() => _query = value),
        onOpen: _openEditor,
        onFavorite: (id) => ref.read(workspaceProvider.notifier).favorite(id),
        onPin: (id, value) => ref.read(workspaceProvider.notifier).pin(id, value),
        onTrash: (id) => ref.read(workspaceProvider.notifier).trash(id),
      );
    } else if (_index == 2) {
      body = const _ParityPlaceholder(
        icon: Icons.calendar_month,
        title: 'Diario',
        message: 'Porting della timeline Diario e delle viste Oggi / Settimana / Mese in corso.',
      );
    } else {
      body = _TasksScreen(notes: workspace.notes);
    }

    return Scaffold(
      appBar: AppBar(
        title: EditorialAppTitle(section == 'Home' ? 'Il tuo spazio' : section),
        actions: [
          IconButton(tooltip: 'Impostazioni', onPressed: () => _settings(context), icon: const Icon(Icons.settings)),
        ],
      ),
      body: body,
      floatingActionButton: _index == 4
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
            ListTile(leading: const Icon(Icons.note_add), title: const Text('Nuova nota'), onTap: () => Navigator.pop(context, 'note')),
            ListTile(leading: const Icon(Icons.today), title: const Text('Diario di oggi'), onTap: () => Navigator.pop(context, 'diary')),
            ListTile(leading: const Icon(Icons.dashboard_customize), title: const Text('Modelli'), onTap: () => Navigator.pop(context, 'templates')),
            ListTile(leading: const Icon(Icons.draw), title: const Text('Nuovo disegno'), onTap: () => Navigator.pop(context, 'sketch')),
            ListTile(leading: const Icon(Icons.dashboard), title: const Text('Nuova lavagna'), onTap: () => Navigator.pop(context, 'board')),
            ListTile(leading: const Icon(Icons.account_tree), title: const Text('Nuova mind map'), onTap: () => Navigator.pop(context, 'mind')),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'note') {
      await _openEditor();
    } else {
      _showPending(action);
    }
  }

  void _showPending(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$feature: porting Flutter in corso.')));
  }

  Future<void> _settings(BuildContext context) => showModalBottomSheet<void>(
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
                SwitchListTile(title: const Text('Tema scuro'), value: widget.dark, onChanged: widget.onDarkChanged),
                const ListTile(
                  title: Text('Notes · Flutter port 0.25.0'),
                  subtitle: Text('Database locale compatibile con Notes Ecosistema Kotlin / Room v8.'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _TasksScreen extends StatelessWidget {
  const _TasksScreen({required this.notes});
  final List<Note> notes;

  @override
  Widget build(BuildContext context) {
    final tasks = notes.where((n) => n.isTask && !n.isDeleted && !n.taskCompleted).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
      children: [
        const EditorialSection('Un passo alla volta.', detail: 'Le attività pianificate e quelle da riprendere.'),
        if (tasks.isEmpty)
          const _ParityPlaceholder(icon: Icons.check_circle_outline, title: 'Nessuna attività', message: 'Le attività delle tue note appariranno qui.')
        else
          ...tasks.map((task) => Card(
                child: ListTile(
                  leading: const Icon(Icons.radio_button_unchecked),
                  title: Text(task.title.isEmpty ? 'Attività' : task.title),
                  subtitle: task.taskDue == null ? null : Text('Scadenza · ${task.taskDue}'),
                ),
              )),
      ],
    );
  }
}

class _ParityPlaceholder extends StatelessWidget {
  const _ParityPlaceholder({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.bodyLarge),
        ],
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
          Text('Database non disponibile.', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('Il port Flutter non ha modificato i dati. Riprova ad aprire il database locale.'),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Riprova')),
        ],
      );
}
