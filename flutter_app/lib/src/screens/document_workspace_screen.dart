import 'package:flutter/material.dart';

import '../data/document_store.dart';
import '../domain/attachments.dart';
import '../domain/document_workspace.dart';
import '../platform/attachment_bridge.dart';
import '../widgets/ui_resilience.dart';

class DocumentWorkspaceScreen extends StatefulWidget {
  const DocumentWorkspaceScreen({
    required this.noteId,
    required this.attachment,
    required this.store,
    super.key,
  });

  final String noteId;
  final AttachmentRef attachment;
  final DocumentStore store;

  @override
  State<DocumentWorkspaceScreen> createState() =>
      _DocumentWorkspaceScreenState();
}

class _DocumentWorkspaceScreenState extends State<DocumentWorkspaceScreen> {
  List<DocumentOcrLayer> _ocr = const [];
  List<DocumentAnnotation> _annotations = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final ocr = await widget.store.ocrFor(
        widget.noteId,
        widget.attachment.key,
      );
      final annotations = await widget.store.annotationsFor(
        widget.noteId,
        widget.attachment.key,
      );
      if (!mounted) return;
      setState(() {
        _ocr = ocr;
        _annotations = annotations;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userErrorText(error);
      });
    }
  }

  Future<void> _editOcr(DocumentOcrLayer layer) async {
    final controller = TextEditingController(text: layer.searchableText);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Correggi OCR · pagina ${layer.page}'),
        content: SizedBox(
          width: 620,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 18,
            decoration: const InputDecoration(
              helperText:
                  'L’OCR originale resta preservato; questa è una correzione utente.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salva correzione'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await widget.store.correctOcr(
        noteId: layer.noteId,
        assetKey: layer.assetKey,
        page: layer.page,
        correctedText: controller.text,
      );
      await _reload();
    }
    controller.dispose();
  }

  Future<void> _addAnnotation(int page) async {
    var kind = DocumentAnnotationKind.highlight;
    final text = TextEditingController();
    final x = TextEditingController(text: '0');
    final y = TextEditingController(text: '0');
    final width = TextEditingController(text: '1');
    final height = TextEditingController(text: '0.12');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, local) => AlertDialog(
          title: Text('Annotazione · pagina $page'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<DocumentAnnotationKind>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: const [
                      DropdownMenuItem(
                        value: DocumentAnnotationKind.highlight,
                        child: Text('Evidenziazione'),
                      ),
                      DropdownMenuItem(
                        value: DocumentAnnotationKind.note,
                        child: Text('Nota'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) local(() => kind = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: text,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Testo'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final entry in <String, TextEditingController>{
                        'X': x,
                        'Y': y,
                        'L': width,
                        'H': height,
                      }.entries) ...[
                        Expanded(
                          child: TextField(
                            controller: entry.value,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: entry.key,
                              helperText: '0–1',
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      try {
        await widget.store.addAnnotation(
          noteId: widget.noteId,
          assetKey: widget.attachment.key,
          page: page,
          kind: kind,
          x: double.parse(x.text.replaceAll(',', '.')),
          y: double.parse(y.text.replaceAll(',', '.')),
          width: double.parse(width.text.replaceAll(',', '.')),
          height: double.parse(height.text.replaceAll(',', '.')),
          text: text.text,
        );
        await _reload();
      } catch (error) {
        if (mounted) setState(() => _error = userErrorText(error));
      }
    }
    for (final controller in [text, x, y, width, height]) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.trim().toLowerCase();
    final pages = needle.isEmpty
        ? _ocr
        : _ocr
            .where(
                (layer) => layer.searchableText.toLowerCase().contains(needle))
            .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(widget.attachment.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => AttachmentBridge.open(
                        key: widget.attachment.key,
                        name: widget.attachment.name,
                        mime: widget.attachment.type.mime,
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Apri originale'),
                    ),
                    Chip(label: Text('${_ocr.length} pagine OCR')),
                    Chip(label: Text('${_annotations.length} annotazioni')),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Cerca nel testo OCR…',
                  ),
                ),
                const SizedBox(height: 16),
                if (_ocr.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Nessun layer OCR disponibile. Acquisisci il documento '
                        'con Smart Capture per conservare testo e provenienza.',
                      ),
                    ),
                  )
                else if (pages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Nessuna pagina contiene questa ricerca.'),
                  )
                else
                  ...pages.map((layer) {
                    final annotations = _annotations
                        .where((item) => item.page == layer.page)
                        .toList(growable: false);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Pagina ${layer.page}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const Spacer(),
                                if (layer.correctedText != null)
                                  const Chip(label: Text('OCR corretto')),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              layer.searchableText,
                              maxLines: 12,
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _editOcr(layer),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Correggi OCR'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _addAnnotation(layer.page),
                                  icon: const Icon(Icons.add_comment_outlined),
                                  label: const Text('Annota regione'),
                                ),
                              ],
                            ),
                            if (annotations.isNotEmpty) ...[
                              const Divider(),
                              ...annotations.map(
                                (item) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    item.kind ==
                                            DocumentAnnotationKind.highlight
                                        ? Icons.highlight_alt
                                        : Icons.comment_outlined,
                                  ),
                                  title: Text(
                                    item.text.trim().isEmpty
                                        ? item.kind.name
                                        : item.text,
                                  ),
                                  subtitle: SelectableText(item.anchor),
                                  trailing: IconButton(
                                    onPressed: () async {
                                      await widget.store
                                          .deleteAnnotation(item.id);
                                      await _reload();
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
