import 'package:flutter/material.dart';

import '../domain/note.dart';
import '../widgets/editorial.dart';

class NotesScreen extends StatelessWidget {
  const NotesScreen({
    required this.notes,
    required this.collections,
    required this.query,
    required this.searchMode,
    required this.onQueryChanged,
    required this.onOpen,
    required this.onFavorite,
    required this.onPin,
    required this.onTrash,
    super.key,
  });

  final List<Note> notes;
  final List<NoteCollection> collections;
  final String query;
  final bool searchMode;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Note> onOpen;
  final ValueChanged<String> onFavorite;
  final void Function(String id, bool value) onPin;
  final ValueChanged<String> onTrash;

  @override
  Widget build(BuildContext context) {
    final names = {for (final c in collections) c.id: c.name};
    final normalized = query.trim().toLowerCase();
    final visible = notes.where((note) {
      if (note.isDeleted || note.archived || note.isTask) return false;
      if (!searchMode || normalized.isEmpty) return true;
      return note.title.toLowerCase().contains(normalized) ||
          note.body.toLowerCase().contains(normalized) ||
          note.tags.any((tag) => tag.toLowerCase().contains(normalized));
    }).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
      children: [
        if (searchMode) ...[
          TextFormField(
            initialValue: query,
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              labelText: 'Cerca nel titolo, nel testo e nei tag',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty ? null : IconButton(onPressed: () => onQueryChanged(''), icon: const Icon(Icons.close)),
            ),
          ),
          const SizedBox(height: 10),
          Text('${visible.length} risultati', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
        ] else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              FilterChip(selected: true, onSelected: null, label: Text('Tutte')),
              FilterChip(selected: false, onSelected: null, label: Text('Inbox')),
              FilterChip(selected: false, onSelected: null, label: Text('Preferiti')),
              FilterChip(selected: false, onSelected: null, label: Text('Archivio')),
              FilterChip(selected: false, onSelected: null, label: Text('Cestino')),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: const [
              FilterChip(selected: true, onSelected: null, label: Text('Tutte')),
              FilterChip(selected: false, onSelected: null, label: Text('Testo')),
              FilterChip(selected: false, onSelected: null, label: Text('Checklist')),
              FilterChip(selected: false, onSelected: null, label: Text('Disegni')),
              FilterChip(selected: false, onSelected: null, label: Text('Lavagne')),
            ],
          ),
          const EditorialSection('Le tue pagine'),
        ],
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.description, size: 32, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 10),
                Text(searchMode ? 'Nessun risultato.' : 'La prossima idea è tua.', style: Theme.of(context).textTheme.headlineMedium),
                Text(searchMode ? 'Prova un’altra parola.' : 'Un pensiero, una lista, un progetto. Inizia con Nuova nota.'),
              ],
            ),
          )
        else
          ...visible.map((note) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _NoteCard(
                  note: note,
                  collection: names[note.collectionId] ?? 'Inbox',
                  onOpen: () => onOpen(note),
                  onFavorite: () => onFavorite(note.id),
                  onPin: () => onPin(note.id, !note.pinned),
                  onTrash: () => onTrash(note.id),
                ),
              )),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.collection,
    required this.onOpen,
    required this.onFavorite,
    required this.onPin,
    required this.onTrash,
  });

  final Note note;
  final String collection;
  final VoidCallback onOpen;
  final VoidCallback onFavorite;
  final VoidCallback onPin;
  final VoidCallback onTrash;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final preview = note.isVisual ? '' : note.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: colors.outlineVariant)),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 22),
              width: 4,
              height: 32,
              color: note.favorite || note.pinned ? colors.primary : colors.outlineVariant,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(collection, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.primary))),
                        if (note.pinned) Icon(Icons.push_pin, size: 16, color: colors.primary),
                        if (note.favorite) Icon(Icons.star, size: 16, color: colors.primary),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'favorite') onFavorite();
                            if (value == 'pin') onPin();
                            if (value == 'trash') onTrash();
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'favorite', child: Text(note.favorite ? 'Rimuovi dai preferiti' : 'Aggiungi ai preferiti')),
                            PopupMenuItem(value: 'pin', child: Text(note.pinned ? 'Non fissare più' : 'Fissa in alto')),
                            const PopupMenuItem(value: 'trash', child: Text('Sposta nel cestino')),
                          ],
                        ),
                      ],
                    ),
                    Text(note.title.isEmpty ? 'Senza titolo' : note.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontFamily: 'serif')),
                    if (note.visualKind != null) ...[
                      const SizedBox(height: 6),
                      Chip(label: Text(note.visualKind == VisualDocumentKind.whiteboard ? 'Lavagna' : 'Disegno'), visualDensity: VisualDensity.compact),
                    ],
                    if (note.tags.isNotEmpty)
                      Text(note.tags.map((e) => '#$e').join(' '), maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 8),
                    Divider(color: colors.outlineVariant),
                    Text('Modificata · ${editorialDate(note.updatedAt)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
