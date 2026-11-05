import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../domain/privacy_copy.dart';

/// Builds only an explicitly approved plain UTF-8 copy. This UI never
/// modifies a Note, never claims to sanitize an existing PDF object tree.
class PrivacyCopyScreen extends StatefulWidget {
  const PrivacyCopyScreen({required this.sources, super.key});
  final List<PrivacyCopySource> sources;

  @override
  State<PrivacyCopyScreen> createState() => _PrivacyCopyScreenState();
}

class _PrivacyCopyScreenState extends State<PrivacyCopyScreen> {
  String? _selectedId;
  List<PrivacyCopyMatch> _matches = const [];
  final Set<int> _selected = {};
  String? _error;
  bool _saving = false;

  void _inspect(PrivacyCopySource source) {
    try {
      final findings = PrivacyCopy.scan(source.text);
      setState(() {
        _selectedId = source.id;
        _matches = findings;
        _selected
          ..clear()
          ..addAll(List.generate(findings.length, (i) => i));
        _error = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _selectedId = source.id;
        _matches = const [];
        _selected.clear();
        _error = error.message;
      });
    }
  }

  Future<void> _saveCopy(PrivacyCopySource source) async {
    if (_saving || _selected.isEmpty) return;
    setState(() => _saving = true);
    try {
      final safeText = PrivacyCopy.redact(source.text, _selected);
      final name = 'notes-copia-oscurata.txt';
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Esporta solo copia del testo oscurato',
        fileName: name,
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        bytes: Uint8List.fromList(utf8.encode(safeText)),
      );
      if (destination != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Copia di testo esportata. '
              'Verifica manualmente eventuali dati non riconosciuti.'),
        ));
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Esportazione non riuscita: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final map = <String, PrivacyCopySource>{
      for (final item in widget.sources.take(500)) item.id: item,
    };
    final source = map[_selectedId];
    final preview = source != null && _selected.isNotEmpty
        ? PrivacyCopy.redact(source.text, _selected)
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Shield')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
        children: [
          const Text('Individuazione euristica locale di email, IBAN '
              'italiani e possibili numeri mobili. Non riconosce tutti i '
              'dati personali. La copia esportata è solo testo: i PDF '
              'originali non vengono modificati né oscurati.'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: source?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Sorgente'),
            items: [
              for (final entry in map.values)
                DropdownMenuItem(
                  value: entry.id,
                  child: Text(entry.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) {
              if (id != null) _inspect(map[id]!);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (source != null && _error == null) ...[
            const SizedBox(height: 12),
            Text('Revisione sorgente: ${source.revision}'),
            Text('Elementi proposti: ${_matches.length}'),
            for (var i = 0; i < _matches.length; i++)
              CheckboxListTile(
                dense: true,
                title: Text(switch (_matches[i].kind) {
                  PrivacyMatchKind.email => 'Email',
                  PrivacyMatchKind.iban => 'IBAN italiano',
                  PrivacyMatchKind.possibleMobile => 'Possibile numero mobile',
                }),
                subtitle: Text(_matches[i].value),
                value: _selected.contains(i),
                onChanged: _saving
                    ? null
                    : (checked) => setState(() {
                        if (checked == true) {
                            _selected.add(i);
                          } else {
                            _selected.remove(i);
                          }
                        }),
              ),
            const SizedBox(height: 16),
            if (preview != null) ...[
              const Text('Anteprima della copia esportata'),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: SelectableText(preview),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed:
                  _saving || _selected.isEmpty ? null : () => _saveCopy(source),
              icon: const Icon(Icons.save_alt),
              label: const Text('Esporta copia .txt'),
            ),
          ],
        ],
      ),
    );
  }
}
