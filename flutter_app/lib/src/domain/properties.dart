import 'dart:convert';

enum NotePropertyType {
  text,
  number,
  date,
  select,
  multiSelect,
  checkbox,
  status,
}

extension NotePropertyTypeWire on NotePropertyType {
  String get wire => name.toUpperCase();

  String get label => switch (this) {
        NotePropertyType.text => 'Testo',
        NotePropertyType.number => 'Numero',
        NotePropertyType.date => 'Data',
        NotePropertyType.select => 'Selezione',
        NotePropertyType.multiSelect => 'Selezione multipla',
        NotePropertyType.checkbox => 'Checkbox',
        NotePropertyType.status => 'Stato',
      };

  static NotePropertyType parse(String raw) {
    final normalized = raw.trim().toLowerCase();
    return NotePropertyType.values.firstWhere(
      (value) => value.name.toLowerCase() == normalized,
      orElse: () => throw FormatException('Tipo proprietà non valido: $raw'),
    );
  }
}

class PropertyDefinition {
  const PropertyDefinition({
    required this.id,
    required this.name,
    required this.type,
    required this.options,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final NotePropertyType type;
  final List<String> options;
  final int createdAt;
  final int updatedAt;

  PropertyDefinition copyWith({
    String? name,
    NotePropertyType? type,
    List<String>? options,
    int? updatedAt,
  }) =>
      PropertyDefinition(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        options: options ?? this.options,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  factory PropertyDefinition.fromMap(Map<String, Object?> row) {
    final rawOptions = row['optionsJson']?.toString() ?? '[]';
    final decoded = jsonDecode(rawOptions);
    if (decoded is! List) {
      throw const FormatException('Opzioni proprietà non valide.');
    }
    final definition = PropertyDefinition(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      type: NotePropertyTypeWire.parse(row['type']?.toString() ?? ''),
      options: decoded.map((value) => value.toString()).toList(growable: false),
      createdAt: (row['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
    );
    PropertyRules.validateDefinition(definition);
    return definition;
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type.name,
        'optionsJson': jsonEncode(options),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class NotePropertyValue {
  const NotePropertyValue({
    required this.noteId,
    required this.definitionId,
    required this.valueJson,
    required this.updatedAt,
  });

  final String noteId;
  final String definitionId;
  final String valueJson;
  final int updatedAt;

  Object? get decoded => jsonDecode(valueJson);

  factory NotePropertyValue.fromMap(Map<String, Object?> row) =>
      NotePropertyValue(
        noteId: row['noteId']?.toString() ?? '',
        definitionId: row['definitionId']?.toString() ?? '',
        valueJson: row['valueJson']?.toString() ?? 'null',
        updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toMap() => {
        'noteId': noteId,
        'definitionId': definitionId,
        'valueJson': valueJson,
        'updatedAt': updatedAt,
      };
}

class PropertySnapshot {
  const PropertySnapshot({
    required this.definitions,
    required this.values,
  });

  final List<PropertyDefinition> definitions;
  final List<NotePropertyValue> values;
}

abstract final class PropertyRules {
  static const maxDefinitions = 100;
  static const maxOptions = 100;
  static const maxNameLength = 80;
  static const maxTextLength = 4000;
  static const maxMultiValues = 50;

  static void validateDefinition(PropertyDefinition definition) {
    final name = definition.name.trim();
    if (definition.id.trim().isEmpty || definition.id.length > 200) {
      throw const FormatException('ID proprietà non valido.');
    }
    if (name.isEmpty || name.length > maxNameLength) {
      throw const FormatException('Nome proprietà non valido.');
    }
    if (definition.createdAt < 0 || definition.updatedAt < 0) {
      throw const FormatException('Data proprietà non valida.');
    }

    final normalized = <String>{};
    for (final option in definition.options) {
      final value = option.trim();
      if (value.isEmpty || value.length > maxNameLength) {
        throw const FormatException('Opzione proprietà non valida.');
      }
      if (!normalized.add(value.toLowerCase())) {
        throw const FormatException('Opzioni proprietà duplicate.');
      }
    }
    if (definition.options.length > maxOptions) {
      throw const FormatException('Troppe opzioni nella proprietà.');
    }

    final needsOptions = definition.type == NotePropertyType.select ||
        definition.type == NotePropertyType.multiSelect ||
        definition.type == NotePropertyType.status;
    if (needsOptions && definition.options.isEmpty) {
      throw const FormatException(
        'Aggiungi almeno un’opzione per questa proprietà.',
      );
    }
    if (!needsOptions && definition.options.isNotEmpty) {
      throw const FormatException(
        'Questo tipo di proprietà non usa opzioni.',
      );
    }
  }

  static String encodeValue(PropertyDefinition definition, Object? value) {
    final normalized = normalizeValue(definition, value);
    return jsonEncode(normalized);
  }

  static Object? decodeValue(
    PropertyDefinition definition,
    String valueJson,
  ) {
    final decoded = jsonDecode(valueJson);
    return normalizeValue(definition, decoded);
  }

  static Object? normalizeValue(
    PropertyDefinition definition,
    Object? value,
  ) {
    if (value == null) return null;

    switch (definition.type) {
      case NotePropertyType.text:
        if (value is! String) {
          throw const FormatException('Testo proprietà non valido.');
        }
        final text = value.trim();
        if (text.length > maxTextLength) {
          throw const FormatException('Testo proprietà troppo lungo.');
        }
        return text.isEmpty ? null : text;
      case NotePropertyType.number:
        final number = value is num ? value.toDouble() : double.tryParse('$value');
        if (number == null || !number.isFinite) {
          throw const FormatException('Numero proprietà non valido.');
        }
        return number;
      case NotePropertyType.date:
        if (value is! String || !_date.hasMatch(value)) {
          throw const FormatException('Data proprietà non valida.');
        }
        final parsed = DateTime.tryParse(value);
        if (parsed == null || _dateKey(parsed) != value) {
          throw const FormatException('Data proprietà non valida.');
        }
        return value;
      case NotePropertyType.select:
      case NotePropertyType.status:
        if (value is! String) {
          throw const FormatException('Opzione proprietà non valida.');
        }
        final match = definition.options.where(
          (option) => option.toLowerCase() == value.trim().toLowerCase(),
        );
        if (match.isEmpty) {
          throw const FormatException('Opzione proprietà sconosciuta.');
        }
        return match.first;
      case NotePropertyType.multiSelect:
        if (value is! List) {
          throw const FormatException('Selezione multipla non valida.');
        }
        if (value.length > maxMultiValues) {
          throw const FormatException('Troppe selezioni nella proprietà.');
        }
        final chosen = <String>[];
        final seen = <String>{};
        for (final item in value) {
          final raw = item.toString().trim();
          final match = definition.options.where(
            (option) => option.toLowerCase() == raw.toLowerCase(),
          );
          if (match.isEmpty) {
            throw const FormatException('Opzione proprietà sconosciuta.');
          }
          final canonical = match.first;
          if (seen.add(canonical.toLowerCase())) chosen.add(canonical);
        }
        return chosen;
      case NotePropertyType.checkbox:
        if (value is! bool) {
          throw const FormatException('Checkbox proprietà non valida.');
        }
        return value;
    }
  }

  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
