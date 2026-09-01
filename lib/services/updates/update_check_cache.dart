import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sello/services/updates/release_manifest_config.dart';
import 'package:sello/shared/models/app_version.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';

/// Local cache so startup does not hit the release endpoint every rebuild.
class UpdateCheckCache {
  UpdateCheckCache({
    this.ttl = ReleaseManifestConfig.checkInterval,
    this.appKey,
  });

  final Duration ttl;
  final String? appKey;

  static const _checkedAtKey = 'sello.update.checked_at';
  static const _statusKey = 'sello.update.status';
  static const _postponedKey = 'sello.update.postponed_identity';
  static const _snapshotKey = 'sello.update.snapshot';

  Future<DateTime?> lastCheckedAt() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_checkedAtKey) ?? '');
  }

  Future<bool> isFresh() async {
    final last = await lastCheckedAt();
    if (last == null) return false;
    return DateTime.now().toUtc().difference(last) < ttl;
  }

  Future<String?> postponedIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_postponedKey)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> postpone(String identity) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_postponedKey, identity);
  }

  Future<UpdateCheckSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_snapshotKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final map = json.map((key, value) => MapEntry(key.toString(), value));
      final storedApp = map['app']?.toString();
      if (appKey != null && storedApp != null && storedApp != appKey) {
        return null;
      }
      final installed = AppVersion.tryParse(map['installed']?.toString());
      if (installed == null) return null;
      final statusName = map['status']?.toString();
      final status = UpdateCheckStatus.values.where((s) => s.name == statusName);
      if (status.isEmpty) return null;
      final platform = AppReleasePlatform.tryParse(map['platform']?.toString());
      return UpdateCheckSnapshot(
        status: status.first,
        installed: installed,
        latest: AppVersion.tryParse(map['latest']?.toString()),
        minimum: AppVersion.tryParse(map['minimum']?.toString()),
        notes: _text(map['notes']),
        releasedAt: DateTime.tryParse(map['released_at']?.toString() ?? ''),
        channel: ReleaseChannelInfo(
          platform: platform,
          destinationUrl: _text(map['destination_url']),
          destinationKind: ReleaseDestinationKind.fromJson(
            map['destination_kind']?.toString(),
          ),
        ),
        checkedAt: DateTime.tryParse(map['checked_at']?.toString() ?? ''),
        failureReason: _text(map['failure_reason']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(UpdateCheckSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    final checkedAt = (snapshot.checkedAt ?? DateTime.now().toUtc())
        .toIso8601String();
    await prefs.setString(_checkedAtKey, checkedAt);
    await prefs.setString(_statusKey, snapshot.status.name);
    await prefs.setString(
      _snapshotKey,
      jsonEncode({
        'app': appKey,
        'status': snapshot.status.name,
        'installed': snapshot.installed.identity,
        'latest': snapshot.latest?.identity,
        'minimum': snapshot.minimum?.identity,
        'notes': snapshot.notes,
        'released_at': snapshot.releasedAt?.toIso8601String(),
        'destination_url': snapshot.channel?.destinationUrl,
        'destination_kind': snapshot.channel?.destinationKind.name,
        'platform': snapshot.channel?.platform.name,
        'checked_at': checkedAt,
        'failure_reason': snapshot.failureReason,
      }),
    );
  }

  static String? _text(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
