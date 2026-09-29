import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/data/plus_entitlement_service.dart';
import 'package:notes_ecosistema/src/domain/local_ai_pack.dart';
import 'package:notes_ecosistema/src/domain/plus.dart';

void main() {
  test('release-safe entitlement defaults to Free when debug override is false',
      () async {
    final snapshot =
        await const PlusEntitlementService(debugPlus: false).snapshot();

    expect(snapshot.plan, NotesPlan.free);
    expect(snapshot.source, EntitlementSource.none);
    expect(snapshot.allows(PlusFeature.localAi20L), isFalse);
  });

  test('debug entitlement unlocks local AI pack without fake billing',
      () async {
    final snapshot =
        await const PlusEntitlementService(debugPlus: true).snapshot();

    expect(snapshot.plan, NotesPlan.plus);
    expect(snapshot.source, EntitlementSource.debug);
    expect(snapshot.allows(PlusFeature.localAi20L), isTrue);
  });

  test('AI pack status parses installed model and clamps progress', () {
    final installed = LocalAiPackStatus.fromMap({
      'supported': true,
      'phase': 'installed',
      'bytesDownloaded': 35300000,
      'totalBytes': 35300000,
      'modelPath': '/data/user/0/app/needle3.cact',
    });
    expect(installed.installed, isTrue);
    expect(installed.progress, 1);

    final downloading = LocalAiPackStatus.fromMap({
      'supported': true,
      'phase': 'downloading',
      'bytesDownloaded': 40,
      'totalBytes': 20,
    });
    expect(downloading.downloading, isTrue);
    expect(downloading.progress, 1);
  });

  test('Needle 20L artifact identity is pinned', () {
    expect(Needle20LPackPolicy.packName, 'notes_needle3_20l');
    expect(Needle20LPackPolicy.modelFileName, 'needle3.cact');
    expect(Needle20LPackPolicy.modelSha256, hasLength(64));
    expect(
      Needle20LPackPolicy.approximateAndroidArm64RuntimeMegabytes,
      lessThan(2),
    );
  });
}
