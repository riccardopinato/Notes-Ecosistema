enum StableLinkKind { object, project, study }

class StableLinkTarget {
  const StableLinkTarget({
    required this.kind,
    required this.id,
  });

  final StableLinkKind kind;
  final String id;
}

abstract final class StableLinks {
  static Uri object(String id) => _build(StableLinkKind.object, id);
  static Uri project(String id) => _build(StableLinkKind.project, id);
  static Uri study(String id) => _build(StableLinkKind.study, id);

  static Uri _build(StableLinkKind kind, String id) {
    final clean = id.trim();
    if (clean.isEmpty || clean.length > 200 || clean.contains('/')) {
      throw const FormatException('ID collegamento non valido.');
    }
    return Uri(
      scheme: 'notes',
      host: kind.name,
      pathSegments: [clean],
    );
  }

  static StableLinkTarget? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'notes') return null;
    final kinds = StableLinkKind.values.where(
      (kind) => kind.name == uri.host.toLowerCase(),
    );
    if (kinds.isEmpty || uri.pathSegments.length != 1) return null;
    final id = uri.pathSegments.single.trim();
    if (id.isEmpty || id.length > 200) return null;
    return StableLinkTarget(kind: kinds.first, id: id);
  }
}
