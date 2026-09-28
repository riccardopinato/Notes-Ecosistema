import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/attachments.dart';
import '../domain/derivatives.dart';
import '../domain/documents.dart';
import '../platform/attachment_bridge.dart';
import '../state/document_controller.dart';
import '../state/workspace_controller.dart';
import '../widgets/editorial.dart';
import '../widgets/ui_resilience.dart';

class PdfWorkspaceScreen extends ConsumerStatefulWidget {
  const PdfWorkspaceScreen({
    required this.noteId,
    required this.attachment,
    super.key,
  });

  final String noteId;
  final AttachmentRef attachment;

  @override
  ConsumerState<PdfWorkspaceScreen> createState() => _PdfWorkspaceScreenState();
}

class _PdfWorkspaceScreenState extends ConsumerState<PdfWorkspaceScreen> {
  final TextEditingController _search = TextEditingController();
  List<PdfAnnotation> _annotations = const [];
  List<SourceDerivative> _derivatives = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final annotations = await ref
          .read(documentStoreProvider)
          .forAsset(widget.noteId, widget.attachment.key);
      final derivatives =
          await ref.read(derivativeStoreProvider).forNote(widget.noteId);
      if (!mounted) return;
      setState(() {
        _annotations = annotations;
        _derivatives = derivatives;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  SourceDerivative? get _ocr => DocumentRules.preferredOcr(
        _derivatives,
        widget.attachment.key,
      );

  @override
  Widget build(BuildContext context) {
    final ocr = _ocr;
    final offsets = ocr == null
        ? const <int>[]
        : DocumentRules.searchOffsets(ocr.content, _search.text);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Workspace'),
        actions: [
          IconButton(
            tooltip: 'Apri PDF originale',
            onPressed: _openOriginal,
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          children: [
            const EditorialEyebrow('DOCUMENT WORKSPACE'),
            const SizedBox(height: 4),
            Text(
              widget.attachment.name,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            const Text(
              'Il PDF originale resta immutabile nel CAS. OCR e annotazioni '
              'sono layer separati e modificabili.',
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _openOriginal,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Apri PDF originale'),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              _ErrorCard(onRetry: _load)
            else ...[
              const EditorialSection(
                'Testo ricercabile',
                detail: 'OCR derivato dalla sorgente, non sostituisce il PDF.',
              ),
              if (ocr == null)
                const _EmptyOcr()
              else ...[
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: 'Cerca nel testo OCR',
                    suffixText: _search.text.trim().isEmpty
                        ? null
                        : '${offsets.length} match',
                  ),
                ),
                const SizedBox(height: 12),
                _OcrCard(
                  derivative: ocr,
                  query: _search.text,
                  onCorrect: () => _correctOcr(ocr),
                ),
              ],
              const SizedBox(height: 24),
              EditorialSection(
                'Annotazioni',
                detail:
                    '${_annotations.length} · pagina o regione normalizzata',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _addAnnotation,
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('Aggiungi annotazione'),
                ),
              ),
              const SizedBox(height: 10),
              if (_annotations.isEmpty)
                const Text('Nessuna annotazione in questo PDF.')
              else
                ..._annotations.map(
                  (item) => Card(
                    child: ListTile(
                      leading: Icon(
                        item.kind == PdfAnnotationKind.highlight
                            ? Icons.highlight_alt
                            : Icons.comment_outlined,
                      ),
                      title: Text(
                        'Pagina ${item.anchor.page}'
                        '${item.anchor.hasRegion ? ' · regione' : ''}',
                      ),
                      subtitle: Text(
                        [
                          if (item.selectedText.trim().isNotEmpty)
                            item.selectedText.trim(),
                          if (item.comment.trim().isNotEmpty)
                            item.comment.trim(),
                        ].join('\n'),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: 'Elimina annotazione',
                        onPressed: () => _deleteAnnotation(item),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openOriginal() async {
    try {
      await AttachmentBridge.open(
        key: widget.attachment.key,
        name: widget.attachment.name,
        mime: widget.attachment.type.mime,
      );
    } catch (error) {
      _message(
        userErrorText(
          error,
          fallback: 'Impossibile aprire il PDF originale.',
        ),
      );
    }
  }

  Future<void> _correctOcr(SourceDerivative source) async {
    final controller = TextEditingController(text: source.content);
    final corrected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Correggi testo OCR'),
        content: SizedBox(
          width: 620,
          child: TextField(
            controller: controller,
            minLines: 12,
            maxLines: 22,
            maxLength: 500000,
            decoration: const InputDecoration(
              helperText:
                  'L’OCR originale resta preservato come evidenza derivata.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Salva correzione'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (corrected == null || corrected.isEmpty) return;

    try {
      await ref.read(derivativeStoreProvider).add(
            sourceNoteId: widget.noteId,
            sourceAssetKey: widget.attachment.key,
            kind: DerivativeKind.ocrCorrected,
            content: corrected,
            sourceText: corrected,
            sourceFingerprint: source.sourceFingerprint,
            engine: 'user-corrected-ocr-v1',
          );
      await _load();
    } catch (error) {
      _message(userErrorText(error));
    }
  }

  Future<void> _addAnnotation() async {
    final page = TextEditingController(text: '1');
    final selected = TextEditingController();
    final comment = TextEditingController();
    final x = TextEditingController();
    final y = TextEditingController();
    final width = TextEditingController();
    final height = TextEditingController();
    var kind = PdfAnnotationKind.comment;
    var region = false;

    final result = await showDialog<
        ({
          PdfAnnotationKind kind,
          PdfAnchor anchor,
          String selected,
          String comment,
        })>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, local) => AlertDialog(
          title: const Text('Annotazione PDF'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<PdfAnnotationKind>(
                    segments: const [
                      ButtonSegment(
                        value: PdfAnnotationKind.comment,
                        label: Text('Commento'),
                        icon: Icon(Icons.comment_outlined),
                      ),
                      ButtonSegment(
                        value: PdfAnnotationKind.highlight,
                        label: Text('Evidenzia'),
                        icon: Icon(Icons.highlight_alt),
                      ),
                    ],
                    selected: {kind},
                    onSelectionChanged: (value) =>
                        local(() => kind = value.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: page,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Pagina'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: selected,
                    maxLength: DocumentRules.maxSelectedText,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Testo selezionato / citazione',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: comment,
                    maxLength: DocumentRules.maxComment,
                    minLines: 2,
                    maxLines: 5,
                    decoration:
                        const InputDecoration(labelText: 'Commento'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ancora a una regione'),
                    subtitle: const Text(
                      'Coordinate normalizzate 0–1, indipendenti dal renderer.',
                    ),
                    value: region,
                    onChanged: (value) => local(() => region = value),
                  ),
                  if (region)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final field in [
                          ('X', x),
                          ('Y', y),
                          ('Larghezza', width),
                          ('Altezza', height),
                        ])
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: field.$2,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: InputDecoration(labelText: field.$1),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                final pageValue = int.tryParse(page.text.trim());
                if (pageValue == null) return;
                final anchor = PdfAnchor(
                  page: pageValue,
                  x: region ? double.tryParse(x.text.trim()) : null,
                  y: region ? double.tryParse(y.text.trim()) : null,
                  width: region ? double.tryParse(width.text.trim()) : null,
                  height: region ? double.tryParse(height.text.trim()) : null,
                );
                try {
                  anchor.validate();
                } catch (_) {
                  return;
                }
                Navigator.pop(
                  context,
                  (
                    kind: kind,
                    anchor: anchor,
                    selected: selected.text.trim(),
                    comment: comment.text.trim(),
                  ),
                );
              },
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ),
    );

    for (final controller in [page, selected, comment, x, y, width, height]) {
      controller.dispose();
    }
    if (result == null) return;

    try {
      await ref.read(documentStoreProvider).add(
            noteId: widget.noteId,
            assetKey: widget.attachment.key,
            anchor: result.anchor,
            kind: result.kind,
            selectedText: result.selected,
            comment: result.comment,
          );
      await _load();
    } catch (error) {
      _message(userErrorText(error));
    }
  }

  Future<void> _deleteAnnotation(PdfAnnotation item) async {
    await ref.read(documentStoreProvider).delete(item.id);
    await _load();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }
}

class _OcrCard extends StatelessWidget {
  const _OcrCard({
    required this.derivative,
    required this.query,
    required this.onCorrect,
  });

  final SourceDerivative derivative;
  final String query;
  final VoidCallback onCorrect;

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    final content = derivative.content;
    String shown = content;
    if (q.isNotEmpty) {
      final lower = content.toLowerCase();
      final index = lower.indexOf(q.toLowerCase());
      if (index >= 0) {
        final start = (index - 160).clamp(0, content.length).toInt();
        final end = (index + q.length + 320).clamp(0, content.length).toInt();
        shown = '${start > 0 ? '…' : ''}${content.substring(start, end)}'
            '${end < content.length ? '…' : ''}';
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  derivative.kind == DerivativeKind.ocrCorrected
                      ? Icons.verified_outlined
                      : Icons.document_scanner_outlined,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    derivative.kind == DerivativeKind.ocrCorrected
                        ? 'OCR corretto dall’utente'
                        : 'OCR originale',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: onCorrect,
                  child: const Text('Correggi'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(shown),
          ],
        ),
      ),
    );
  }
}

class _EmptyOcr extends StatelessWidget {
  const _EmptyOcr();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            'Nessun layer OCR persistente per questo PDF. '
            'Acquisisci il documento con Smart Capture per creare testo '
            'ricercabile con provenance.',
          ),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Text('Document Workspace non disponibile.'),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Riprova'),
              ),
            ],
          ),
        ),
      );
}
