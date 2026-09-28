import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/attachments.dart';

void main() {
  const pdfKey =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf';
  const imageKey =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.jpg';

  test('attachment reachability includes note draft and sidecar references',
      () {
    final keys = Attachments.referencedKeys(
      noteBodies: const [
        '[Documento](notes-asset://$pdfKey)',
      ],
      draftBodies: const [
        '[Immagine](notes-asset://$imageKey)',
      ],
      sidecarKeys: const [pdfKey, imageKey, null, 'invalid-key'],
    );

    expect(keys, {pdfKey, imageKey});
  });

  test('sidecar-only PDF remains reachable after its body link is removed', () {
    final keys = Attachments.referencedKeys(
      noteBodies: const ['Testo senza link allegati'],
      draftBodies: const [],
      sidecarKeys: const [pdfKey],
    );

    expect(keys, contains(pdfKey));
  });
}
