import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/note.dart';
import '../state/workspace_controller.dart';
import '../widgets/editorial.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({this.note, super.key});
  final Note? note;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note?.title ?? '');
    _body = TextEditingController(text: widget.note?.body ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = widget.note;
    final note = old == null
        ? Note(
            id: const Uuid().v4(),
            title: _title.text,
            body: _body.text,
            favorite: false,
            createdAt: now,
            updatedAt: now,
            pinned: false,
            archived: false,
            tags: const [],
          )
        : old.copyWith(title: _title.text, body: _body.text, updatedAt: now);
    await ref.read(workspaceProvider.notifier).save(note);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const EditorialAppTitle('La tua pagina', eyebrow: 'IL TUO TACCUINO'),
          actions: [
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Salvataggio…' : 'Salva')),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
            children: [
              TextField(
                controller: _title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontFamily: 'serif'),
                decoration: const InputDecoration(hintText: 'Titolo', border: InputBorder.none, filled: false),
                maxLines: null,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _body,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: const InputDecoration(hintText: 'Inizia a scrivere…', border: InputBorder.none, filled: false),
                minLines: 18,
                maxLines: null,
                keyboardType: TextInputType.multiline,
              ),
            ],
          ),
        ),
      );
}
