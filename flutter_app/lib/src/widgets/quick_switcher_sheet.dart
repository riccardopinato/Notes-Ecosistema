import 'package:flutter/material.dart';

import '../domain/note.dart';
import '../domain/quick_switcher.dart';
import '../domain/project_workspace.dart';

Future<QuickSwitcherEntry?> showQuickSwitcher({
  required BuildContext context,
  required List<Note> notes,
  required List<NoteCollection> collections,
  List<ProjectWorkspace> projects = const [],
}) =>
    showDialog<QuickSwitcherEntry>(
      context: context,
      builder: (_) => _QuickSwitcherDialog(
        notes: notes,
        collections: collections,
        projects: projects,
      ),
    );

class _QuickSwitcherDialog extends StatefulWidget {
  const _QuickSwitcherDialog({
    required this.notes,
    required this.collections,
    required this.projects,
  });

  final List<Note> notes;
  final List<NoteCollection> collections;
  final List<ProjectWorkspace> projects;

  @override
  State<_QuickSwitcherDialog> createState() => _QuickSwitcherDialogState();
}

class _QuickSwitcherDialogState extends State<_QuickSwitcherDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final results = QuickSwitcher.search(
      query: _query,
      notes: widget.notes,
      collections: widget.collections,
      projects: widget.projects,
    );
    return AlertDialog(
      title: const Text('Quick Switcher'),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Nota, attività, progetto, raccolta o comando…',
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: results.isEmpty
                  ? const Center(child: Text('Nessun risultato.'))
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final entry = results[index];
                        return ListTile(
                          leading: Icon(
                            switch (entry.kind) {
                              QuickSwitcherKind.note =>
                                Icons.description_outlined,
                              QuickSwitcherKind.task =>
                                Icons.check_circle_outline,
                              QuickSwitcherKind.collection =>
                                Icons.folder_outlined,
                              QuickSwitcherKind.project => Icons.work_outline,
                              QuickSwitcherKind.command => Icons.bolt_outlined,
                            },
                          ),
                          title: Text(entry.label),
                          subtitle: entry.subtitle == null
                              ? null
                              : Text(entry.subtitle!),
                          onTap: () => Navigator.pop(context, entry),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Chiudi'),
        ),
      ],
    );
  }
}
