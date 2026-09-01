import 'package:equatable/equatable.dart';
import 'package:sello/services/updates/release_app_kind.dart';
import 'package:sello/shared/models/app_version.dart';

/// Result of comparing the installed build to remote release metadata.
enum UpdateCheckStatus {
  upToDate,
  updateAvailable,
  updateRequired,
  checkFailed;

  bool get isBlocking => this == UpdateCheckStatus.updateRequired;
  bool get canContinue => this != UpdateCheckStatus.updateRequired;
}

/// Destinations for a later install/download step — not used for install yet.
enum ReleaseDestinationKind {
  apk,
  appStore,
  testFlight,
  web,
  other;

  static ReleaseDestinationKind fromJson(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'apk' => ReleaseDestinationKind.apk,
      'app_store' || 'appstore' => ReleaseDestinationKind.appStore,
      'testflight' || 'test_flight' => ReleaseDestinationKind.testFlight,
      'web' => ReleaseDestinationKind.web,
      _ => ReleaseDestinationKind.other,
    };
  }
}

enum AppReleasePlatform {
  android,
  ios,
  web,
  other;

  String get jsonKey => name;

  static AppReleasePlatform tryParse(String? raw) {
    return switch (raw?.trim().toLowerCase()) {
      'android' => AppReleasePlatform.android,
      'ios' => AppReleasePlatform.ios,
      'web' => AppReleasePlatform.web,
      _ => AppReleasePlatform.other,
    };
  }
}

class ReleaseChannelInfo extends Equatable {
  const ReleaseChannelInfo({
    required this.platform,
    this.destinationUrl,
    this.destinationKind = ReleaseDestinationKind.other,
  });

  final AppReleasePlatform platform;
  final String? destinationUrl;
  final ReleaseDestinationKind destinationKind;

  bool get hasDestination {
    final url = destinationUrl?.trim() ?? '';
    return url.startsWith('http://') || url.startsWith('https://');
  }

  factory ReleaseChannelInfo.fromJson(
    AppReleasePlatform platform,
    Map<String, dynamic>? json,
  ) {
    if (json == null) {
      return ReleaseChannelInfo(platform: platform);
    }
    final url = json['destination_url']?.toString().trim();
    return ReleaseChannelInfo(
      platform: platform,
      destinationUrl: (url == null || url.isEmpty) ? null : url,
      destinationKind: ReleaseDestinationKind.fromJson(
        json['destination_kind']?.toString(),
      ),
    );
  }

  @override
  List<Object?> get props => [platform, destinationUrl, destinationKind];
}

class SelloReleaseManifest extends Equatable {
  const SelloReleaseManifest({
    required this.latest,
    this.releasedAt,
    this.notes,
    this.minimum,
    this.minimumEnforced = false,
    this.platforms = const {},
    this.schemaVersion = 1,
  });

  final AppVersion latest;
  final DateTime? releasedAt;
  final String? notes;
  final AppVersion? minimum;
  final bool minimumEnforced;
  final Map<AppReleasePlatform, ReleaseChannelInfo> platforms;
  final int schemaVersion;

  ReleaseChannelInfo channelFor(AppReleasePlatform platform) {
    return platforms[platform] ?? ReleaseChannelInfo(platform: platform);
  }

  static SelloReleaseManifest parse(
    dynamic raw, {
    ReleaseAppKind? app,
  }) {
    if (raw is! Map) {
      throw const FormatException('Release configuration is not an object.');
    }
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final schemaVersion = (json['schema_version'] as num?)?.toInt() ?? 1;
    final appsRaw = json['apps'];
    final Map<String, dynamic> entry;

    if (appsRaw is Map) {
      if (app == null) {
        throw const FormatException('Missing app selection.');
      }
      final selected = appsRaw[app.jsonKey];
      if (selected is! Map) {
        throw FormatException(
          'Missing release information for ${app.jsonKey}.',
        );
      }
      entry = selected.map((key, value) => MapEntry(key.toString(), value));
    } else {
      entry = json;
    }

    return _fromAppEntry(entry, schemaVersion: schemaVersion);
  }

  static SelloReleaseManifest? tryParse(
    dynamic raw, {
    ReleaseAppKind? app,
  }) {
    try {
      return parse(raw, app: app);
    } catch (_) {
      return null;
    }
  }

