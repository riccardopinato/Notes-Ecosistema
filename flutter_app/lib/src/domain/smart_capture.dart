import 'dart:async';
import 'dart:convert';
import 'dart:io';

class WebSnapshot {
  const WebSnapshot({
    required this.requestedUrl,
    required this.finalUrl,
    required this.title,
    required this.description,
    required this.text,
  });

  final String requestedUrl;
  final String finalUrl;
  final String title;
  final String description;
  final String text;

  String toMarkdown() {
    final safeTitle = title.trim().isEmpty ? finalUrl : title.trim();
    final descriptionText = description.trim();
    final bodyText = text.trim();
    final buffer = StringBuffer()
      ..writeln('## $safeTitle')
      ..writeln()
      ..writeln('[Apri fonte]($finalUrl)');

    if (descriptionText.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(
          '> ${descriptionText.replaceAll('\n', '\n> ')}',
        );
    }
    if (bodyText.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(bodyText);
    }
    return buffer.toString().trim();
  }
}

abstract final class SmartCaptureRules {
  static const maxSharedUris = 20;
  static const maxWebHtmlBytes = 1500000;
  static const maxWebTextChars = 24000;
  static const maxOcrTextChars = 60000;
  static const maxUrlLength = 4096;

  static String? extractSingleHttpUrl(String text) {
    final candidate = text.trim();
    if (candidate.length < 8 || candidate.length > maxUrlLength) {
      return null;
    }
    if (!RegExp(r'^https?://[^\s]+$', caseSensitive: false)
        .hasMatch(candidate)) {
      return null;
    }
    try {
      return normalizeHttpUrl(candidate);
    } catch (_) {
      return null;
    }
  }

  static String normalizeHttpUrl(String raw) {
    if (raw.length > maxUrlLength) {
      throw const FormatException('URL troppo lungo.');
    }
    final uri = Uri.parse(raw.trim());
    final scheme = uri.scheme.toLowerCase();
    if (!const {'http', 'https'}.contains(scheme)) {
      throw const FormatException(
        'Sono supportati solo link http e https.',
      );
    }
    if (uri.host.trim().isEmpty) {
      throw const FormatException('Indirizzo web non valido.');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'URL con credenziali non supportato.',
      );
    }
    if (uri.fragment.length > 2000) {
      throw const FormatException('URL non valido.');
    }

    final port = uri.hasPort ? ':${uri.port}' : '';
    final path = uri.path.isEmpty ? '/' : uri.path;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
    return '$scheme://${uri.host.toLowerCase()}$port$path$query$fragment';
  }

  static String appendSection(
    String body,
    String title,
    String content, {
    int maxTotalChars = 200000,
  }) {
    final clean = content.trim();
    if (clean.isEmpty) return body;
    final heading =
        title.trim().isEmpty ? 'Contenuto acquisito' : title.trim();
    final addition =
        '${body.trim().isEmpty ? '' : '\n\n'}## $heading\n\n$clean\n';
    if (body.length + addition.length > maxTotalChars) {
      throw const FormatException(
        'La nota diventerebbe troppo lunga. Riduci il contenuto e riprova.',
      );
    }
    return '$body$addition';
  }

  static bool containsSection(
    String body,
    String title,
    String content,
  ) {
    final clean = content.trim();
    if (clean.isEmpty) return true;
    return body.contains('## ${title.trim()}\n\n$clean');
  }

  static String clipOcr(String text) {
    final value = text.replaceAll('\u0000', ' ').trim();
    return value.length <= maxOcrTextChars
        ? value
        : value.substring(0, maxOcrTextChars);
  }

  static String clipWebText(String text) {
    var value = text
        .replaceAll('\u0000', ' ')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (value.length > maxWebTextChars) {
      value = value.substring(0, maxWebTextChars);
    }
    return value;
  }
}

