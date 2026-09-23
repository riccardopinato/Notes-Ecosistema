import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../domain/attachments.dart';
import '../domain/blocks.dart';
import '../domain/diary.dart';
import '../domain/editing.dart';
import '../domain/knowledge.dart';
import '../domain/note.dart';
import '../domain/planner.dart';
import '../domain/templates.dart';
import '../domain/visual_documents.dart';
import '../platform/attachment_bridge.dart';
import '../screens/sketch_screen.dart';
import '../screens/whiteboard_screen.dart';
import '../state/workspace_controller.dart';
import '../widgets/editorial.dart';
import '../widgets/knowledge_tools.dart';
import '../widgets/smart_capture_sheet.dart';
import '../widgets/universal_block_editor.dart';

enum _EditorMode { text, preview, blocks, checklist }

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({
    required this.collections,
    this.note,
    this.allNotes = const [],
    super.key,
  });

  final Note? note;
  final List<NoteCollection> collections;
  final List<Note> allNotes;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late final String _id;
  late final TextEditingController _title;
  late final TextEditingController _body;
  late String? _collectionId;
  late List<String> _tags;
  List<ContentBlock> _blocks = const [];
  bool _blocksInitialized = false;
  _EditorMode _mode = _EditorMode.text;
  bool _saving = false;
  bool _dirty = false;
  bool _recording = false;
  String? _recordingPath;
  Timer? _recordingTimer;
  final AudioRecorder _recorder = AudioRecorder();
  String? _error;

  bool get _readOnlyVisual => widget.note?.isVisual == true;
  DateTime? get _diaryDate => Diary.date(_tags);

  @override
  void initState() {
    super.initState();
    _id = widget.note?.id ?? const Uuid().v4();
    _title = TextEditingController(text: widget.note?.title ?? '');
    _body = TextEditingController(text: widget.note?.body ?? '');
    _collectionId = widget.note?.collectionId;
    _tags = List<String>.from(widget.note?.tags ?? const []);
    if (Checklist.hasMarker(_body.text)) {
      _mode = _EditorMode.checklist;
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    unawaited(_recorder.dispose());
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (_saving || _recording || _readOnlyVisual) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final normalizedTags = NoteTags.normalize(_tags);
      final now = DateTime.now().millisecondsSinceEpoch;
      final old = widget.note;
      final note = old == null
          ? Note(
              id: _id,
              title: _title.text,
              body: _body.text,
              collectionId: _collectionId,
              favorite: false,
              createdAt: now,
              updatedAt: now,
              pinned: false,
              archived: false,
              tags: normalizedTags,
            )
          : old.copyWith(
              title: _title.text,
              body: _body.text,
              collectionId: _collectionId,
              tags: normalizedTags,
              updatedAt: now,
            );

      await ref.read(workspaceProvider.notifier).save(note);
      if (_blocksInitialized) {
        final normalized = _blocks.isEmpty
            ? BlockEditorCodec.parse(_id, _body.text)
            : BlockEditorCodec.canonicalize(_id, _blocks);
        await ref.read(databaseProvider).replaceNoteBlocks(_id, normalized);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString().replaceFirst('FormatException: ', '');
        });
      }
    }
  }

  Future<void> _enableBlocks() async {
    if (_saving) return;
    try {
      final stored = _blocksInitialized
          ? _blocks
          : await ref.read(databaseProvider).loadNoteBlocks(_id);
      final storedMarkdown =
          stored.isEmpty ? null : BlockEditorCodec.toMarkdown(stored);
      final source = stored.isNotEmpty && storedMarkdown == _body.text
          ? stored
          : BlockEditorCodec.parse(_id, _body.text);
      if (!mounted) return;
      setState(() {
        _blocks = source.isEmpty
            ? [BlockEditorCodec.newBlock(_id, ContentBlockType.text, 0)]
            : source;
        _blocksInitialized = true;
        _mode = _EditorMode.blocks;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('FormatException: ', '');
        });
      }
    }
  }

  void _blocksChanged(List<ContentBlock> blocks) {
    final normalized = BlockEditorCodec.canonicalize(_id, blocks);
    final markdown = BlockEditorCodec.toMarkdown(normalized);
    setState(() {
      _blocks = normalized;
      _blocksInitialized = true;
      _body.text = markdown;
      _body.selection = TextSelection.collapsed(offset: markdown.length);
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _openVisual(Note note) async {
    if (note.visualKind == VisualDocumentKind.whiteboard) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WhiteboardScreen(
            note: note,
            onSave: (updated) =>
                ref.read(workspaceProvider.notifier).save(updated),
          ),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SketchScreen(
            note: note,
            onSave: (updated) =>
                ref.read(workspaceProvider.notifier).save(updated),
          ),
        ),
      );
    }
    await ref.read(workspaceProvider.notifier).refresh();
  }

  Future<void> _openVisualById(String id) async {
    final notes = ref.read(workspaceProvider).notes;
    Note? target;
    for (final note in notes) {
      if (note.id == id && note.isVisual && !note.isDeleted) {
        target = note;
        break;
      }
    }
    if (target == null) {
      setState(() => _error = 'Documento visuale non disponibile.');
      return;
    }
    await _openVisual(target);
  }

  Future<void> _createDrawing(String blockId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = const Uuid().v4();
    final note = Note(
      id: id,
      title: 'Disegno',
      body: SketchCodec.encode(SketchDocument()),
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      tags: const [],
      sketchJson: const VisualInfo(
        kind: VisualInfoKind.sketch,
      ).encode(),
    );
    final linked = note.copyWith(
      sketchJson: VisualInfo(
        linkedNoteId: _id,
        kind: VisualInfoKind.sketch,
      ).encode(),
    );
    await ref.read(workspaceProvider.notifier).save(linked);
    _attachVisualBlock(
      blockId,
      ContentBlockType.drawing,
      BlockEditorCodec.drawingMetadata(id),
      'Disegno',
    );
    await _openVisual(linked);
  }

  Future<void> _createWhiteboard(String blockId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = const Uuid().v4();
    final note = Note(
      id: id,
      title: 'Lavagna',
      body: WhiteboardCodec.encode(
        WhiteboardOps.empty(WhiteboardMode.freeform),
      ),
      favorite: false,
      createdAt: now,
      updatedAt: now,
      pinned: false,
      archived: false,
      tags: const [],
      sketchJson: VisualInfo(
        linkedNoteId: _id,
        kind: VisualInfoKind.whiteboard,
      ).encode(),
    );
    await ref.read(workspaceProvider.notifier).save(note);
    _attachVisualBlock(
      blockId,
      ContentBlockType.whiteboard,
      BlockEditorCodec.whiteboardMetadata(id),
      'Lavagna',
    );
    await _openVisual(note);
  }

  void _attachVisualBlock(
    String blockId,
    ContentBlockType type,
    String metadata,
    String fallbackTitle,
  ) {
    final next = _blocks.map((block) {
      if (block.id != blockId) return block;
      return block.copyWith(
        type: type,
        checked: null,
        text: block.text.trim().isEmpty ? fallbackTitle : block.text,
        metadataJson: metadata,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }).toList();
    _blocksChanged(next);
  }

  Future<void> _smartCapture() async {
    if (_saving) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SmartCaptureSheet(
        body: _body.text,
        onBodyChanged: (body) {
          if (!mounted || body == _body.text) return;
          setState(() {
            _body.text = body;
            _body.selection = TextSelection.collapsed(offset: body.length);
            _dirty = true;
            _error = null;
            if (_blocksInitialized) {
              _blocks = BlockEditorCodec.parse(_id, body);
            }
          });
        },
      ),
    );
  }

  Future<void> _takePhoto() async {
    if (_saving || _recording) return;
    try {
      if (Attachments.refs(_body.text).map((ref) => ref.key).toSet().length >=
          20) {
        throw const FormatException(
          'Puoi aggiungere fino a 20 allegati per nota.',
        );
      }
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
        maxWidth: 4096,
        maxHeight: 4096,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      final store = await AttachmentStore.open();
      final key = await store.ingest(bytes, AttachmentType.jpeg);
      final label =
          'Foto ${DateTime.now().toIso8601String().substring(0, 10)}';
      final body = Attachments.append(_body.text, key, label);
      if (!mounted) return;
      setState(() {
        _body.text = body;
        _body.selection = TextSelection.collapsed(offset: body.length);
        _dirty = true;
        _error = null;
        if (_blocksInitialized) {
          _blocks = BlockEditorCodec.parse(_id, body);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    if (_saving) return;

    try {
      if (Attachments.refs(_body.text).map((ref) => ref.key).toSet().length >=
          20) {
        throw const FormatException(
          'Puoi aggiungere fino a 20 allegati per nota.',
        );
      }
      if (!await _recorder.hasPermission()) {
        throw const FormatException(
          'Microfono non autorizzato. Abilitalo nelle impostazioni Android.',
        );
      }

      final root = await getTemporaryDirectory();
      final path = p.join(
        root.path,
        'voice-${const Uuid().v4()}.m4a',
      );
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) {
        await _recorder.cancel();
        return;
      }

      _recordingTimer?.cancel();
      _recordingTimer = Timer(
        const Duration(minutes: 5),
        () => unawaited(_stopRecording()),
      );
      setState(() {
        _recording = true;
        _recordingPath = path;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _recordingPath = null;
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    final fallback = _recordingPath;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    setState(() => _recording = false);

    String? path;
    try {
      path = await _recorder.stop() ?? fallback;
      if (path == null) {
        throw const FormatException('Registrazione non disponibile.');
      }
      final file = File(path);
      if (!await file.exists()) {
        throw const FormatException('Registrazione non disponibile.');
      }
      final bytes = await file.readAsBytes();
      final store = await AttachmentStore.open();
      final key = await store.ingest(bytes, AttachmentType.m4a);
      final now = DateTime.now();
      final label =
          'Registrazione ${now.toIso8601String().substring(0, 16).replaceFirst('T', ' ')}';
      final body = Attachments.append(_body.text, key, label);
      if (!mounted) return;
      setState(() {
        _body.text = body;
        _body.selection = TextSelection.collapsed(offset: body.length);
        _dirty = true;
        _recordingPath = null;
        _error = null;
        if (_blocksInitialized) {
          _blocks = BlockEditorCodec.parse(_id, body);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _recordingPath = null;
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    } finally {
      final cleanup = path ?? fallback;
      if (cleanup != null) {
        try {
          final file = File(cleanup);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _attachFiles() async {
    if (_saving) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const [
          'jpg',
          'jpeg',
          'png',
          'webp',
          'm4a',
          'mp3',
          'wav',
          'ogg',
          'pdf',
          'txt',
          'docx',
          'xlsx',
          'pptx',
        ],
      );
      if (picked == null || picked.files.isEmpty) return;
      final store = await AttachmentStore.open();
      var body = _body.text;

      for (final file in picked.files) {
        final bytes = file.bytes;
        final type = Attachments.typeFromName(file.name);
        if (bytes == null || type == null) {
          throw FormatException('Formato non supportato: ${file.name}');
        }
        final key = await store.ingest(bytes, type);
        body = Attachments.append(body, key, file.name);
      }

      if (!mounted) return;
      setState(() {
        _body.text = body;
        _body.selection = TextSelection.collapsed(offset: body.length);
        _dirty = true;
        if (_blocksInitialized) {
          _blocks = BlockEditorCodec.parse(_id, body);
        }
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('FormatException: ', '');
        });
      }
    }
  }

  Future<void> _attachmentPanel(AttachmentRef ref) async {
    try {
      final store = await AttachmentStore.open();
      await store.read(ref.key);
      final file = store.file(ref.key);
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ref.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  ref.type.mime,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                if (ref.type.category == AttachmentCategory.image) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Image.file(
                        file,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Text('Anteprima immagine non disponibile.'),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        try {
                          await AttachmentBridge.open(
                            key: ref.key,
                            name: ref.name,
                            mime: ref.type.mime,
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                error
                                    .toString()
                                    .replaceFirst('PlatformException', '')
                                    .replaceFirst('FormatException: ', ''),
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.open_in_new),
                      label: Text(
                        ref.type.category == AttachmentCategory.audio
                            ? 'Ascolta'
                            : 'Apri',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        try {
                          await AttachmentBridge.share(
                            key: ref.key,
                            name: ref.name,
                            mime: ref.type.mime,
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      },
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Condividi'),
                    ),
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () {
                              Navigator.pop(context);
                              _removeAttachment(ref.key);
                            },
                      icon: const Icon(Icons.link_off),
                      label: const Text('Rimuovi collegamento'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  void _removeAttachment(String key) {
    final body = Attachments.remove(_body.text, key);
    setState(() {
      _body.text = body;
      _body.selection = TextSelection.collapsed(offset: body.length);
      _dirty = true;
      if (_blocksInitialized) {
        _blocks = BlockEditorCodec.parse(_id, body);
      }
    });
  }

  void _applyKnowledgeEdit(MarkdownSelectionEdit edit) {
    _body.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection(
        baseOffset: edit.start.clamp(0, edit.text.length).toInt(),
        extentOffset: edit.end.clamp(0, edit.text.length).toInt(),
      ),
    );
    setState(() {
      _dirty = true;
      _error = null;
      if (_blocksInitialized) {
        _blocks = BlockEditorCodec.parse(_id, edit.text);
      }
    });
  }

  Future<void> _openLinkedNote(String id) async {
    Note? target;
    for (final note in widget.allNotes) {
      if (note.id == id && !note.isDeleted && !note.isTask && !note.isVisual) {
        target = note;
        break;
      }
    }
    if (target == null) {
      setState(() => _error = 'Nota collegata non disponibile.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          note: target,
          collections: widget.collections,
          allNotes: widget.allNotes,
        ),
      ),
    );
  }

  Future<void> _saveAsTemplate() async {
    if (_saving || _readOnlyVisual) return;
    try {
      final content = PersonalTemplates.capture(
        _title.text,
        _body.text,
        _tags,
      );
      await ref.read(workspaceProvider.notifier).createTemplate(content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modello creato: lo trovi in Crea → Modelli.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('FormatException: ', '');
        });
      }
    }
  }

  void _applyMarkdown(MarkdownAction action) {
    final selection = _body.selection;
    final start = selection.isValid ? selection.start : _body.text.length;
    final end = selection.isValid ? selection.end : start;
    try {
      final edit = MarkdownEditing.apply(
        _body.text,
        start,
        end,
        action,
      );
      _body.value = TextEditingValue(
        text: edit.text,
        selection: TextSelection(
          baseOffset: edit.start,
          extentOffset: edit.end,
        ),
      );
      _changed();
      setState(() => _error = null);
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  Future<void> _insertLink() async {
    final selection = _body.selection;
    final start = selection.isValid ? selection.start : _body.text.length;
    final end = selection.isValid ? selection.end : start;
    final a = start < end ? start : end;
    final b = start < end ? end : start;
    final selected = _body.text.substring(
      a.clamp(0, _body.text.length).toInt(),
      b.clamp(0, _body.text.length).toInt(),
    );
    final label = TextEditingController(text: selected);
    final url = TextEditingController(text: 'https://');
    String? error;

    final edit = await showDialog<MarkdownEdit>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Inserisci link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Testo'),
              ),
              TextField(
                controller: url,
                decoration:
                    const InputDecoration(labelText: 'Indirizzo https://'),
              ),
              if (error != null)
                Text(
                  error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(
                    context,
                    MarkdownEditing.link(
                      _body.text,
                      start,
                      end,
                      label.text,
                      url.text,
                    ),
                  );
                } catch (e) {
                  setLocal(() {
                    error =
                        e.toString().replaceFirst('FormatException: ', '');
                  });
                }
              },
              child: const Text('Inserisci'),
            ),
          ],
        ),
      ),
    );

    label.dispose();
    url.dispose();
    if (edit == null || !mounted) return;
    _body.value = TextEditingValue(
      text: edit.text,
      selection: TextSelection.collapsed(offset: edit.end),
    );
    _changed();
    setState(() => _error = null);
  }

  Future<void> _addChecklistItem() async {
    final controller = TextEditingController();
    String? error;
    final body = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Nuova attività'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Testo'),
                onSubmitted: (_) {},
              ),
              if (error != null)
                Text(
                  error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(
                    context,
                    Checklist.append(_body.text, controller.text),
                  );
                } catch (e) {
                  setLocal(() {
                    error =
                        e.toString().replaceFirst('FormatException: ', '');
                  });
                }
              },
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (body == null || !mounted) return;
    _body.text = body;
    _body.selection = TextSelection.collapsed(offset: body.length);
    _changed();
    setState(() => _error = null);
  }

  Future<void> _chooseCollection() async {
    final selected = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Raccolta'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: const ListTile(
              leading: Icon(Icons.inbox),
              title: Text('Inbox'),
            ),
          ),
          ...widget.collections.map(
            (collection) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, collection.id),
              child: ListTile(
                leading: const Icon(Icons.folder),
                title: Text(collection.name),
                trailing: collection.id == _collectionId
                    ? const Icon(Icons.check)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted || selected == null) return;
    setState(() {
      _collectionId = selected.isEmpty ? null : selected;
      _dirty = true;
    });
  }

  Future<void> _chooseDiaryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _diaryDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
    );
    if (picked == null || !mounted) return;
    try {
      final next = Diary.datedTags(_tags, picked);
      NoteTags.normalize(next);
      setState(() {
        _tags = next;
        _dirty = true;
        _error = null;
      });
    } catch (error) {
      setState(() {
        _error = error.toString().replaceFirst('FormatException: ', '');
      });
    }
  }

  void _removeDiaryDate() {
    final next = Diary.datedTags(_tags, null);
    setState(() {
      _tags = next;
      _dirty = true;
    });
  }

  Future<void> _editTags() async {
    var tags = Diary.userTags(_tags);
    final date = _diaryDate;
    final controller = TextEditingController();
    String? error;

    final updated = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Tag della nota'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Fino a 20 tag complessivi, incluso il collegamento al Diario.',
                  ),
                  const SizedBox(height: 8),
                  ...tags.map(
                    (tag) => ListTile(
                      dense: true,
                      title: Text('#$tag'),
                      trailing: IconButton(
                        onPressed: () => setLocal(
                          () => tags =
                              tags.where((value) => value != tag).toList(),
                        ),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Nuovo tag, es. lavoro',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () {
                      try {
                        var next = NoteTags.add(tags, controller.text);
                        next = Diary.datedTags(next, date);
                        NoteTags.normalize(next);
                        setLocal(() {
                          tags = Diary.userTags(next);
                          controller.clear();
                          error = null;
                        });
                      } catch (e) {
                        setLocal(() {
                          error = e
                              .toString()
                              .replaceFirst('FormatException: ', '');
                        });
                      }
                    },
                    child: const Text('Aggiungi'),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                Diary.datedTags(tags, date),
              ),
              child: const Text('Chiudi'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    if (updated == null || !mounted) return;
    setState(() {
      _tags = updated;
      _dirty = true;
    });
  }

  Future<void> _history() async {
    if (_dirty) {
      setState(() {
        _error =
            'Salva o riapri la nota prima di ripristinare una versione precedente.';
      });
      return;
    }
    final rows =
        await ref.read(databaseProvider).loadHistory(_id);
    if (!mounted) return;

    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna versione precedente.')),
      );
      return;
    }

    final row = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Cronologia'),
        children: rows
            .map(
              (item) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, item),
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                    (item['title']?.toString().isNotEmpty ?? false)
                        ? item['title'].toString()
                        : 'Senza titolo',
                  ),
                  subtitle: Text(
                    editorialDate(
                      (item['savedAt'] as num?)?.toInt() ?? 0,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (row == null || !mounted) return;

    List<String> tags = const [];
    try {
      tags = (jsonDecode(row['tagsJson']?.toString() ?? '[]') as List)
          .map((e) => e.toString())
          .toList();
    } catch (_) {}

    setState(() {
      _title.text = row['title']?.toString() ?? '';
      _body.text = row['body']?.toString() ?? '';
      _collectionId = row['collectionId']?.toString();
      _tags = tags;
      _dirty = true;
      _mode = Checklist.hasMarker(_body.text)
          ? _EditorMode.checklist
          : _EditorMode.text;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_readOnlyVisual) {
      return Scaffold(
        appBar: AppBar(
          title: const EditorialAppTitle(
            'Documento visuale',
            eyebrow: 'SKETCHBOOK / WHITEBOARD',
          ),
        ),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Questo documento usa il formato visuale della 0.25. '
            'Non viene aperto nell’editor di testo per evitare modifiche al payload. '
            'Il relativo editor Flutter viene portato nello step visuale.',
          ),
        ),
      );
    }

    final collectionName = widget.collections
        .where((item) => item.id == _collectionId)
        .map((item) => item.name)
        .firstOrNull;
    final visibleTags = Diary.userTags(_tags);
    final checklist = Checklist.parse(_body.text);

    return Scaffold(
      appBar: AppBar(
        title: const EditorialAppTitle(
          'La tua pagina',
          eyebrow: 'IL TUO TACCUINO',
        ),
        actions: [
          IconButton(
            onPressed: _saving ? null : _saveAsTemplate,
            tooltip: 'Salva come modello',
            icon: const Icon(Icons.dashboard_customize),
          ),
          IconButton(
            onPressed: _saving ? null : _history,
            tooltip: 'Cronologia',
            icon: const Icon(Icons.history),
          ),
          FilledButton(
            onPressed: _saving || _recording ? null : _save,
            child: Text(_saving ? 'Salvataggio…' : 'Salva'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_saving) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
                children: [
                  TextField(
                    controller: _title,
                    onChanged: (_) => _changed(),
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontFamily: 'serif'),
                    decoration: const InputDecoration(
                      hintText: 'Titolo',
                      border: InputBorder.none,
                      filled: false,
                    ),
                    maxLines: null,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.folder, size: 18),
                        label: Text(collectionName ?? 'Inbox'),
                        onPressed: _saving ? null : _chooseCollection,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.sell, size: 18),
                        label: Text(
                          visibleTags.isEmpty
                              ? 'Aggiungi tag'
                              : 'Tag (${visibleTags.length})',
                        ),
                        onPressed: _saving ? null : _editTags,
                      ),
                      ActionChip(
                        avatar:
                            const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          _diaryDate == null
                              ? 'Giorno'
                              : dateKey(_diaryDate!),
                        ),
                        onPressed: _saving ? null : _chooseDiaryDate,
                      ),
                      if (_diaryDate != null)
                        IconButton(
                          onPressed:
                              _saving ? null : _removeDiaryDate,
                          tooltip: 'Rimuovi dal Diario',
                          icon: const Icon(Icons.event_busy),
                        ),
                    ],
                  ),
                  if (visibleTags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      visibleTags.map((tag) => '#$tag').join(' '),
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            _saving || _recording ? null : _attachFiles,
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Allega'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _saving || _recording ? null : _takePhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Foto'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _toggleRecording,
                        icon: Icon(
                          _recording ? Icons.stop_circle : Icons.mic_none,
                        ),
                        label: Text(
                          _recording ? 'Termina' : 'Registra',
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed:
                            _saving || _recording ? null : _smartCapture,
                        icon: const Icon(Icons.document_scanner),
                        label: const Text('Smart Capture'),
                      ),
                      Text(
                        '${Attachments.refs(_body.text).length}/20 allegati',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      if (_recording)
                        Text(
                          'Registrazione in corso · massimo 5 minuti',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                    ],
                  ),
                  if (Attachments.refs(_body.text).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...Attachments.refs(_body.text).map(
                      (ref) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          ref.type.category == AttachmentCategory.image
                              ? Icons.image
                              : ref.type.category == AttachmentCategory.audio
                                  ? Icons.audio_file
                                  : Icons.insert_drive_file,
                        ),
                        title: Text(ref.name),
                        subtitle: Text(ref.type.mime),
                        onTap: _saving ? null : () => _attachmentPanel(ref),
                        trailing: IconButton(
                          onPressed:
                              _saving ? null : () => _attachmentPanel(ref),
                          icon: const Icon(Icons.more_horiz),
                          tooltip: 'Apri allegato',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        selected: _mode == _EditorMode.text,
                        onSelected: _saving
                            ? null
                            : (_) =>
                                setState(() => _mode = _EditorMode.text),
                        label: const Text('Testo'),
                      ),
                      ChoiceChip(
                        selected: _mode == _EditorMode.preview,
                        onSelected: _saving
                            ? null
                            : (_) =>
                                setState(() => _mode = _EditorMode.preview),
                        label: const Text('Anteprima'),
                      ),
                      ChoiceChip(
                        selected: _mode == _EditorMode.blocks,
                        onSelected: _saving
                            ? null
                            : (_) => _enableBlocks(),
                        label: const Text('Blocchi'),
                      ),
                      ChoiceChip(
                        selected: _mode == _EditorMode.checklist,
                        onSelected: _saving
                            ? null
                            : (_) => setState(
                                () => _mode = _EditorMode.checklist,
                              ),
                        label: Text('Checklist (${checklist.length})'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_mode == _EditorMode.text) ...[
                    _MarkdownToolbar(
                      enabled: !_saving,
                      onAction: _applyMarkdown,
                      onLink: _insertLink,
                    ),
                    KnowledgeToolsBar(
                      text: _body.text,
                      selection: _body.selection,
                      notes: widget.allNotes,
                      currentNoteId: _id,
                      enabled: !_saving,
                      onEdit: _applyKnowledgeEdit,
                      onOpenNote: _openLinkedNote,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _body,
                      onChanged: (_) {
                        _changed();
                        setState(() {});
                      },
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: const InputDecoration(
                        hintText: 'Comincia da un pensiero…',
                        border: InputBorder.none,
                        filled: false,
                      ),
                      minLines: 18,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                    ),
                  ] else if (_mode == _EditorMode.preview) ...[
                    Text(
                      'Anteprima di lettura · le immagini esterne non vengono caricate automaticamente.',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 8),
                    if (_body.text.length > 200000)
                      const Text(
                        'Questa nota è troppo lunga per l’anteprima. '
                        'Il testo completo resta disponibile in Testo.',
                      )
                    else
                      MarkdownBody(
                        data: _body.text,
                        selectable: true,
                        onTapLink: (text, href, title) {
                          if (href == null) return;
                          final id = Knowledge.targetId(href);
                          if (id != null) {
                            _openLinkedNote(id);
                          }
                        },
                      ),
                  ] else if (_mode == _EditorMode.blocks) ...[
                    UniversalBlockEditor(
                      noteId: _id,
                      blocks: _blocks,
                      enabled: !_saving,
                      onChanged: _blocksChanged,
                      onCreateDrawing: _createDrawing,
                      onOpenDrawing: _openVisualById,
                      onCreateWhiteboard: _createWhiteboard,
                      onOpenWhiteboard: _openVisualById,
                    ),
                  ] else ...[
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _saving ? null : _addChecklistItem,
                          icon: const Icon(Icons.add_task),
                          label: const Text('Aggiungi attività'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(
                                  () => _mode = _EditorMode.text,
                                ),
                          child: const Text('Modifica Markdown'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (checklist.isEmpty)
                      const Text('Aggiungi la prima attività.')
                    else
                      ...checklist.map(
                        (item) => Padding(
                          padding: EdgeInsets.only(
                            left: item.depth * 20.0,
                            bottom: 4,
                          ),
                          child: CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: item.completed,
                            controlAffinity:
                                ListTileControlAffinity.leading,
                            title: Text(item.label),
                            onChanged: _saving
                                ? null
                                : (value) {
                                    try {
                                      final body =
                                          Checklist.setCompleted(
                                        _body.text,
                                        item.lineIndex,
                                        value ?? false,
                                      );
                                      _body.text = body;
                                      _changed();
                                      setState(() => _error = null);
                                    } catch (error) {
                                      setState(() {
                                        _error = error
                                            .toString()
                                            .replaceFirst(
                                              'FormatException: ',
                                              '',
                                            );
                                      });
                                    }
                                  },
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkdownToolbar extends StatelessWidget {
  const _MarkdownToolbar({
    required this.enabled,
    required this.onAction,
    required this.onLink,
  });

  final bool enabled;
  final ValueChanged<MarkdownAction> onAction;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              _button(
                Icons.format_bold,
                'Grassetto',
                MarkdownAction.bold,
              ),
              _button(
                Icons.format_italic,
                'Corsivo',
                MarkdownAction.italic,
              ),
              _button(Icons.title, 'Titolo', MarkdownAction.heading),
              _button(
                Icons.format_list_bulleted,
                'Elenco',
                MarkdownAction.bullet,
              ),
              _button(
                Icons.format_list_numbered,
                'Elenco numerato',
                MarkdownAction.numbered,
              ),
              _button(
                Icons.format_quote,
                'Citazione',
                MarkdownAction.quote,
              ),
              _button(Icons.code, 'Codice', MarkdownAction.code),
              _button(
                Icons.developer_mode,
                'Blocco codice',
                MarkdownAction.codeBlock,
              ),
              IconButton(
                onPressed: enabled ? onLink : null,
                tooltip: 'Inserisci link',
                icon: const Icon(Icons.link),
              ),
            ],
          ),
        ),
      );

  Widget _button(
    IconData icon,
    String tooltip,
    MarkdownAction action,
  ) =>
      IconButton(
        onPressed: enabled ? () => onAction(action) : null,
        tooltip: tooltip,
        icon: Icon(icon),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
