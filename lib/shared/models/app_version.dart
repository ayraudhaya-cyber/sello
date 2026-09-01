import 'package:equatable/equatable.dart';

/// Installed or published Sello version (`1.0.0`) plus build number (`1`).
class AppVersion extends Equatable implements Comparable<AppVersion> {
  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.build = 0,
  });

  final int major;
  final int minor;
  final int patch;
  final int build;

  String get versionName => '$major.$minor.$patch';

  String get identity => '$versionName+$build';

  /// Parses `1.10.0`, `1.10.0+2`, or `1.10`.
  factory AppVersion.parse(String raw, {int? buildOverride}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Version is empty.');
    }

    final plus = trimmed.split('+');
    final core = plus.first.trim();
    final parsedBuild = plus.length > 1
        ? int.tryParse(plus[1].trim())
        : null;
    if (plus.length > 1 && parsedBuild == null) {
      throw FormatException('Invalid build number in "$raw".');
    }

    final parts = core.split('.');
    if (parts.length < 2 || parts.length > 3) {
      throw FormatException('Invalid version "$raw".');
    }

    int parsePart(String value, String label) {
      final parsed = int.tryParse(value.trim());
      if (parsed == null || parsed < 0) {
        throw FormatException('Invalid $label in "$raw".');
      }
      return parsed;
    }

    return AppVersion(
      major: parsePart(parts[0], 'major'),
      minor: parsePart(parts[1], 'minor'),
      patch: parts.length == 3 ? parsePart(parts[2], 'patch') : 0,
      build: buildOverride ?? parsedBuild ?? 0,
    );
  }

  static AppVersion? tryParse(String? raw, {int? buildOverride}) {
    if (raw == null) return null;
    try {
      return AppVersion.parse(raw, buildOverride: buildOverride);
    } catch (_) {
      return null;
    }
  }

  factory AppVersion.fromNameAndBuild(String versionName, String buildNumber) {
    final parsedBuild = int.tryParse(buildNumber.trim());
    if (parsedBuild == null || parsedBuild < 0) {
      throw FormatException('Invalid build number "$buildNumber".');
    }
    return AppVersion.parse(versionName, buildOverride: parsedBuild);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;
  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  @override
  String toString() => identity;

  @override
  List<Object?> get props => [major, minor, patch, build];
}