class WebCapture {
  Future<WebSnapshot> fetch(String rawUrl) async {
    var current = SmartCaptureRules.normalizeHttpUrl(rawUrl);
    final requested = current;
    final client = HttpClient()
      ..autoUncompress = true
      ..connectionTimeout = const Duration(seconds: 8);

    try {
      for (var redirect = 0; redirect < 6; redirect++) {
        await _validatePublicDestination(current);
        final uri = Uri.parse(current);
        final request = await client.getUrl(uri);
        request
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers.set(
            HttpHeaders.userAgentHeader,
            'NotesEcosystem/0.25 Flutter SmartCapture',
          )
          ..headers.set(
            HttpHeaders.acceptHeader,
            'text/html,application/xhtml+xml;q=0.9,*/*;q=0.1',
          );

        final response = await request.close().timeout(
              const Duration(seconds: 10),
            );

        if (response.statusCode >= 300 && response.statusCode <= 399) {
          if (redirect >= 5) {
            throw const FormatException('Troppi reindirizzamenti.');
          }
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) {
            throw const FormatException(
              'Reindirizzamento web non valido.',
            );
          }
          current = SmartCaptureRules.normalizeHttpUrl(
            uri.resolve(location).toString(),
          );
          await response.drain<void>();
          continue;
        }

        if (response.statusCode < 200 || response.statusCode > 299) {
          throw FormatException(
            'La pagina ha risposto con codice HTTP ${response.statusCode}.',
          );
        }

        final contentType =
            response.headers.contentType?.mimeType.toLowerCase() ?? '';
        if (contentType != 'text/html' &&
            contentType != 'application/xhtml+xml') {
          throw const FormatException(
            'Il link non contiene una pagina HTML.',
          );
        }

        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length >
              SmartCaptureRules.maxWebHtmlBytes) {
            throw const FormatException(
              'Pagina web troppo grande per l’acquisizione rapida.',
            );
          }
          bytes.addAll(chunk);
        }
        final charset =
            response.headers.contentType?.charset?.toLowerCase() ?? 'utf-8';
        final html = charset.contains('latin1')
            ? latin1.decode(bytes, allowInvalid: true)
            : utf8.decode(bytes, allowMalformed: true);
        return parseSnapshot(requested, current, html);
      }
    } finally {
      client.close(force: true);
    }

    throw const FormatException(
      'Impossibile completare l’acquisizione web.',
    );
  }

  WebSnapshot parseSnapshot(
    String requestedUrl,
    String finalUrl,
    String html,
  ) {
    var cleaned = html
        .replaceAll(
          RegExp(r'<script\b[^>]*>.*?</script>',
              caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style\b[^>]*>.*?</style>',
              caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(r'<noscript\b[^>]*>.*?</noscript>',
              caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(r'<svg\b[^>]*>.*?</svg>',
              caseSensitive: false, dotAll: true),
          ' ',
        );

    final titleRaw = _first(
      cleaned,
      RegExp(r'<title\b[^>]*>(.*?)</title>',
          caseSensitive: false, dotAll: true),
    );
    var title = _htmlToPlain(titleRaw ?? '');
    if (title.isEmpty) {
      title = Uri.parse(finalUrl).host;
    }
    if (title.length > 300) title = title.substring(0, 300);

    final description = _metaContent(cleaned, 'description') ??
        _metaProperty(cleaned, 'og:description') ??
        '';

    final canonicalRaw = _first(
      cleaned,
      RegExp(
        "<link\\b(?=[^>]*\\brel\\s*=\\s*[\"']?canonical[\"']?)[^>]*\\bhref\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>",
        caseSensitive: false,
        dotAll: true,
      ),
    );

    var canonical = finalUrl;
    if (canonicalRaw != null && canonicalRaw.trim().isNotEmpty) {
      try {
        canonical = SmartCaptureRules.normalizeHttpUrl(
          Uri.parse(finalUrl).resolve(canonicalRaw).toString(),
        );
      } catch (_) {}
    }

    final article = _first(
          cleaned,
          RegExp(r'<article\b[^>]*>(.*?)</article>',
              caseSensitive: false, dotAll: true),
        ) ??
        _first(
          cleaned,
          RegExp(r'<main\b[^>]*>(.*?)</main>',
              caseSensitive: false, dotAll: true),
        ) ??
        _first(
          cleaned,
          RegExp(r'<body\b[^>]*>(.*?)</body>',
              caseSensitive: false, dotAll: true),
        ) ??
        cleaned;

    final readable = article
        .replaceAll(
          RegExp(
            r'</(p|div|section|article|li|h[1-6]|blockquote)>',
            caseSensitive: false,
          ),
          '\n',
        )
        .replaceAll(
          RegExp(r'<br\s*/?>', caseSensitive: false),
          '\n',
        );

    return WebSnapshot(
      requestedUrl: requestedUrl,
      finalUrl: canonical,
      title: title,
      description: _htmlToPlain(description).substring(
        0,
        _htmlToPlain(description).length.clamp(0, 1000).toInt(),
      ),
      text: SmartCaptureRules.clipWebText(_htmlToPlain(readable)),
    );
  }

  Future<void> _validatePublicDestination(String url) async {
    final host = Uri.parse(url).host.toLowerCase();
    if (const {'localhost', 'localhost.localdomain', '0.0.0.0'}
        .contains(host)) {
      throw const FormatException(
        'Indirizzi locali non supportati.',
      );
    }
    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty ||
        addresses.any(_isPrivateOrLocalAddress)) {
      throw const FormatException(
        'Per sicurezza non vengono acquisiti indirizzi di rete locale.',
      );
    }
  }

  bool _isPrivateOrLocalAddress(InternetAddress address) {
    if (address.isLoopback ||
        address.isLinkLocal ||
        address.isMulticast) {
      return true;
    }
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      final a = bytes[0];
      final b = bytes[1];
      return a == 0 ||
          a == 10 ||
          a == 127 ||
          (a == 169 && b == 254) ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168);
    }
    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      return (bytes[0] & 0xFE) == 0xFC;
    }
    return false;
  }

  String? _metaContent(String html, String name) => _first(
        html,
        RegExp(
          '<meta\\b(?=[^>]*\\bname\\s*=\\s*["\\\']?$name["\\\']?)[^>]*\\bcontent\\s*=\\s*["\\\']([^"\\\']*)["\\\'][^>]*>',
          caseSensitive: false,
          dotAll: true,
        ),
      );

  String? _metaProperty(String html, String property) => _first(
        html,
        RegExp(
          '<meta\\b(?=[^>]*\\bproperty\\s*=\\s*["\\\']?$property["\\\']?)[^>]*\\bcontent\\s*=\\s*["\\\']([^"\\\']*)["\\\'][^>]*>',
          caseSensitive: false,
          dotAll: true,
        ),
      );

  String? _first(String input, RegExp regex) =>
      regex.firstMatch(input)?.group(1);

  String _htmlToPlain(String value) => _decodeEntities(
        value
            .replaceAll(RegExp(r'<[^>]+>'), ' ')
            .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
            .replaceAll(RegExp(r'\n[ \t]+'), '\n')
            .replaceAll(RegExp(r'\n{3,}'), '\n\n')
            .trim(),
      );

  String _decodeEntities(String value) => value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}
