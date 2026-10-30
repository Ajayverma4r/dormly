// features/structure/domain/node_names.dart
//
// Client-side mirror of the server's room/bed/floor name rules: names are
// trimmed, inner whitespace collapsed, and must be unique (ignoring case)
// among the children of one parent.

/// Matches the server's limit on node names.
const int maxNodeNameLength = 80;

/// Trimmed name with inner runs of whitespace collapsed to one space.
String normalizeNodeName(String raw) =>
    raw.replaceAll(RegExp(r'\s+'), ' ').trim();

/// How a node is labelled in lists: a bare "109" on the Room level reads
/// "Room 109"; a name that already mentions its level is shown as is.
String nodeDisplayLabel(String raw, String levelName) {
  final name = normalizeNodeName(raw);
  final level = normalizeNodeName(levelName);
  if (level.isEmpty || name.toLowerCase().contains(level.toLowerCase())) {
    return name;
  }
  return '$level $name';
}

/// Comparison key: two names on [levelName] clash when their keys are equal,
/// so "109" and "Room 109" are the same room (as on the server).
String nodeNameKey(String raw, [String levelName = '']) =>
    nodeDisplayLabel(raw, levelName).toLowerCase();

/// The [proposed] names that clash with [existing] names or repeat within
/// [proposed] itself, in the order first seen (each reported once).
List<String> findNodeNameClashes(
  Iterable<String> existing,
  Iterable<String> proposed, {
  String levelName = '',
}) {
  final taken = {for (final n in existing) nodeNameKey(n, levelName)};
  final seen = <String>{};
  final reported = <String>{};
  final clashes = <String>[];
  for (final raw in proposed) {
    if (normalizeNodeName(raw).isEmpty) continue;
    final key = nodeNameKey(raw, levelName);
    if ((taken.contains(key) || !seen.add(key)) && reported.add(key)) {
      clashes.add(normalizeNodeName(raw));
    }
  }
  return clashes;
}
