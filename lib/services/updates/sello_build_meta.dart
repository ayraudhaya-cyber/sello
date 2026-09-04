/// Compile-time build metadata for support (optional; never secrets).
///
/// Version/build come from [PackageInfo] / `pubspec.yaml`. This only adds a
/// short git revision when the CI build passes `--dart-define=SELLO_GIT_SHA=…`
/// (Vercel: `VERCEL_GIT_COMMIT_SHA`).
abstract final class SelloBuildMeta {
  /// Full or truncated commit SHA from the web/native CI build.
  static const String gitSha = String.fromEnvironment(
    'SELLO_GIT_SHA',
    defaultValue: '',
  );

  /// Short revision for UI (7 chars). Null when not baked into this build.
  static String? get shortRevision {
    final trimmed = gitSha.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= 7 ? trimmed : trimmed.substring(0, 7);
  }
}