  static SelloReleaseManifest _fromAppEntry(
    Map<String, dynamic> json, {
    required int schemaVersion,
  }) {
    final latestRaw = json['latest'];
    if (latestRaw is! Map) {
      throw const FormatException('Missing latest release information.');
    }
    final latestMap = latestRaw.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final latest = _parseVersionMap(latestMap, label: 'latest');

    AppVersion? minimum;
    var minimumEnforced = false;
    final minimumRaw = json['minimum'];
    if (minimumRaw is Map) {
      final minimumMap = minimumRaw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      minimum = _parseVersionMap(minimumMap, label: 'minimum');
      minimumEnforced = minimumMap['enforced'] == true;
    }

    final platforms = <AppReleasePlatform, ReleaseChannelInfo>{};
    final platformsRaw = json['platforms'];
    if (platformsRaw is Map) {
      for (final entry in platformsRaw.entries) {
        final platform = AppReleasePlatform.tryParse(entry.key.toString());
        if (platform == AppReleasePlatform.other) continue;
        final value = entry.value;
        platforms[platform] = ReleaseChannelInfo.fromJson(
          platform,
          value is Map
              ? value.map((k, v) => MapEntry(k.toString(), v))
              : null,
        );
      }
    }

    return SelloReleaseManifest(
      latest: latest,
      releasedAt: DateTime.tryParse(latestMap['released_at']?.toString() ?? ''),
      notes: _optionalText(latestMap['notes'] ?? json['notes']),
      minimum: minimum,
      minimumEnforced: minimumEnforced,
      platforms: platforms,
      schemaVersion: schemaVersion,
    );
  }

  static AppVersion _parseVersionMap(
    Map<String, dynamic> json, {
    required String label,
  }) {
    final version = json['version']?.toString();
    if (version == null || version.trim().isEmpty) {
      throw FormatException('Missing $label version.');
    }
    final buildRaw = json['build'];
    int? build;
    if (buildRaw is num) {
      build = buildRaw.toInt();
    } else if (buildRaw != null) {
      build = int.tryParse(buildRaw.toString());
    }
    if (build == null || build < 0) {
      throw FormatException('Missing or invalid $label build number.');
    }
    return AppVersion.parse(version, buildOverride: build);
  }

  static String? _optionalText(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  List<Object?> get props => [
        latest,
        releasedAt,
        notes,
        minimum,
        minimumEnforced,
        platforms,
        schemaVersion,
      ];
}

class UpdateCheckSnapshot extends Equatable {
  const UpdateCheckSnapshot({
    required this.status,
    required this.installed,
    this.latest,
    this.minimum,
    this.notes,
    this.releasedAt,
    this.channel,
    this.checkedAt,
    this.failureReason,
  });

  final UpdateCheckStatus status;
  final AppVersion installed;
  final AppVersion? latest;
  final AppVersion? minimum;
  final String? notes;
  final DateTime? releasedAt;
  final ReleaseChannelInfo? channel;
  final DateTime? checkedAt;
  final String? failureReason;

  bool get hasUpdate =>
      status == UpdateCheckStatus.updateAvailable ||
      status == UpdateCheckStatus.updateRequired;

  String get latestLabel => latest?.identity ?? '—';

  static UpdateCheckSnapshot failed({
    required AppVersion installed,
    String? reason,
    DateTime? checkedAt,
  }) {
    return UpdateCheckSnapshot(
      status: UpdateCheckStatus.checkFailed,
      installed: installed,
      checkedAt: checkedAt ?? DateTime.now().toUtc(),
      failureReason: reason,
    );
  }

  @override
  List<Object?> get props => [
        status,
        installed,
        latest,
        minimum,
        notes,
        releasedAt,
        channel,
        checkedAt,
        failureReason,
      ];
}

/// Pure comparison used by the update service and tests.
abstract final class UpdatePolicy {
  static UpdateCheckStatus resolve({
    required AppVersion installed,
    required SelloReleaseManifest manifest,
  }) {
    final minimum = manifest.minimum;
    if (manifest.minimumEnforced &&
        minimum != null &&
        installed < minimum) {
      return UpdateCheckStatus.updateRequired;
    }
    if (installed < manifest.latest) {
      return UpdateCheckStatus.updateAvailable;
    }
    return UpdateCheckStatus.upToDate;
  }
}
