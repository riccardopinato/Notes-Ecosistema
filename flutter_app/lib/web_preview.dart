import 'package:flutter/material.dart';

import 'src/theme/notes_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesWebPreview());
}

class NotesWebPreview extends StatelessWidget {
  const NotesWebPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Notes Ecosistema Web Preview',
      theme: NotesTheme.light(),
      darkTheme: NotesTheme.dark(),
      home: const _NotesPreviewShell(),
    );
  }
}

class _NotesPreviewShell extends StatefulWidget {
  const _NotesPreviewShell();

  @override
  State<_NotesPreviewShell> createState() => _NotesPreviewShellState();
}

class _NotesPreviewShellState extends State<_NotesPreviewShell> {
  int _index = 0;
  final _search = TextEditingController();
  final _notes = <_PreviewNote>[
    const _PreviewNote('Casa di Anna',
        'Lista cose da sistemare e idee per il weekend', 'Oggi'),
    const _PreviewNote(
        'TrailPath', 'Audit, web preview e release Android', 'Ieri'),
    const _PreviewNote('Tesi', 'Capitoli, fonti e checklist finale', 'Lun'),
    const _PreviewNote('Spesa', 'Verdure, pasta, caffè e crocchette', 'Dom'),
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final destinations = const [
      NavigationDestination(
          icon: Icon(Icons.note_alt_outlined),
          selectedIcon: Icon(Icons.note_alt_rounded),
          label: 'Note'),
      NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month_rounded),
          label: 'Planner'),
      NavigationDestination(
          icon: Icon(Icons.timer_outlined),
          selectedIcon: Icon(Icons.timer_rounded),
          label: 'Focus'),
      NavigationDestination(
          icon: Icon(Icons.draw_outlined),
          selectedIcon: Icon(Icons.draw_rounded),
          label: 'Sketch'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes · Web Preview'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: Chip(label: Text('Browser preview'))),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          _notesPage(context),
          const _PreviewInfo(
              icon: Icons.calendar_view_week_rounded,
              title: 'Planner Pro',
              subtitle:
                  'Anteprima web di Agenda, Giorno, Settimana e Mese. Le funzioni native di reminder restano da verificare sull’APK.'),
          const _PreviewInfo(
              icon: Icons.self_improvement_rounded,
              title: 'Focus / Pomodoro',
              subtitle:
                  'UI e flussi possono essere verificati online; notifiche e servizi in background restano Android-only.'),
          const _PreviewInfo(
              icon: Icons.brush_rounded,
              title: 'Sketchbook',
              subtitle:
                  'Anteprima del modulo visuale. Condivisione file e integrazioni native richiedono il test Android.'),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        destinations: destinations,
        onDestinationSelected: (value) => setState(() => _index = value),
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                setState(() {
                  _notes.insert(
                    0,
                    _PreviewNote('Nuova nota ${_notes.length + 1}',
                        'Creata nella preview web', 'Adesso'),
                  );
                });
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuova nota'),
            )
          : null,
    );
  }

  Widget _notesPage(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final visible = _notes.where((note) {
      if (query.isEmpty) return true;
      return note.title.toLowerCase().contains(query) ||
          note.body.toLowerCase().contains(query);
    }).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final max = constraints.maxWidth > 900 ? 860.0 : double.infinity;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: max),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
              children: [
                Text('Le tue note',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 6),
                Text(
                  'Ricerca dinamica e UI principale direttamente nel browser.',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Cerca nelle note…',
                  ),
                ),
                const SizedBox(height: 18),
                if (visible.isEmpty)
                  const _PreviewInfo(
                    icon: Icons.search_off_rounded,
                    title: 'Nessun risultato',
                    subtitle:
                        'Continua a modificare la ricerca per filtrare in tempo reale.',
                  )
                else
                  for (final note in visible) ...[
                    Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 10),
                        title: Text(note.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(note.body,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ),
                        trailing: Text(note.when),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PreviewNote {
  const _PreviewNote(this.title, this.body, this.when);
  final String title;
  final String body;
  final String when;
}

class _PreviewInfo extends StatelessWidget {
  const _PreviewInfo({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 54),
                  const SizedBox(height: 18),
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  Text(subtitle, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
