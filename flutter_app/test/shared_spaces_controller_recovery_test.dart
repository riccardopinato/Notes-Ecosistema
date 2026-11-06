import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notes_ecosistema/src/domain/shared_spaces.dart';
import 'package:notes_ecosistema/src/state/shared_spaces_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('undo snapshot preserves persisted Shared Spaces invitation history',
      () async {
    const owner = SharedIdentity(
      id: 'owner-1',
      displayName: 'Owner',
    );
    final space = SharedSpaces.create(
      owner: owner,
      name: 'Casa',
      description: 'Private shared workspace',
      now: 100,
    );
    final invite = SharedSpaces.invite(
      space,
      owner,
      role: SharedRole.editor,
      now: 200,
    );
    final record = SharedInviteRecord(
      id: 'invite-history-1',
      spaceId: space.id,
      spaceName: space.name,
      role: invite.role,
      code: invite.encode(),
      issuedAt: invite.issuedAt,
      expiresAt: invite.expiresAt,
    );
    final original = SharedSpacesSnapshot(
      identity: owner,
      spaces: [space],
      inviteHistory: [record],
    );
    SharedPreferences.setMockInitialValues({
      'shared_spaces_v1': SharedSpacesCodec.encode(original),
    });

    final controller = SharedSpacesController();
    try {
      await controller.load();
      final before = controller.snapshot();
      expect(before.inviteHistory, hasLength(1));
      expect(before.inviteHistory.single.code, record.code);

      await controller.restoreExact(before);
      final persisted =
          (await SharedPreferences.getInstance()).getString('shared_spaces_v1');
      expect(persisted, isNotNull);
      final restored = SharedSpacesCodec.decode(persisted!);
      expect(restored.inviteHistory, hasLength(1));
      expect(restored.inviteHistory.single.id, record.id);
      expect(restored.inviteHistory.single.code, record.code);
    } finally {
      controller.dispose();
    }
  });
}
