/// Case-insensitive unique option names, keeping the first casing seen.
List<String> uniqueOptionLabels(Iterable<String> labels) {
  final seen = <String, String>{};
  for (final raw in labels) {
    final label = raw.trim();
    if (label.isEmpty) continue;
    seen.putIfAbsent(label.toLowerCase(), () => label);
  }
  return List<String>.unmodifiable(seen.values);
}

/// Autocomplete matches for a typed option name.
///
/// Empty query yields no suggestions so the field stays quiet until the user
/// starts typing. Prefix matches come first, then other contains matches.
List<String> filterOptionNameSuggestions({
  required String query,
  required Iterable<String> saved,
  int limit = 8,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];

  final unique = uniqueOptionLabels(saved);
  final starts = <String>[];
  final contains = <String>[];
  for (final label in unique) {
    final lower = label.toLowerCase();
    if (lower.startsWith(q)) {
      starts.add(label);
    } else if (lower.contains(q)) {
      contains.add(label);
    }
  }
  return [...starts, ...contains].take(limit).toList(growable: false);
}
