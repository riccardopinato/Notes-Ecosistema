import 'dart:math' as math;

abstract interface class SemanticEmbeddingEngine {
  String get id;
  int get dimensions;
  List<double> embed(String text);
}

class LocalHashEmbeddingEngine implements SemanticEmbeddingEngine {
  const LocalHashEmbeddingEngine({this.dimensions = 192})
      : assert(dimensions >= 64 && dimensions <= 1024);

  @override
  final int dimensions;

  @override
  String get id => 'local-hash-semantic-v1';

  static const maxInputChars = 60000;

  @override
  List<double> embed(String text) {
    final source =
        text.length <= maxInputChars ? text : text.substring(0, maxInputChars);
    final tokens = tokenize(source);
    if (tokens.isEmpty) return List<double>.filled(dimensions, 0);

    final vector = List<double>.filled(dimensions, 0);
    for (final token in tokens) {
      _accumulate(vector, 'w:$token', 1.0);
      final stem = _stem(token);
      if (stem != token) _accumulate(vector, 's:$stem', 0.8);

      final concept = _conceptAliases[token] ?? _conceptAliases[stem];
      if (concept != null) {
        _accumulate(vector, 'c:$concept', 1.5);
      }

      if (token.length >= 4) {
        final padded = '^${token}_';
        for (var i = 0; i <= padded.length - 3; i++) {
          _accumulate(vector, 'g:${padded.substring(i, i + 3)}', 0.18);
        }
      }
    }

    for (var i = 0; i + 1 < tokens.length; i++) {
      _accumulate(vector, 'b:${tokens[i]}_${tokens[i + 1]}', 0.35);
    }

    final norm = math.sqrt(
      vector.fold<double>(0, (sum, value) => sum + value * value),
    );
    if (norm <= 0) return vector;
    for (var i = 0; i < vector.length; i++) {
      vector[i] /= norm;
    }
    return vector;
  }

  void _accumulate(List<double> vector, String feature, double weight) {
    final hash = _fnv1a(feature);
    final index = (hash & 0x7fffffff) % vector.length;
    final sign = (hash & 0x80000000) == 0 ? 1.0 : -1.0;
    vector[index] += weight * sign;
  }

  static int _fnv1a(String value) {
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static List<String> tokenize(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'https?://\S+'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
    return normalized
        .split(RegExp(r'\s+'))
        .where(
          (token) => token.length >= 2 && !_stopWords.contains(token),
        )
        .toList(growable: false);
  }

  static double cosine(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0;
    var dot = 0.0;
    var aNorm = 0.0;
    var bNorm = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      aNorm += a[i] * a[i];
      bNorm += b[i] * b[i];
    }
    if (aNorm <= 0 || bNorm <= 0) return 0;
    return dot / math.sqrt(aNorm * bNorm);
  }

  static String _stem(String token) {
    for (final suffix in const [
      'mente',
      'ments',
      'ment',
      'zioni',
      'zione',
      'tions',
      'tion',
      'ando',
      'endo',
      'ing',
      'ato',
      'ito',
      'are',
      'ere',
      'ire',
      'ati',
      'iti',
      'ale',
      'ali',
      'es',
      's',
    ]) {
      if (token.length > suffix.length + 3 && token.endsWith(suffix)) {
        return token.substring(0, token.length - suffix.length);
      }
    }
    return token;
  }

  static const _conceptAliases = <String, String>{
    'auto': 'mobility-car',
    'automobile': 'mobility-car',
    'macchina': 'mobility-car',
    'car': 'mobility-car',
    'vehicle': 'mobility-car',
    'voiture': 'mobility-car',
    'coche': 'mobility-car',
    'carro': 'mobility-car',
    'batteria': 'energy-battery',
    'batterie': 'energy-battery',
    'battery': 'energy-battery',
    'batteries': 'energy-battery',
    'accumulatore': 'energy-battery',
    'autonomia': 'energy-range',
    'range': 'energy-range',
    'endurance': 'energy-range',
    'ricarica': 'energy-charge',
    'ricaricare': 'energy-charge',
    'charge': 'energy-charge',
    'charging': 'energy-charge',
    'viaggio': 'travel',
    'viaggi': 'travel',
    'vacanza': 'travel',
    'vacanze': 'travel',
    'travel': 'travel',
    'trip': 'travel',
    'journey': 'travel',
    'voyage': 'travel',
    'viaje': 'travel',
    'reuniao': 'meeting',
    'riunione': 'meeting',
    'riunioni': 'meeting',
    'meeting': 'meeting',
    'call': 'meeting',
    'appuntamento': 'meeting',
    'review': 'review',
    'revisione': 'review',
    'controllo': 'review',
    'lavoro': 'work',
    'ufficio': 'work',
    'work': 'work',
    'office': 'work',
    'job': 'work',
    'attivita': 'task',
    'task': 'task',
    'todo': 'task',
    'compito': 'task',
    'scadenza': 'deadline',
    'deadline': 'deadline',
    'termine': 'deadline',
    'nota': 'note',
    'note': 'note',
    'appunto': 'note',
    'appunti': 'note',
    'casa': 'home',
    'abitazione': 'home',
    'home': 'home',
    'house': 'home',
    'maison': 'home',
    'salute': 'health',
    'health': 'health',
    'benessere': 'health',
    'fitness': 'fitness',
    'allenamento': 'fitness',
    'workout': 'fitness',
    'corsa': 'running',
    'running': 'running',
    'run': 'running',
    'fotografia': 'photography',
    'foto': 'photography',
    'photography': 'photography',
    'photo': 'photography',
    'studio': 'study',
    'studiare': 'study',
    'study': 'study',
    'learn': 'study',
    'learning': 'study',
    'ricerca': 'research',
    'research': 'research',
    'fonte': 'source',
    'source': 'source',
    'documento': 'document',
    'document': 'document',
    'progetto': 'project',
    'project': 'project',
    'idea': 'idea',
    'concept': 'idea',
  };

  static const _stopWords = <String>{
    'che',
    'con',
    'del',
    'della',
    'delle',
    'degli',
    'dei',
    'per',
    'una',
    'uno',
    'gli',
    'le',
    'la',
    'il',
    'lo',
    'un',
    'di',
    'da',
    'in',
    'su',
    'e',
    'o',
    'a',
    'the',
    'and',
    'for',
    'with',
    'this',
    'that',
    'of',
    'to',
    'is',
    'on',
    'de',
    'des',
    'les',
    'el',
    'los',
    'las',
    'por',
    'para',
    'com',
    'um',
    'uma',
    'der',
    'die',
    'das',
    'und',
  };
}
