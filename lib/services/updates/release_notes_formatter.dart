/// Formats release `latest.notes` for What’s New surfaces.
///
/// Notes remain a single string in the release manifest. Lines may be separated
/// by newlines or semicolons; leading bullet markers are stripped then re-added
/// by the UI.
abstract final class ReleaseNotesFormatter {
  static List<String> bullets(String? notes) {
    final raw = notes?.trim() ?? '';
    if (raw.isEmpty) return const [];

    final parts = raw.contains('\n')
        ? raw.split('\n')
        : raw.split(RegExp(r'\s*;\s*'));

    return [
      for (final part in parts)
        if (_clean(part) case final line? when line.isNotEmpty) line,
    ];
  }

  static String? _clean(String part) {
    var line = part.trim();
    if (line.isEmpty) return null;
    line = line.replaceFirst(RegExp(r'^[•\-\*]\s*'), '').trim();
    return line.isEmpty ? null : line;
  }
}
