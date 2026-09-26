import 'package:flutter/material.dart';

import '../domain/note.dart';
import '../domain/quick_switcher.dart';

Future<QuickSwitcherEntry?> showQuickSwitcher({
  required BuildContext context,
  required List<Note> notes,
  required List<NoteCollection> collections,
}) =>
    showDialog<QuickSwitcherEntry>(
      context: context,
      builder: (_) => _QuickSwitcherDialog(
        notes: notes,
        collections: collections,
      ),
    );

class _QuickSwitcherDialog extends StatefulWidget {
  const _QuickSwitcherDialog({
    required this.notes,
    required this.collections,
  });

  final List<Note> notes;
  final List<NoteCollection> collections;

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
                hintText: 'Nota, attività, raccolta o comando…',
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
