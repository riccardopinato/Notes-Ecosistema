import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/shared_activity.dart';
import 'package:notes_ecosistema/src/domain/shared_spaces.dart';
import 'package:notes_ecosistema/src/sync/shared_spaces_live_sync.dart';

void main() {
  const actor = SharedIdentity(
    id: 'github:1',
    displayName: 'Riccardo',
    githubUserId: '1',
    githubLogin: 'riccardo',
  );

  test('activity merge is deterministic, deduplicated and bounded', () {
    final event = sharedActivityEvent(
      actor: actor,
      spaceId: 'space-1',
      kind: SharedActivityKind.documentUpdated,
      at: 100,
      subjectId: 'note-1',
    );
    final same = sharedActivityEvent(
      actor: actor,
      spaceId: 'space-1',
      kind: SharedActivityKind.documentUpdated,
      at: 100,
      subjectId: 'note-1',
    );
    expect(event.id, same.id);

    final merged = mergeSharedActivity([event], [same]);
    expect(merged, hasLength(1));
    expect(merged.single.id, event.id);
  });

  test('activity codec roundtrips and unread ignores own events', () {
    final mine = sharedActivityEvent(
      actor: actor,
      spaceId: 'space-1',
      kind: SharedActivityKind.spaceCreated,
      at: 100,
    );
    const other = SharedIdentity(
      id: 'github:2',
      displayName: 'Anna',
      githubUserId: '2',
      githubLogin: 'anna',
    );
    final remote = sharedActivityEvent(
      actor: other,
      spaceId: 'space-1',
      kind: SharedActivityKind.documentUpdated,
      at: 200,
      subjectId: 'note-1',
    );

    final raw = SharedActivityCodec.encode({
      'space-1': [remote, mine],
    });
    final decoded = SharedActivityCodec.decode(raw);
    expect(decoded['space-1'], hasLength(2));
    expect(
      sharedUnreadCount(
        events: decoded['space-1']!,
        identityId: actor.id,
        lastReadAt: 0,
      ),
      1,
    );
    expect(
      sharedUnreadCount(
        events: decoded['space-1']!,
        identityId: actor.id,
        lastReadAt: 200,
      ),
      0,
    );
  });

  test('state activity detects metadata, sharing and members', () {
    final base = SharedSpaces.create(
      owner: actor,
      name: 'Casa',
      description: 'Base',
      now: 100,
    );
    var changed = SharedSpaces.rename(
      base,
      actor,
      name: 'Casa nuova',
      description: 'Aggiornata',
      now: 200,
    );
    changed = SharedSpaces.linkContent(
      changed,
      actor.id,
      'note-1',
      now: 300,
    );
    changed = SharedSpaces.updateMember(
      changed,
      actor,
      'github:2',
      role: SharedRole.viewer,
      displayName: 'Anna',
      now: 400,
    );

    final events = buildSharedStateActivity(
      actor: actor,
      current: changed,
      previous: base,
    );

    expect(
      events.map((event) => event.kind),
      containsAll([
        SharedActivityKind.spaceUpdated,
        SharedActivityKind.contentAdded,
        SharedActivityKind.memberChanged,
      ]),
    );
  });

  test('initial state creates only one bootstrap event', () {
    final space = SharedSpaces.create(
      owner: actor,
      name: 'Casa',
      now: 100,
    );
    final events = buildSharedStateActivity(
      actor: actor,
      current: space,
    );
    expect(events, hasLength(1));
    expect(events.single.kind, SharedActivityKind.spaceCreated);
  });
}
