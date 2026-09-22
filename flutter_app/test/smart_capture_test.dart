import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/smart_capture.dart';

void main() {
  test('Smart Capture normalizes public HTTP URLs', () {
    expect(
      SmartCaptureRules.normalizeHttpUrl('HTTPS://Example.COM/path?q=1'),
      'https://example.com/path?q=1',
    );
    expect(
      SmartCaptureRules.extractSingleHttpUrl(' https://example.com '),
      'https://example.com/',
    );
    expect(
      () => SmartCaptureRules.normalizeHttpUrl('ftp://example.com/file'),
      throwsFormatException,
    );
    expect(
      () => SmartCaptureRules.normalizeHttpUrl(
        'https://user:secret@example.com/',
      ),
      throwsFormatException,
    );
  });

  test('Smart Capture sections are idempotence-detectable', () {
    const content = 'testo acquisito';
    final body = SmartCaptureRules.appendSection(
      'Prima parte',
      'Testo estratto',
      content,
    );

    expect(
      body,
      'Prima parte\n\n## Testo estratto\n\ntesto acquisito\n',
    );
    expect(
      SmartCaptureRules.containsSection(
        body,
        'Testo estratto',
        content,
      ),
      isTrue,
    );
  });

  test('Web snapshot strips executable markup and builds Markdown', () {
    const html = '''
<html>
  <head>
    <title>Pagina prova</title>
    <meta name="description" content="Descrizione prova">
    <script>window.secret = true;</script>
  </head>
  <body>
    <main>
      <h1>Titolo articolo</h1>
      <p>Primo paragrafo.</p>
      <style>.hidden { display:none }</style>
      <p>Secondo &amp; ultimo.</p>
    </main>
  </body>
</html>
''';

    final snapshot = WebCapture().parseSnapshot(
      'https://example.com/a',
      'https://example.com/a',
      html,
    );

    expect(snapshot.title, 'Pagina prova');
    expect(snapshot.description, 'Descrizione prova');
    expect(snapshot.text, contains('Primo paragrafo.'));
    expect(snapshot.text, contains('Secondo & ultimo.'));
    expect(snapshot.text, isNot(contains('window.secret')));
    expect(snapshot.text, isNot(contains('display:none')));

    final markdown = snapshot.toMarkdown();
    expect(markdown, contains('## Pagina prova'));
    expect(markdown, contains('[Apri fonte](https://example.com/a)'));
    expect(markdown, contains('> Descrizione prova'));
  });

  test('OCR and web clipping respect Kotlin limits', () {
    final ocr = SmartCaptureRules.clipOcr(
      'x' * (SmartCaptureRules.maxOcrTextChars + 100),
    );
    final web = SmartCaptureRules.clipWebText(
      'y' * (SmartCaptureRules.maxWebTextChars + 100),
    );

    expect(ocr.length, SmartCaptureRules.maxOcrTextChars);
    expect(web.length, SmartCaptureRules.maxWebTextChars);
  });
}
