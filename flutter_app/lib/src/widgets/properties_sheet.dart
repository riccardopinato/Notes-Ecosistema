import 'package:flutter/material.dart';

import '../domain/properties.dart';

Future<Map<String, Object?>?> showPropertiesSheet({
  required BuildContext context,
  required List<PropertyDefinition> definitions,
  required Map<String, Object?> values,
  required Future<PropertyDefinition> Function(
    String name,
    NotePropertyType type,
    List<String> options,
  ) onCreateDefinition,
}) =>
    showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PropertiesSheet(
        definitions: definitions,
        values: values,
        onCreateDefinition: onCreateDefinition,
      ),
    );

class PropertiesSheet extends StatefulWidget {
  const PropertiesSheet({
    required this.definitions,
    required this.values,
    required this.onCreateDefinition,
    super.key,
  });

  final List<PropertyDefinition> definitions;
  final Map<String, Object?> values;
  final Future<PropertyDefinition> Function(
    String name,
    NotePropertyType type,
    List<String> options,
  ) onCreateDefinition;

  @override
  State<PropertiesSheet> createState() => _PropertiesSheetState();
}

class _PropertiesSheetState extends State<PropertiesSheet> {
  late List<PropertyDefinition> _definitions;
  late Map<String, Object?> _values;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _definitions = List<PropertyDefinition>.from(widget.definitions);
    _values = Map<String, Object?>.from(widget.values);
  }

  Future<void> _addDefinition() async {
    final name = TextEditingController();
    final options = TextEditingController();
    var type = NotePropertyType.text;
    String? error;

    final result = await showDialog<_NewProperty>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, local) {
          final needsOptions = type == NotePropertyType.select ||
              type == NotePropertyType.multiSelect ||
              type == NotePropertyType.status;
          return AlertDialog(
            title: const Text('Nuova proprietà'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Nome'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<NotePropertyType>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Tipo'),
                      items: NotePropertyType.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) =>
                          local(() => type = value ?? NotePropertyType.text),
                    ),
                    if (needsOptions) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: options,
                        decoration: const InputDecoration(
                          labelText: 'Opzioni separate da virgola',
                          hintText: 'Da fare, In corso, Fatto',
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
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
                  final parsed = needsOptions
                      ? options.text
                          .split(',')
                          .map((value) => value.trim())
                          .where((value) => value.isNotEmpty)
                          .toList(growable: false)
                      : const <String>[];
                  try {
                    final candidate = PropertyDefinition(
                      id: 'pending',
                      name: name.text.trim(),
                      type: type,
                      options: parsed,
                      createdAt: 0,
                      updatedAt: 0,
                    );
                    PropertyRules.validateDefinition(candidate);
                    Navigator.pop(
                      context,
                      _NewProperty(candidate.name, candidate.type, parsed),
                    );
                  } catch (e) {
                    local(
                      () => error =
                          e.toString().replaceFirst('FormatException: ', ''),
                    );
                  }
                },
                child: const Text('Crea'),
              ),
            ],
          );
        },
      ),
    );

    name.dispose();
    options.dispose();
    if (result == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.onCreateDefinition(
        result.name,
        result.type,
        result.options,
      );
      if (!mounted) return;
      setState(() => _definitions = [..._definitions, created]..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          ));
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e.toString().replaceFirst('FormatException: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(PropertyDefinition definition) async {
    final current = _values[definition.id];

    switch (definition.type) {
      case NotePropertyType.checkbox:
        setState(() => _values[definition.id] = current != true);
        return;
      case NotePropertyType.date:
        final parsed =
            current is String ? DateTime.tryParse(current) : DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: parsed ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime(2200, 12, 31),
        );
        if (picked != null && mounted) {
          setState(
            () => _values[definition.id] =
                '${picked.year.toString().padLeft(4, '0')}-'
                    '${picked.month.toString().padLeft(2, '0')}-'
                    '${picked.day.toString().padLeft(2, '0')}',
          );
        }
        return;
      case NotePropertyType.select:
      case NotePropertyType.status:
        final selected = await showDialog<String?>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(definition.name),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, ''),
                child: const Text('Nessun valore'),
              ),
              ...definition.options.map(
                (option) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, option),
                  child: Row(
                    children: [
                      Expanded(child: Text(option)),
                      if (current == option) const Icon(Icons.check),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
        if (selected != null && mounted) {
          setState(() {
            if (selected.isEmpty) {
              _values.remove(definition.id);
            } else {
              _values[definition.id] = selected;
            }
          });
        }
        return;
      case NotePropertyType.multiSelect:
        final chosen = {
          if (current is List) ...current.map((value) => value.toString()),
        };
        final selected = await showDialog<Set<String>>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, local) => AlertDialog(
              title: Text(definition.name),
              content: SizedBox(
                width: 480,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: definition.options
                      .map(
                        (option) => FilterChip(
                          label: Text(option),
                          selected: chosen.contains(option),
                          onSelected: (enabled) => local(() {
                            if (enabled) {
                              chosen.add(option);
                            } else {
                              chosen.remove(option);
                            }
                          }),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, chosen),
                  child: const Text('Applica'),
                ),
              ],
            ),
          ),
        );
        if (selected != null && mounted) {
          setState(() {
            if (selected.isEmpty) {
              _values.remove(definition.id);
            } else {
              _values[definition.id] = selected.toList(growable: false);
            }
          });
        }
        return;
      case NotePropertyType.text:
      case NotePropertyType.number:
        final controller = TextEditingController(
          text: current == null ? '' : current.toString(),
        );
        final value = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(definition.name),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: definition.type == NotePropertyType.number
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              maxLines: definition.type == NotePropertyType.text ? null : 1,
              decoration: InputDecoration(
                hintText:
                    definition.type == NotePropertyType.number ? '0' : 'Valore',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annulla'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Applica'),
              ),
            ],
          ),
        );
        controller.dispose();
        if (value == null || !mounted) return;
        try {
          final normalized = PropertyRules.normalizeValue(definition, value);
          setState(() {
            if (normalized == null) {
              _values.remove(definition.id);
            } else {
              _values[definition.id] = normalized;
            }
            _error = null;
          });
        } catch (e) {
          setState(
            () => _error = e.toString().replaceFirst('FormatException: ', ''),
          );
        }
        return;
    }
  }

  String _summary(PropertyDefinition definition) {
    final value = _values[definition.id];
    if (value == null) return 'Nessun valore';
    if (value is List) return value.join(', ');
    if (value is bool) return value ? 'Sì' : 'No';
    return value.toString();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Proprietà',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _addDefinition,
                      icon: const Icon(Icons.add),
                      label: const Text('Nuova'),
                    ),
                  ],
                ),
                const Text(
                  'Metadati strutturati riutilizzabili senza modificare il database legacy.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 10),
                Expanded(
                  child: _definitions.isEmpty
                      ? const Center(
                          child: Text(
                            'Nessuna proprietà. Creane una per strutturare note e attività.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          itemCount: _definitions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final definition = _definitions[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(definition.name),
                              subtitle: Text(
                                '${definition.type.label} · ${_summary(definition)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: _busy ? null : () => _edit(definition),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.pop(
                            context,
                            Map<String, Object?>.from(_values),
                          ),
                  child: const Text('Applica'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _NewProperty {
  const _NewProperty(this.name, this.type, this.options);

  final String name;
  final NotePropertyType type;
  final List<String> options;
}
