import 'package:flutter/material.dart';

import '../domain/note.dart';
import '../domain/templates.dart';

class TemplatesScreen extends StatefulWidget {
  const TemplatesScreen({
    required this.notes,
    required this.onUse,
    required this.onEdit,
    super.key,
  });

  final List<Note> notes;
  final ValueChanged<TemplateContent> onUse;
  final ValueChanged<Note> onEdit;

  @override
  State<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends State<TemplatesScreen> {
  final _query = TextEditingController();
  bool _reset = true;
  bool _showPersonal = false;
  String? _expanded;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _useBookTracker() async {
    var draftTitle = 'La mia biblioteca';
    var includeToRead = true;
    final selected = await showDialog<TemplateContent>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final title = draftTitle.trim();
            final preview = PageTemplates.bookTracker(
              title: title.isEmpty ? 'La mia biblioteca' : title,
              includeToRead: includeToRead,
            );
            return AlertDialog(
              title: const Text('Libreria personale'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Crea una nota privata, modificabile come tutte le altre.'),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: draftTitle,
                      maxLength: 90,
                      decoration: const InputDecoration(
                        labelText: 'Titolo della nota',
                      ),
                      onChanged: (value) =>
                          setDialogState(() => draftTitle = value),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Includi "Da leggere"'),
                      value: includeToRead,
                      onChanged: (value) => setDialogState(
                        () => includeToRead = value ?? false,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Anteprima',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    SelectableText(preview.body),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: title.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, preview),
                  child: const Text('Crea nota'),
                ),
              ],
            );
          },
        ),
      );
    if (mounted && selected != null) widget.onUse(selected);
  }

  @override
  Widget build(BuildContext context) {
    final personal = PersonalTemplates.catalog(widget.notes, _query.text);

    return Scaffold(
      appBar: AppBar(title: const Text('Modelli')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
        children: [
          TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Cerca modelli',
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            key: const ValueKey<String>('templates-step4-view'),
            segments: const <ButtonSegment<bool>>[
              ButtonSegment<bool>(
                value: false,
                label: Text('Catalogo'),
                icon: Icon(Icons.auto_awesome_outlined),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('I miei'),
                icon: Icon(Icons.bookmarks_outlined),
              ),
            ],
            selected: <bool>{_showPersonal},
            onSelectionChanged: (selected) => setState(() {
              _showPersonal = selected.first;
              _expanded = null;
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Azzera checklist completate'),
            subtitle: const Text(
              'Quando usi un modello le attività spuntate tornano da fare.',
            ),
            value: _reset,
            onChanged: (value) => setState(() => _reset = value),
          ),
          const SizedBox(height: 10),
          if (!_showPersonal) ...[
            Text(
              'Catalogo gratuito',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Modelli pronti da usare nelle tue note. '
              'Nessun acquisto, abbonamento o accesso a un altro servizio.',
            ),
            const SizedBox(height: 8),
            if (_query.text.trim().isEmpty ||
                'libreria personale'.contains(_query.text.trim().toLowerCase()))
              _TemplateCard(
                keyName: 'builtin:book_tracker',
                title: 'Libreria personale · Gratuito',
                body: PageTemplates.bookTracker().body,
                expanded: _expanded == 'builtin:book_tracker',
                onPreview: () => setState(() {
                  _expanded = _expanded == 'builtin:book_tracker'
                      ? null
                      : 'builtin:book_tracker';
                }),
                onUse: _useBookTracker,
              ),
            ...PageTemplates.all.map(
              (template) => _TemplateCard(
                keyName: 'builtin:${template.key}',
                title: template.name,
                body: template.body,
                expanded: _expanded == 'builtin:${template.key}',
                onPreview: () => setState(() {
                  _expanded = _expanded == 'builtin:${template.key}'
                      ? null
                      : 'builtin:${template.key}';
                }),
                onUse: () {
                  final content = PersonalTemplates.instantiate(
                    template.title,
                    template.body,
                    const [],
                    DateTime.now(),
                    reset: _reset,
                  );
                  widget.onUse(content);
                },
              ),
            ),
          ],
          if (_showPersonal) ...[
            const SizedBox(height: 16),
            Text(
              'I miei modelli',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            if (personal.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Nessun modello personale. Da una nota usa “Salva come modello”.',
                ),
              )
            else
              ...personal.map(
                (note) => _TemplateCard(
                  keyName: 'personal:${note.id}',
                  title: note.title.isEmpty ? 'Modello personale' : note.title,
                  body: note.body,
                  expanded: _expanded == 'personal:${note.id}',
                  onPreview: () => setState(() {
                    _expanded = _expanded == 'personal:${note.id}'
                        ? null
                        : 'personal:${note.id}';
                  }),
                  onUse: () => widget.onUse(
                    PersonalTemplates.from(
                      note,
                      DateTime.now(),
                      reset: _reset,
                    ),
                  ),
                  onEdit: () => widget.onEdit(note),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text(
            'Variabili disponibili: {{data}}, {{ora}}, {{giorno}}. '
            'I modelli personali sono normali note archiviate e restano compatibili con backup e sync.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.keyName,
    required this.title,
    required this.body,
    required this.expanded,
    required this.onPreview,
    required this.onUse,
    this.onEdit,
  });

  final String keyName;
  final String title;
  final String body;
  final bool expanded;
  final VoidCallback onPreview;
  final VoidCallback onUse;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Card(
        key: ValueKey(keyName),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (expanded) ...[
                const SizedBox(height: 8),
                Text(
                  body.length > 2000 ? '${body.substring(0, 2000)}\n…' : body,
                ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onPreview,
                  child: Text(
                    expanded ? 'Nascondi anteprima' : 'Anteprima',
                  ),
                ),
              ),
              FilledButton(
                onPressed: onUse,
                child: const Text('Usa modello'),
              ),
              if (onEdit != null)
                TextButton(
                  onPressed: onEdit,
                  child: const Text('Modifica modello'),
                ),
            ],
          ),
        ),
      );
}
