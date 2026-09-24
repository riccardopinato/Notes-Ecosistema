import 'package:flutter/material.dart';

import '../domain/blocks.dart';

class UniversalBlockEditor extends StatelessWidget {
  const UniversalBlockEditor({
    required this.noteId,
    required this.blocks,
    required this.enabled,
    required this.onChanged,
    this.onCreateDrawing,
    this.onOpenDrawing,
    this.onCreateWhiteboard,
    this.onOpenWhiteboard,
    super.key,
  });

  final String noteId;
  final List<ContentBlock> blocks;
  final bool enabled;
  final ValueChanged<List<ContentBlock>> onChanged;
  final ValueChanged<String>? onCreateDrawing;
  final ValueChanged<String>? onOpenDrawing;
  final ValueChanged<String>? onCreateWhiteboard;
  final ValueChanged<String>? onOpenWhiteboard;

  void _commit(List<ContentBlock> next) {
    onChanged(BlockEditorCodec.canonicalize(noteId, next));
  }

  void _add(ContentBlockType type, [int? index]) {
    final target = index ?? blocks.length;
    final next = [...blocks];
    next.insert(
      target.clamp(0, next.length).toInt(),
      BlockEditorCodec.newBlock(noteId, type, target),
    );
    _commit(next);
  }

  void _replace(int index, ContentBlock nextBlock) {
    final next = [...blocks];
    next[index] = nextBlock;
    _commit(next);
  }

  void _delete(int index) {
    final next = [...blocks]..removeAt(index);
    _commit(next);
  }

  void _move(int index, int delta) {
    final to = (index + delta).clamp(0, blocks.length - 1).toInt();
    if (to == index) return;
    final next = [...blocks];
    final moved = next.removeAt(index);
    next.insert(to, moved);
    _commit(next);
  }

  void _duplicate(int index) {
    final source = blocks[index];
    final copy = BlockEditorCodec.newBlock(
      noteId,
      source.type,
      index + 1,
      text: source.text,
    ).copyWith(
      checked: source.checked,
      metadataJson: source.metadataJson,
    );
    final next = [...blocks]..insert(index + 1, copy);
    _commit(next);
  }

