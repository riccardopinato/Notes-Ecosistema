import 'package:flutter/material.dart';
import '../domain/document_delta.dart';

/// Read-only manual comparison. Inputs are already visibility-scoped by their
/// caller; no remote fetch, no writes, no automatic replacement.
class DocumentDeltaScreen extends StatefulWidget {
  const DocumentDeltaScreen({required this.sources, super.key});
  final List<DocumentDeltaSource> sources;

  @override
  State<DocumentDeltaScreen> createState() => _DocumentDeltaScreenState();
}

class _DocumentDeltaScreenState extends State<DocumentDeltaScreen> {
  String? _beforeId;
  String? _afterId;
  DocumentDeltaReport? _report;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final sourceMap = <String, DocumentDeltaSource>{};
    for (final item in widget.sources.take(500)) {
      sourceMap[item.id] = item;
    }
    final choices = sourceMap.values.toList(growable: false);
    final a = sourceMap[_beforeId];
    final b = sourceMap[_afterId];
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Document Delta')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
        children: [
          const Text('Confronto verificabile, solo lettura. '
              'La riga rimossa e la riga aggiunta indicano differenze '
              'testuali; nessuna modifica viene salvata.'),
          const SizedBox(height: 16),
          if (choices.length < 2)
            const Text('Servono due versioni testuali disponibili.')
          else ...[
            DropdownButtonFormField<String>(
              initialValue: a?.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Versione iniziale'),
              items: [
                for (final item in choices)
                  DropdownMenuItem(
                      value: item.id,
                      child: Text(item.title, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (id) => setState(() {
                _beforeId = id;
                _report = null;
              }),
            ),
            DropdownButtonFormField<String>(
              initialValue: b?.id,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Versione successiva'),
              items: [
                for (final item in choices)
                  DropdownMenuItem(
                      value: item.id,
                      child: Text(item.title, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (id) => setState(() {
                _afterId = id;
                _report = null;
              }),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: a == null || b == null || a.id == b.id
                  ? null
                  : () {
                      try {
                        final result = DocumentDelta.compare(a, b);
                        setState(() {
                          _report = result;
                          _error = null;
                        });
                      } on FormatException catch (err) {
                        setState(() {
                          _report = null;
                          _error = err.message;
                        });
                      }
                    },
              child: const Text('Confronta'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (report != null && a != null && b != null) ...[
            const SizedBox(height: 20),
            Text('Aggiunte: ${report.added} · Rimozioni: ${report.removed}'),
            const SizedBox(height: 6),
            Text('Prima: ${a.provenance}'),
            Text('Dopo: ${b.provenance}'),
            SelectableText('SHA-256 prima: ${report.leftFingerprint}'),
            SelectableText('SHA-256 dopo: ${report.rightFingerprint}'),
            const Divider(),
            for (final row in report.rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
                color: switch (row.kind) {
                  DocumentDeltaKind.added =>
                    Theme.of(context).colorScheme.primaryContainer,
                  DocumentDeltaKind.removed =>
                    Theme.of(context).colorScheme.errorContainer,
                  DocumentDeltaKind.unchanged => null,
                },
                child: SelectableText(
                  '${switch (row.kind) {
                    DocumentDeltaKind.added => '+ ',
                    DocumentDeltaKind.removed => '- ',
                    DocumentDeltaKind.unchanged => '  ',
                  }}${row.text}',
                ),
              ),
          ],
        ],
      ),
    );
  }
}
