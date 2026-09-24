import 'dart:convert';

enum SharedActivityKind {
  spaceCreated,
  spaceUpdated,
  contentAdded,
  contentRemoved,
  memberChanged,
  documentUpdated,
  conflictPreserved;

  String get label => switch (this) {
        SharedActivityKind.spaceCreated => 'ha creato lo spazio',
        SharedActivityKind.spaceUpdated => 'ha aggiornato lo spazio',
        SharedActivityKind.contentAdded => 'ha condiviso un contenuto',
        SharedActivityKind.contentRemoved => 'ha reso privato un contenuto',
        SharedActivityKind.memberChanged => 'ha aggiornato i membri',
        SharedActivityKind.documentUpdated => 'ha modificato un contenuto',
        SharedActivityKind.conflictPreserved =>
          'ha preservato un conflitto locale',
      };
}

class SharedActivityEvent {
  const SharedActivityEvent({
    required this.id,
    required this.spaceId,
    required this.actorId,
    required this.actorName,
    required this.kind,
    required this.at,
    this.subjectId,
  });

  final String id;
  final String spaceId;
  final String actorId;
  final String actorName;
  final SharedActivityKind kind;
  final int at;
  final String? subjectId;

  Map<String, Object?> toJson() => {
        'id': id,
        'spaceId': spaceId,
        'actorId': actorId,
        'actorName': actorName,
        'kind': kind.name,
        'at': at,
        if (subjectId != null) 'subjectId': subjectId,
      };

  factory SharedActivityEvent.fromJson(Map<String, Object?> map) {
    final kindName = map['kind']?.toString();
    final kinds =
        SharedActivityKind.values.where((value) => value.name == kindName);
    if (kinds.isEmpty) {
      throw const FormatException('Tipo attività Shared non valido.');
    }
    final event = SharedActivityEvent(
      id: _requiredActivityId(map['id'], 'evento'),
      spaceId: _requiredActivityId(map['spaceId'], 'spazio'),
      actorId: _requiredActivityId(map['actorId'], 'autore'),
      actorName: _activityActorName(map['actorName']),
      kind: kinds.first,
      at: _activityTimestamp(map['at']),
      subjectId: map['subjectId'] == null
          ? null
          : _requiredActivityId(map['subjectId'], 'soggetto'),
    );
    validateSharedActivity(event);
    return event;
  }
}

const sharedActivityLimit = 200;

void validateSharedActivity(SharedActivityEvent event) {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(event.id)) {
    throw const FormatException('ID attività Shared non valido.');
  }
  _requiredActivityId(event.spaceId, 'spazio');
  _requiredActivityId(event.actorId, 'autore');
  _activityActorName(event.actorName);
  _activityTimestamp(event.at);
  if (event.subjectId != null) {
    _requiredActivityId(event.subjectId, 'soggetto');
  }
}

List<SharedActivityEvent> mergeSharedActivity(
  Iterable<SharedActivityEvent> left,
  Iterable<SharedActivityEvent> right, {
  int limit = sharedActivityLimit,
}) {
  if (limit < 1 || limit > sharedActivityLimit) {
    throw const FormatException('Limite attività Shared non valido.');
  }
  final byId = <String, SharedActivityEvent>{};
  for (final event in [...left, ...right]) {
    validateSharedActivity(event);
    byId[event.id] = event;
  }
  final result = byId.values.toList(growable: false)
    ..sort((a, b) {
      final byTime = b.at.compareTo(a.at);
      if (byTime != 0) return byTime;
      return b.id.compareTo(a.id);
    });
  return result.take(limit).toList(growable: false);
}

int sharedUnreadCount({
  required Iterable<SharedActivityEvent> events,
  required String identityId,
  required int lastReadAt,
}) {
  return events
      .where(
        (event) =>
            event.actorId != identityId && event.at > lastReadAt,
      )
      .length;
}

abstract final class SharedActivityCodec {
  static const format = 'notes-shared-activity-cache';
  static const version = 1;
  static const maxBytes = 1024 * 1024;

  static String encode(Map<String, List<SharedActivityEvent>> bySpace) {
    if (bySpace.length > 30) {
      throw const FormatException('Troppi spazi nella cache attività Shared.');
    }
    final normalized = <String, Object?>{};
    for (final entry in bySpace.entries) {
      final spaceId = _requiredActivityId(entry.key, 'spazio');
      final events = mergeSharedActivity(const [], entry.value);
      for (final event in events) {
        if (event.spaceId != spaceId) {
          throw const FormatException(
            'Attività Shared associata allo spazio errato.',
          );
        }
      }
      normalized[spaceId] =
          events.map((event) => event.toJson()).toList(growable: false);
    }
    final raw = jsonEncode({
      'format': format,
      'version': version,
      'spaces': normalized,
    });
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Cache attività Shared troppo grande.');
    }
    return raw;
  }

  static Map<String, List<SharedActivityEvent>> decode(String raw) {
    if (utf8.encode(raw).length > maxBytes) {
      throw const FormatException('Cache attività Shared troppo grande.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['format'] != format ||
        decoded['version'] != version ||
        decoded['spaces'] is! Map) {
      throw const FormatException('Cache attività Shared non valida.');
    }
    final spaces = decoded['spaces'] as Map;
    if (spaces.length > 30) {
      throw const FormatException('Troppi spazi nella cache attività Shared.');
    }
    final result = <String, List<SharedActivityEvent>>{};
    for (final entry in spaces.entries) {
      final spaceId = _requiredActivityId(entry.key, 'spazio');
      final rows = entry.value;
      if (rows is! List || rows.length > sharedActivityLimit) {
        throw const FormatException('Cronologia Shared non valida.');
      }
      final events = <SharedActivityEvent>[];
      for (final value in rows) {
        if (value is! Map) {
          throw const FormatException('Evento Shared non valido.');
        }
        events.add(
          SharedActivityEvent.fromJson(
            value.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        );
      }
      result[spaceId] = mergeSharedActivity(const [], events);
    }
    return result;
  }
}

String _requiredActivityId(Object? value, String field) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.length > 200) {
    throw FormatException('ID $field Shared non valido.');
  }
  return text;
}

String _activityActorName(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.length > 80) {
    throw const FormatException('Nome autore Shared non valido.');
  }
  return text;
}

int _activityTimestamp(Object? value) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  if (number == null || number < 0 || number > 4102444800000) {
    throw const FormatException('Data attività Shared non valida.');
  }
  return number;
}