  @override
  Widget build(BuildContext context) {
    final source = blocks.isEmpty
        ? [
            BlockEditorCodec.newBlock(
              noteId,
              ContentBlockType.text,
              0,
            ),
          ]
        : blocks;

    if (blocks.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (blocks.isEmpty) _commit(source);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${source.length} ${source.length == 1 ? 'blocco' : 'blocchi'}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const Spacer(),
            _AddBlockButton(
              enabled: enabled,
              onAdd: _add,
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(source.length, (index) {
          final block = source[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _BlockCard(
              block: block,
              index: index,
              total: source.length,
              enabled: enabled,
              onText: (text) => _replace(
                index,
                block.copyWith(
                  text: text,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                ),
              ),
              onChecked: (checked) => _replace(
                index,
                block.copyWith(
                  checked: checked,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                ),
              ),
              onType: (type) => _replace(
                index,
                BlockEditorCodec.changeType(block, type).copyWith(
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                ),
              ),
              onHeadingLevel: (level) => _replace(
                index,
                BlockEditorCodec.withHeadingLevel(block, level).copyWith(
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                ),
              ),
              onAddAfter: (type) => _add(type, index + 1),
              onDuplicate: () => _duplicate(index),
              onDelete: () => _delete(index),
              onMoveUp: index == 0 ? null : () => _move(index, -1),
              onMoveDown:
                  index == source.length - 1 ? null : () => _move(index, 1),
              onCreateDrawing: onCreateDrawing == null
                  ? null
                  : () => onCreateDrawing!(block.id),
              onOpenDrawing: () {
                final id = BlockEditorCodec.sketchId(block);
                if (id != null) onOpenDrawing?.call(id);
              },
              onCreateWhiteboard: onCreateWhiteboard == null
                  ? null
                  : () => onCreateWhiteboard!(block.id),
              onOpenWhiteboard: () {
                final id = BlockEditorCodec.whiteboardId(block);
                if (id != null) onOpenWhiteboard?.call(id);
              },
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: enabled ? () => _add(ContentBlockType.text) : null,
          icon: const Icon(Icons.add),
          label: const Text('Aggiungi blocco'),
        ),
      ],
    );
  }
}

class _BlockCard extends StatefulWidget {
  const _BlockCard({
    required this.block,
    required this.index,
    required this.total,
    required this.enabled,
    required this.onText,
    required this.onChecked,
    required this.onType,
    required this.onHeadingLevel,
    required this.onAddAfter,
    required this.onDuplicate,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onCreateDrawing,
    required this.onOpenDrawing,
    required this.onCreateWhiteboard,
    required this.onOpenWhiteboard,
  });

  final ContentBlock block;
  final int index;
  final int total;
  final bool enabled;
  final ValueChanged<String> onText;
  final ValueChanged<bool> onChecked;
  final ValueChanged<ContentBlockType> onType;
  final ValueChanged<int> onHeadingLevel;
  final ValueChanged<ContentBlockType> onAddAfter;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onCreateDrawing;
  final VoidCallback onOpenDrawing;
  final VoidCallback? onCreateWhiteboard;
  final VoidCallback onOpenWhiteboard;

  @override
  State<_BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends State<_BlockCard> {
  late final TextEditingController _controller;
  bool _slashMenu = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.text);
  }

  @override
  void didUpdateWidget(covariant _BlockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.text != widget.block.text &&
        _controller.text != widget.block.text) {
      _controller.value = TextEditingValue(
        text: widget.block.text,
        selection: TextSelection.collapsed(
          offset: widget.block.text.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _textChanged(String value) {
    if ((widget.block.type == ContentBlockType.text ||
            widget.block.type == ContentBlockType.markdown) &&
        value.trimLeft().startsWith('/')) {
      setState(() => _slashMenu = true);
    } else if (_slashMenu) {
      setState(() => _slashMenu = false);
    }
    widget.onText(value);
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final label = _blockLabel(block);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(label),
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.enabled ? widget.onMoveUp : null,
                  tooltip: 'Sposta su',
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  onPressed: widget.enabled ? widget.onMoveDown : null,
                  tooltip: 'Sposta giù',
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                PopupMenuButton<String>(
                  enabled: widget.enabled,
                  onSelected: (action) {
                    if (action == 'duplicate') {
                      widget.onDuplicate();
                    } else if (action == 'delete') {
                      widget.onDelete();
                    } else if (action == 'add') {
                      _showAddAfter(context);
                    } else if (action.startsWith('type:')) {
                      final name = action.substring(5);
                      final type = ContentBlockType.values.firstWhere(
                        (value) => value.name == name,
                      );
                      widget.onType(type);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'add',
                      child: Text('Aggiungi dopo'),
                    ),
                    const PopupMenuItem(
                      value: 'duplicate',
                      child: Text('Duplica'),
                    ),
                    const PopupMenuDivider(),
                    ..._commands.map(
                      (command) => PopupMenuItem(
                        value: 'type:${command.type.name}',
                        child: Text('Trasforma · ${command.label}'),
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Elimina blocco'),
                    ),
                  ],
                ),
              ],
            ),
            if (block.type == ContentBlockType.divider)
              const Divider(height: 32)
            else if (block.type == ContentBlockType.checklist ||
                block.type == ContentBlockType.task)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: block.checked ?? false,
                    onChanged: widget.enabled
                        ? (value) => widget.onChecked(value ?? false)
                        : null,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: widget.enabled,
                      onChanged: _textChanged,
                      decoration: const InputDecoration(
                        hintText: 'Attività…',
                      ),
                      maxLines: null,
                    ),
                  ),
                ],
              )
            else if (block.type == ContentBlockType.heading)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('H1')),
                      ButtonSegment(value: 2, label: Text('H2')),
                      ButtonSegment(value: 3, label: Text('H3')),
                    ],
                    selected: {BlockEditorCodec.headingLevel(block)},
                    onSelectionChanged: widget.enabled
                        ? (value) => widget.onHeadingLevel(value.first)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _controller,
                    enabled: widget.enabled,
                    onChanged: _textChanged,
                    style: Theme.of(context).textTheme.headlineSmall,
                    decoration: const InputDecoration(hintText: 'Titolo…'),
                    maxLines: null,
                  ),
                ],
              )
            else if (block.type == ContentBlockType.code)
              TextField(
                controller: _controller,
                enabled: widget.enabled,
                onChanged: _textChanged,
                minLines: 3,
                maxLines: null,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(hintText: 'Codice…'),
              )
            else if (block.type == ContentBlockType.quote ||
                block.type == ContentBlockType.callout)
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      width: 4,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                padding: const EdgeInsets.only(left: 12),
                child: TextField(
                  controller: _controller,
                  enabled: widget.enabled,
                  onChanged: _textChanged,
                  minLines: 2,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: block.type == ContentBlockType.quote
                        ? 'Citazione…'
                        : 'Nota in evidenza…',
                  ),
                ),
              )
            else if (block.type == ContentBlockType.drawing)
              _VisualBlock(
                icon: Icons.draw,
                title: block.text.trim().isEmpty ? 'Disegno' : block.text,
                linked: BlockEditorCodec.sketchId(block) != null,
                linkedLabel: 'Sketchbook',
                createLabel: 'Crea disegno',
                openLabel: 'Apri disegno',
                enabled: widget.enabled,
                onCreate: widget.onCreateDrawing,
                onOpen: widget.onOpenDrawing,
                controller: _controller,
                onText: _textChanged,
              )
            else if (block.type == ContentBlockType.whiteboard)
              _VisualBlock(
                icon: Icons.dashboard,
                title: block.text.trim().isEmpty ? 'Lavagna' : block.text,
                linked: BlockEditorCodec.whiteboardId(block) != null,
                linkedLabel: 'Whiteboard',
                createLabel: 'Crea lavagna',
                openLabel: 'Apri lavagna',
                enabled: widget.enabled,
                onCreate: widget.onCreateWhiteboard,
                onOpen: widget.onOpenWhiteboard,
                controller: _controller,
                onText: _textChanged,
              )
            else if (block.type == ContentBlockType.image ||
                block.type == ContentBlockType.audio ||
                block.type == ContentBlockType.file)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  block.type == ContentBlockType.image
                      ? Icons.image
                      : block.type == ContentBlockType.audio
                          ? Icons.audio_file
                          : Icons.attach_file,
                ),
                title: Text(_blockLabel(block)),
                subtitle: Text(
                  block.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              Stack(
                children: [
                  TextField(
                    controller: _controller,
                    enabled: widget.enabled,
                    onChanged: _textChanged,
                    minLines: block.type == ContentBlockType.markdown ? 2 : 1,
                    maxLines: null,
                    style: block.type == ContentBlockType.markdown
                        ? const TextStyle(fontFamily: 'monospace')
                        : null,
                    decoration: InputDecoration(
                      hintText: widget.index == 0
                          ? 'Scrivi oppure digita / per i blocchi…'
                          : 'Scrivi…',
                    ),
                  ),
                  Positioned(
                    left: 4,
                    top: 48,
                    child: PopupMenuButton<ContentBlockType>(
                      enabled: _slashMenu && widget.enabled,
                      tooltip: 'Comandi blocco',
                      onOpened: () {},
                      onSelected: (type) {
                        _controller.clear();
                        widget.onText('');
                        widget.onType(type);
                        setState(() => _slashMenu = false);
                      },
                      itemBuilder: (_) => _commands
                          .map(
                            (command) => PopupMenuItem(
                              value: command.type,
                              child: ListTile(
                                dense: true,
                                title: Text('/${command.label.toLowerCase()}'),
                                subtitle: Text(command.hint),
                              ),
                            ),
                          )
                          .toList(),
                      child: _slashMenu
                          ? const SizedBox(width: 1, height: 1)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddAfter(BuildContext context) async {
    final type = await showModalBottomSheet<ContentBlockType>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: _commands
              .map(
                (command) => ListTile(
                  title: Text(command.label),
                  subtitle: Text(command.hint),
                  onTap: () => Navigator.pop(context, command.type),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (type != null) widget.onAddAfter(type);
  }
}

class _VisualBlock extends StatelessWidget {
  const _VisualBlock({
    required this.icon,
    required this.title,
    required this.linked,
    required this.linkedLabel,
    required this.createLabel,
    required this.openLabel,
    required this.enabled,
    required this.onCreate,
    required this.onOpen,
    required this.controller,
    required this.onText,
  });

  final IconData icon;
  final String title;
  final bool linked;
  final String linkedLabel;
  final String createLabel;
  final String openLabel;
  final bool enabled;
  final VoidCallback? onCreate;
  final VoidCallback onOpen;
  final TextEditingController controller;
  final ValueChanged<String> onText;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (linked) Chip(label: Text(linkedLabel)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              enabled: enabled,
              onChanged: onText,
              decoration: const InputDecoration(labelText: 'Titolo'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: linked
                  ? OutlinedButton(
                      onPressed: enabled ? onOpen : null,
                      child: Text(openLabel),
                    )
                  : FilledButton(
                      onPressed: enabled ? onCreate : null,
                      child: Text(createLabel),
                    ),
            ),
          ],
        ),
      );
}

class _AddBlockButton extends StatelessWidget {
  const _AddBlockButton({
    required this.enabled,
    required this.onAdd,
  });

  final bool enabled;
  final ValueChanged<ContentBlockType> onAdd;

  @override
  Widget build(BuildContext context) => PopupMenuButton<ContentBlockType>(
        enabled: enabled,
        tooltip: 'Aggiungi blocco',
        onSelected: onAdd,
        itemBuilder: (_) => _commands
            .map(
              (command) => PopupMenuItem(
                value: command.type,
                child: ListTile(
                  dense: true,
                  title: Text(command.label),
                  subtitle: Text(command.hint),
                ),
              ),
            )
            .toList(),
        child: const Chip(
          avatar: Icon(Icons.add, size: 18),
          label: Text('Blocco'),
        ),
      );
}

class _BlockCommand {
  const _BlockCommand(this.label, this.hint, this.type);
  final String label;
  final String hint;
  final ContentBlockType type;
}

const _commands = [
  _BlockCommand('Testo', 'Paragrafo normale', ContentBlockType.text),
  _BlockCommand('Titolo', 'Intestazione H1-H3', ContentBlockType.heading),
  _BlockCommand(
    'Checklist',
    'Voce da spuntare',
    ContentBlockType.checklist,
  ),
  _BlockCommand('Citazione', 'Citazione o estratto', ContentBlockType.quote),
  _BlockCommand('Codice', 'Blocco monospazio', ContentBlockType.code),
  _BlockCommand(
    'Callout',
    'Nota in evidenza',
    ContentBlockType.callout,
  ),
  _BlockCommand(
    'Separatore',
    'Linea di separazione',
    ContentBlockType.divider,
  ),
  _BlockCommand(
    'Disegno',
    'Sketchbook collegato alla nota',
    ContentBlockType.drawing,
  ),
  _BlockCommand(
    'Lavagna',
    'Whiteboard o mind map collegata',
    ContentBlockType.whiteboard,
  ),
  _BlockCommand(
    'Markdown',
    'Contenuto Markdown libero',
    ContentBlockType.markdown,
  ),
];

String _blockLabel(ContentBlock block) => switch (block.type) {
      ContentBlockType.text => 'TESTO',
      ContentBlockType.markdown => 'MARKDOWN',
      ContentBlockType.heading => 'H${BlockEditorCodec.headingLevel(block)}',
      ContentBlockType.checklist => 'CHECKLIST',
      ContentBlockType.task => 'ATTIVITÀ',
      ContentBlockType.image => 'IMMAGINE',
      ContentBlockType.audio => 'AUDIO',
      ContentBlockType.file => 'FILE',
      ContentBlockType.drawing => 'DISEGNO',
      ContentBlockType.whiteboard => 'LAVAGNA',
      ContentBlockType.bookmark => 'BOOKMARK',
      ContentBlockType.table => 'TABELLA',
      ContentBlockType.code => 'CODICE',
      ContentBlockType.quote => 'CITAZIONE',
      ContentBlockType.callout => 'CALLOUT',
      ContentBlockType.divider => 'SEPARATORE',
    };
