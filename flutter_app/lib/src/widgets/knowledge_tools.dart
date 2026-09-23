import 'package:flutter/material.dart';

import '../domain/knowledge.dart';
import '../domain/note.dart';

class KnowledgeToolsBar extends StatelessWidget {
  const KnowledgeToolsBar({
    required this.text,
    required this.selection,
    required this.notes,
    required this.currentNoteId,
    required this.enabled,
    required this.onEdit,
    required this.onOpenNote,
    super.key,
  });

  final String text;
  final TextSelection selection;
  final List<Note> notes;
  final String currentNoteId;
  final bool enabled;
  final ValueChanged<MarkdownSelectionEdit> onEdit;
  final ValueChanged<String> onOpenNote;

  List<Note> get _textNotes => notes
      .where(
        (note) =>
            !note.isDeleted &&
            !note.isTask &&
            !note.isVisual &&
            note.id != currentNoteId,
      )
      .toList(growable: false);

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          TextButton.icon(
            onPressed: enabled ? () => _link(context) : null,
            icon: const Icon(Icons.link, size: 18),
            label: const Text('Collega'),
          ),
          TextButton.icon(
            onPressed: enabled ? () => _headings(context) : null,
            icon: const Icon(Icons.toc, size: 18),
            label: const Text('Indice'),
          ),
          TextButton.icon(
            onPressed: enabled ? () => _findReplace(context) : null,
            icon: const Icon(Icons.find_replace, size: 18),
            label: const Text('Trova'),
          ),
          TextButton.icon(
            onPressed: enabled ? () => _connections(context) : null,
            icon: const Icon(Icons.hub, size: 18),
            label: const Text('Backlink'),
          ),
        ],
      );

  Future<void> _link(BuildContext context) async {
    final controller = TextEditingController();
    Note? selected;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final query = controller.text.trim().toLowerCase();
          final found = _textNotes
              .where(
                (note) =>
                    query.isEmpty ||
                    note.title.toLowerCase().contains(query),
              )
              .take(50)
              .toList();
          return AlertDialog(
            title: const Text('Collega una nota'),
            content: SizedBox(
              width: 520,
              height: 380,
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Cerca titolo',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: found.isEmpty
                        ? const Center(child: Text('Nessuna nota corrispondente.'))
                        : ListView.builder(
                            itemCount: found.length,
                            itemBuilder: (_, index) {
                              final note = found[index];
                              return ListTile(
                                title: Text(
                                  note.title.isEmpty ? 'Senza titolo' : note.title,
                                ),
                                onTap: () {
                                  selected = note;
                                  Navigator.pop(context);
                                },
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
        },
      ),
    );
    controller.dispose();
    if (selected == null) return;

    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : start;
    onEdit(
      Knowledge.insert(
        text,
        start,
        end,
        selected!.id,
        selected!.title,
      ),
    );
  }

  Future<void> _headings(BuildContext context) async {
    final headings = Knowledge.headings(text);
    final selected = await showDialog<NoteHeading>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Indice dei titoli'),
        content: SizedBox(
          width: 500,
          height: 360,
          child: headings.isEmpty
              ? const Center(
                  child: Text(
                    'Aggiungi titoli Markdown con #, ## o ###. '
                    'I blocchi di codice sono esclusi.',
                  ),
                )
              : ListView(
                  children: headings
                      .map(
                        (heading) => ListTile(
                          contentPadding: EdgeInsets.only(
                            left: (heading.level - 1) * 16.0,
                          ),
                          title: Text(
                            heading.title.isEmpty ? 'Titolo' : heading.title,
                          ),
                          onTap: () => Navigator.pop(context, heading),
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
    if (selected != null) {
      onEdit(
        MarkdownSelectionEdit(
          text,
          selected.offset,
          selected.offset,
        ),
      );
    }
  }

  Future<void> _findReplace(BuildContext context) async {
    final query = TextEditingController();
    final replacement = TextEditingController();
    var caseSensitive = false;
    MarkdownSelectionEdit? result;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final ranges = LiteralSearch.ranges(
            text,
            query.text,
            ignoreCase: !caseSensitive,
          );
          return AlertDialog(
            title: const Text('Trova e sostituisci'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: query,
                    onChanged: (_) => setLocal(() {}),
                    decoration:
                        const InputDecoration(labelText: 'Testo da cercare'),
                  ),
                  TextField(
                    controller: replacement,
                    decoration:
                        const InputDecoration(labelText: 'Sostituisci con'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: caseSensitive,
                    onChanged: (value) =>
                        setLocal(() => caseSensitive = value ?? false),
                    title: const Text('Distingui maiuscole'),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${ranges.length} occorrenze · ricerca letterale',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: ranges.isEmpty
                    ? null
                    : () {
                        final cursor =
                            selection.isValid ? selection.end : 0;
                        final target = ranges.firstWhere(
                          (range) => range.start >= cursor,
                          orElse: () => ranges.first,
                        );
                        result = MarkdownSelectionEdit(
                          text,
                          target.start,
                          target.end,
                        );
                        Navigator.pop(context);
                      },
                child: const Text('Seleziona successiva'),
              ),
              FilledButton(
                onPressed: ranges.isEmpty
                    ? null
                    : () {
                        result = LiteralSearch.replaceAll(
                          text,
                          query.text,
                          replacement.text,
                          ignoreCase: !caseSensitive,
                        );
                        Navigator.pop(context);
                      },
                child: Text('Sostituisci tutte (${ranges.length})'),
              ),
            ],
          );
        },
      ),
    );
    query.dispose();
    replacement.dispose();
    if (result != null) onEdit(result!);
  }

  Future<void> _connections(BuildContext context) async {
    final outgoing = Knowledge.links(text)
        .fold<Map<String, NoteLink>>(
          {},
          (map, link) => map..putIfAbsent(link.id, () => link),
        )
        .values
        .toList();
    final incoming = _textNotes
        .where(
          (note) => Knowledge.links(note.body)
              .any((link) => link.id == currentNoteId.toLowerCase()),
        )
        .toList();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Le pagine collegate'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: ListView(
            children: [
              Text(
                'Da questa nota',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (outgoing.isEmpty)
                const ListTile(
                  title: Text('Nessun collegamento. Usa Collega.'),
                )
              else
                ...outgoing.map((link) {
                  Note? target;
                  for (final note in _textNotes) {
                    if (note.id.toLowerCase() == link.id) {
                      target = note;
                      break;
                    }
                  }
                  return ListTile(
                    title: Text(
                      target?.title.isNotEmpty == true
                          ? target!.title
                          : link.label,
                    ),
                    subtitle: target == null
                        ? const Text('Nota non disponibile')
                        : null,
                    enabled: target != null,
                    onTap: target == null
                        ? null
                        : () {
                            Navigator.pop(context);
                            onOpenNote(target!.id);
                          },
                  );
                }),
              const Divider(),
              Text(
                'Note che rimandano qui',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (incoming.isEmpty)
                const ListTile(title: Text('Nessun backlink salvato.'))
              else
                ...incoming.map(
                  (note) => ListTile(
                    title: Text(note.title.isEmpty ? 'Senza titolo' : note.title),
                    onTap: () {
                      Navigator.pop(context);
                      onOpenNote(note.id);
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
      ),
    );
  }
}
