import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/shared_space_bundle.dart';
import 'package:notes_ecosistema/src/domain/shared_spaces.dart';
import 'package:notes_ecosistema/src/domain/sync.dart';
import 'package:notes_ecosistema/src/sync/shared_spaces_live_sync.dart';

void main() {
  const owner = SharedIdentity(
    id: 'owner-1',
    displayName: 'Owner',
  );
  const viewer = SharedIdentity(
    id: 'viewer-1',
    displayName: 'Viewer',
  );

  SharedSpace spaceAt(int now) => SharedSpaces.create(
        owner: owner,
        name: 'Casa',
        description: 'Spazio comune',
        now: now,
      );

  test('spaces are private by default and explicit sharing is selective', () {
    final space = spaceAt(100);
    expect(space.contentIds, isEmpty);
    expect(space.roleFor(owner.id), SharedRole.owner);

    final shared = SharedSpaces.linkContent(
      space,
      owner.id,
      'note-1',
      now: 200,
    );
    expect(shared.contentIds, {'note-1'});
    expect(shared.contentIds.contains('private-note'), isFalse);

    final privateAgain = SharedSpaces.unlinkContent(
      shared,
      owner.id,
      'note-1',
      now: 300,
    );
    expect(privateAgain.contentIds, isEmpty);
  });

  test('viewer cannot mutate content while editor can', () {
    var space = spaceAt(100);
    space = SharedSpaces.updateMember(
      space,
      owner,
      viewer.id,
      role: SharedRole.viewer,
      displayName: viewer.displayName,
      now: 200,
    );

    expect(space.roleFor(viewer.id), SharedRole.viewer);
    expect(
      () => SharedSpaces.linkContent(
        space,
        viewer.id,
        'note-1',
        now: 300,
      ),
      throwsFormatException,
    );

    space = SharedSpaces.updateMember(
      space,
      owner,
      viewer.id,
      role: SharedRole.editor,
      now: 400,
    );
    final edited = SharedSpaces.linkContent(
      space,
      viewer.id,
      'note-1',
      now: 500,
    );
    expect(edited.contentIds, {'note-1'});
  });

  test('invite joins same canonical space without carrying secrets', () {
    final space = spaceAt(100);
    final invite = SharedSpaces.invite(
      space,
      owner,
      role: SharedRole.editor,
      now: 1000,
    );
    final code = invite.encode();

    expect(code.startsWith('NS26.'), isTrue);
    expect(code.contains('token'), isFalse);

    final decoded = SharedSpaceInvite.decode(code, now: 1001);
    final joined = SharedSpaces.joinInvite(
      decoded,
      viewer,
      now: 1002,
    );

    expect(joined.id, space.id);
    expect(joined.createdAt, space.createdAt);
    expect(joined.ownerId, owner.id);
    expect(joined.roleFor(viewer.id), SharedRole.editor);
  });

  test('expired invite is rejected', () {
    final invite = SharedSpaceInvite(
      spaceId: 'space-1',
      spaceName: 'Casa',
      owner: const SharedMember(
        id: 'owner-1',
        displayName: 'Owner',
        role: SharedRole.owner,
        updatedAt: 100,
      ),
      spaceCreatedAt: 100,
      role: SharedRole.viewer,
      issuedAt: 1000,
      expiresAt: 2000,
    );
    final code = invite.encode();
    expect(
      () => SharedSpaceInvite.decode(code, now: 2001),
      throwsFormatException,
    );
  });

  test('merge uses clocks so newer share or unshare wins', () {
    final base = spaceAt(100);
    final local = SharedSpaces.linkContent(
      base,
      owner.id,
      'note-1',
      now: 200,
    );
    final remoteRemoved = SharedSpaces.unlinkContent(
      local,
      owner.id,
      'note-1',
      now: 300,
    );

    final mergedRemoved = SharedSpaces.merge(local, remoteRemoved);
    expect(mergedRemoved.contentIds, isEmpty);

    final remoteReadded = SharedSpaces.linkContent(
      remoteRemoved,
      owner.id,
      'note-1',
      now: 400,
    );
    final mergedReadded = SharedSpaces.merge(
      mergedRemoved,
      remoteReadded,
    );
    expect(mergedReadded.contentIds, {'note-1'});
  });

  test('shared spaces codec roundtrips member and tombstone clocks', () {
    var space = spaceAt(100);
    space = SharedSpaces.updateMember(
      space,
      owner,
      viewer.id,
      role: SharedRole.editor,
      displayName: viewer.displayName,
      now: 200,
    );
    space = SharedSpaces.linkContent(
      space,
      owner.id,
      'note-1',
      now: 300,
    );
    space = SharedSpaces.unlinkContent(
      space,
      owner.id,
      'note-1',
      now: 400,
    );

    final raw = SharedSpacesCodec.encode(
      SharedSpacesSnapshot(
        identity: owner,
        spaces: [space],
      ),
    );
    final decoded = SharedSpacesCodec.decode(raw);

    expect(decoded.identity.id, owner.id);
    expect(decoded.spaces.single.roleFor(viewer.id), SharedRole.editor);
    expect(decoded.spaces.single.contentIds, isEmpty);
    expect(
      decoded.spaces.single.contentRemovedAt['note-1'],
      400,
    );
  });

  test('portable space bundle validates document membership', () {
    var space = spaceAt(100);
    space = SharedSpaces.linkContent(
      space,
      owner.id,
      'note-1',
      now: 200,
    );
    const document = SyncDocument(
      id: 'note-1',
      title: 'Lista',
      body: 'Latte',
      favorite: false,
      createdAt: 100,
      updatedAt: 200,
      pinned: false,
      archived: false,
      tags: [],
    );

    final archive = Archive()
      ..add(
        ArchiveFile.string(
          'space.json',
          jsonEncode({
            'format': SharedSpaceBundle.format,
            'version': SharedSpaceBundle.version,
            'exportedAt': 500,
            'actor': owner.toJson(),
            'space': space.toJson(),
          }),
        ),
      )
      ..add(
        ArchiveFile.string(
          'documents/${SyncCodec.filename(document.id)}',
          SyncCodec.encode(document),
        ),
      )
      ..add(
        ArchiveFile.string(
          'LEGGIMI.txt',
          'test',
        ),
      );

    final bytes = ZipEncoder().encodeBytes(archive);
    final decoded = SharedSpaceBundle.decode(bytes);

    expect(decoded.space.id, space.id);
    expect(decoded.documents['note-1'], document);
    expect(decoded.assets, isEmpty);
  });

  test('bundle rejects unknown paths', () {
    final archive = Archive()
      ..add(
        ArchiveFile.string(
          '../rogue.txt',
          'bad',
        ),
      );
    final bytes = ZipEncoder().encodeBytes(archive);
    expect(
      () => SharedSpaceBundle.decode(bytes),
      throwsFormatException,
    );
  });

  test('live sync bootstraps from the newest document', () {
    const older = SyncDocument(
      id: 'note-1',
      title: 'Vecchia',
      body: 'A',
      favorite: false,
      createdAt: 100,
      updatedAt: 200,
      pinned: false,
      archived: false,
      tags: [],
    );
    const newer = SyncDocument(
      id: 'note-1',
      title: 'Nuova',
      body: 'B',
      favorite: false,
      createdAt: 100,
      updatedAt: 300,
      pinned: false,
      archived: false,
      tags: [],
    );

    expect(
      decideSharedLiveDocument(
        baseHash: null,
        local: newer,
        remote: older,
      ),
      SharedLiveDecision.upload,
    );
    expect(
      decideSharedLiveDocument(
        baseHash: null,
        local: older,
        remote: newer,
      ),
      SharedLiveDecision.download,
    );
  });

  test('live sync detects two-sided edits from the same base', () {
    const base = SyncDocument(
      id: 'note-1',
      title: 'Base',
      body: 'A',
      favorite: false,
      createdAt: 100,
      updatedAt: 100,
      pinned: false,
      archived: false,
      tags: [],
    );
    const local = SyncDocument(
      id: 'note-1',
      title: 'Locale',
      body: 'B',
      favorite: false,
      createdAt: 100,
      updatedAt: 200,
      pinned: false,
      archived: false,
      tags: [],
    );
    const remote = SyncDocument(
      id: 'note-1',
      title: 'Remota',
      body: 'C',
      favorite: false,
      createdAt: 100,
      updatedAt: 210,
      pinned: false,
      archived: false,
      tags: [],
    );

    final baseHash = sharedLiveDocumentHash(base);
    expect(
      decideSharedLiveDocument(
        baseHash: baseHash,
        local: local,
        remote: remote,
      ),
      SharedLiveDecision.conflict,
    );
    expect(
      decideSharedLiveDocument(
        baseHash: sharedLiveDocumentHash(local),
        local: local,
        remote: remote,
      ),
      SharedLiveDecision.download,
    );
    expect(
      decideSharedLiveDocument(
        baseHash: sharedLiveDocumentHash(remote),
        local: local,
        remote: remote,
      ),
      SharedLiveDecision.upload,
    );
  });

  test('GitHub binding migrates legacy owner without losing the space', () {
    final legacySpace = spaceAt(100);
    final migrated = SharedSpaces.bindGitHubIdentity(
      SharedSpacesSnapshot(
        identity: owner,
        spaces: [legacySpace],
      ),
      userId: '143192448',
      login: 'riccardopinato',
    );

    expect(migrated.identity.id, 'github:143192448');
    expect(migrated.identity.githubUserId, '143192448');
    expect(migrated.identity.githubLogin, 'riccardopinato');
    expect(migrated.identity.legacyIds, contains(owner.id));

    final space = migrated.spaces.single;
    expect(space.ownerId, migrated.identity.id);
    expect(space.roleFor(migrated.identity.id), SharedRole.owner);
    expect(space.member(owner.id), isNull);

    final roundtrip = SharedSpacesCodec.decode(
      SharedSpacesCodec.encode(migrated),
    );
    expect(roundtrip.identity.id, migrated.identity.id);
    expect(roundtrip.identity.legacyIds, contains(owner.id));
    expect(roundtrip.spaces.single.ownerId, migrated.identity.id);
  });

  test('legacy remote identity is canonicalized before merge', () {
    final remoteLegacy = spaceAt(100);
    final migrated = SharedSpaces.bindGitHubIdentity(
      SharedSpacesSnapshot(
        identity: owner,
        spaces: [remoteLegacy],
      ),
      userId: '143192448',
      login: 'riccardopinato',
    );

    final normalizedRemote = SharedSpaces.canonicalizeIdentity(
      remoteLegacy,
      migrated.identity,
    );
    final merged = SharedSpaces.merge(
      migrated.spaces.single,
      normalizedRemote,
    );

    expect(merged.ownerId, 'github:143192448');
    expect(merged.roleFor('github:143192448'), SharedRole.owner);
    expect(merged.members.where((member) => member.role == SharedRole.owner),
        hasLength(1));
  });

  test('fresh install discovers a canonical remote shared space', () {
    const canonical = SharedIdentity(
      id: 'github:143192448',
      displayName: 'Riccardo',
      githubUserId: '143192448',
      githubLogin: 'riccardopinato',
    );
    final remote = SharedSpaces.create(
      owner: canonical,
      name: 'Casa',
      description: 'Condiviso',
      now: 100,
    );

    final discovered = mergeDiscoveredSharedSpaces(
      identity: canonical,
      localSpaces: const [],
      remoteSpaces: [remote],
    );

    expect(discovered, hasLength(1));
    expect(discovered.single.id, remote.id);
    expect(discovered.single.roleFor(canonical.id), SharedRole.owner);
  });

  test('remote discovery ignores spaces where identity is not a member', () {
    const canonical = SharedIdentity(
      id: 'github:143192448',
      displayName: 'Riccardo',
      githubUserId: '143192448',
      githubLogin: 'riccardopinato',
    );
    final foreign = SharedSpaces.create(
      owner: owner,
      name: 'Altro',
      now: 100,
    );

    final discovered = mergeDiscoveredSharedSpaces(
      identity: canonical,
      localSpaces: const [],
      remoteSpaces: [foreign],
    );

    expect(discovered, isEmpty);
  });

  test('GitHub binding refuses account switch with existing spaces', () {
    final migrated = SharedSpaces.bindGitHubIdentity(
      SharedSpacesSnapshot(
        identity: owner,
        spaces: [spaceAt(100)],
      ),
      userId: '143192448',
      login: 'riccardopinato',
    );

    expect(
      () => SharedSpaces.bindGitHubIdentity(
        migrated,
        userId: '999999',
        login: 'another-user',
      ),
      throwsFormatException,
    );
  });

}
