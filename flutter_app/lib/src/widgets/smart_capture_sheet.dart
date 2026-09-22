import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/attachments.dart';
import '../domain/smart_capture.dart';

class SmartCaptureSheet extends StatefulWidget {
  const SmartCaptureSheet({
    required this.body,
    required this.onBodyChanged,
    super.key,
  });

  final String body;
  final ValueChanged<String> onBodyChanged;

  @override
  State<SmartCaptureSheet> createState() => _SmartCaptureSheetState();
}

class _SmartCaptureSheetState extends State<SmartCaptureSheet> {
  late String _body;
  late final TextEditingController _url;
  late final DocumentScanner _scanner;
  late final TextRecognizer _recognizer;

  bool _busy = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _body = widget.body;
    _url = TextEditingController(
      text: SmartCaptureRules.extractSingleHttpUrl(_body) ?? '',
    );
    _scanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: const {
          DocumentFormat.jpeg,
          DocumentFormat.pdf,
        },
        mode: ScannerMode.full,
        pageLimit: 12,
        isGalleryImport: true,
      ),
    );
    _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  }

  @override
  void dispose() {
    _url.dispose();
    _scanner.close();
    _recognizer.close();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('FormatException: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setBody(String body) {
    _body = body;
    widget.onBodyChanged(body);
  }

  Future<void> _scan() => _run(() async {
        final result = await _scanner.scanDocument();
        final store = await AttachmentStore.open();
        final ocr = <String>[];

        for (final imagePath in result.images ?? const <String>[]) {
          final imageFile = _fileFromScannerPath(imagePath);
          if (!await imageFile.exists()) continue;
          final recognized = await _recognizer.processImage(
            InputImage.fromFilePath(imageFile.path),
          );
          final clipped = SmartCaptureRules.clipOcr(recognized.text);
          if (clipped.isNotEmpty) ocr.add(clipped);
        }

        var imported = 0;
        final pdf = result.pdf;
        if (pdf != null) {
          final file = _fileFromScannerPath(pdf.uri);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final key = await store.ingest(bytes, AttachmentType.pdf);
            final before = Attachments.refs(_body).map((e) => e.key).toSet();
            if (!before.contains(key)) {
              _setBody(
                Attachments.append(
                  _body,
                  key,
                  'Scansione.pdf',
                ),
              );
              imported++;
            }
          }
        } else {
          for (final imagePath in result.images ?? const <String>[]) {
            final file = _fileFromScannerPath(imagePath);
            if (!await file.exists()) continue;
            final bytes = await file.readAsBytes();
            final type =
                Attachments.typeFromName(file.path) ?? AttachmentType.jpeg;
            final key = await store.ingest(bytes, type);
            final before = Attachments.refs(_body).map((e) => e.key).toSet();
            if (!before.contains(key)) {
              _setBody(
                Attachments.append(
                  _body,
                  key,
                  file.uri.pathSegments.isEmpty
                      ? 'Scansione.jpg'
                      : file.uri.pathSegments.last,
                ),
              );
              imported++;
            }
          }
        }

        final combined = ocr.join('\n\n---\n\n').trim();
        if (combined.isNotEmpty &&
            !SmartCaptureRules.containsSection(
              _body,
              'Testo scannerizzato',
              combined,
            )) {
          _setBody(
            SmartCaptureRules.appendSection(
              _body,
              'Testo scannerizzato',
              combined,
            ),
          );
        }

        if (mounted) {
          setState(() {
            _status = imported > 0 && combined.isNotEmpty
                ? 'Documento acquisito · OCR aggiunto.'
                : imported > 0
                    ? 'Documento acquisito.'
                    : combined.isNotEmpty
                        ? 'OCR aggiunto.'
                        : 'Scansione completata.';
          });
        }
      });

  Future<void> _ocrAttachedImages() => _run(() async {
        final refs = Attachments.refs(_body)
            .where((ref) => ref.type.category == AttachmentCategory.image)
            .toList();
        if (refs.isEmpty) {
          throw const FormatException(
            'Questa nota non contiene immagini da leggere.',
          );
        }

        final store = await AttachmentStore.open();
        final texts = <String>[];
        for (final ref in refs) {
          final file = store.file(ref.key);
          if (!await file.exists()) continue;
          final recognized = await _recognizer.processImage(
            InputImage.fromFilePath(file.path),
          );
          final clipped = SmartCaptureRules.clipOcr(recognized.text);
          if (clipped.isNotEmpty) texts.add(clipped);
        }

        final combined = texts.join('\n\n---\n\n').trim();
        if (combined.isEmpty) {
          if (mounted) {
            setState(() => _status = 'Nessun testo riconosciuto.');
          }
          return;
        }

        if (!SmartCaptureRules.containsSection(
          _body,
          'Testo estratto',
          combined,
        )) {
          _setBody(
            SmartCaptureRules.appendSection(
              _body,
              'Testo estratto',
              combined,
            ),
          );
        }
        if (mounted) {
          setState(
            () => _status =
                'Testo estratto dalle immagini · ${combined.length} caratteri.',
          );
        }
      });

  Future<void> _captureWeb() => _run(() async {
        final snapshot = await WebCapture().fetch(_url.text);
        final markdown = snapshot.toMarkdown();
        if (!SmartCaptureRules.containsSection(
          _body,
          'Pagina acquisita',
          markdown,
        )) {
          _setBody(
            SmartCaptureRules.appendSection(
              _body,
              'Pagina acquisita',
              markdown,
            ),
          );
        }
        if (mounted) {
          setState(() => _status = 'Pagina salvata nella nota.');
        }
      });

  File _fileFromScannerPath(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme == 'file') {
      return File.fromUri(uri);
    }
    return File(raw);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 8,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Smart Capture',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Acquisisci carta, immagini e pagine web senza uscire dalla nota.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              if (_status != null) ...[
                const SizedBox(height: 10),
                Text(_status!),
              ],
              const SizedBox(height: 16),
              _CaptureCard(
                icon: Icons.document_scanner,
                title: 'Scanner documenti',
                detail:
                    'Ritaglio, prospettiva, multipagina, PDF e OCR del testo.',
                button: 'Scansiona',
                enabled: !_busy,
                onPressed: _scan,
              ),
              const SizedBox(height: 12),
              _CaptureCard(
                icon: Icons.text_snippet,
                title: 'OCR immagini',
                detail:
                    'Legge le immagini già allegate e aggiunge il testo riconosciuto.',
                button: 'Estrai testo',
                enabled: !_busy,
                onPressed: _ocrAttachedImages,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.language),
                          const SizedBox(width: 10),
                          Text(
                            'Acquisisci pagina web',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Salva titolo, descrizione, fonte e testo leggibile in Markdown.',
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _url,
                        enabled: !_busy,
                        decoration: const InputDecoration(
                          labelText: 'https://…',
                        ),
                        keyboardType: TextInputType.url,
                        maxLength: SmartCaptureRules.maxUrlLength,
                      ),
                      FilledButton.icon(
                        onPressed:
                            _busy || _url.text.trim().isEmpty ? null : _captureWeb,
                        icon: const Icon(Icons.download),
                        label: const Text('Salva contenuto'),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Script, cookie e codice della pagina non vengono conservati.',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _CaptureCard extends StatelessWidget {
  const _CaptureCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.button,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String button;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(detail),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: enabled ? onPressed : null,
                child: Text(button),
              ),
            ],
          ),
        ),
      );
}
