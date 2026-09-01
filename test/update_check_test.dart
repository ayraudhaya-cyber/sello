import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sello/services/updates/app_version_reader.dart';
import 'package:sello/services/updates/release_app_kind.dart';
import 'package:sello/services/updates/release_manifest_client.dart';
import 'package:sello/services/updates/update_check_cache.dart';
import 'package:sello/services/updates/update_check_messages.dart';
import 'package:sello/services/updates/update_check_service.dart';
import 'package:sello/shared/models/app_version.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';
import 'package:sello/shared/models/user_role.dart';

void main() {
  group('AppVersion comparison', () {
    test('orders 1.9.0 below 1.10.0', () {
      expect(AppVersion.parse('1.9.0') < AppVersion.parse('1.10.0'), isTrue);
      expect(AppVersion.parse('1.10.0') > AppVersion.parse('1.9.0'), isTrue);
    });

    test('uses build number as a tiebreaker', () {
      expect(
        AppVersion.parse('1.0.0+2') > AppVersion.parse('1.0.0+1'),
        isTrue,
      );
      expect(
        AppVersion.fromNameAndBuild('1.0.0', '2') >
            AppVersion.fromNameAndBuild('1.0.0', '1'),
        isTrue,
      );
    });

    test('equal versions compare equal', () {
      expect(AppVersion.parse('1.0.0+1'), AppVersion.parse('1.0.0+1'));
      expect(
        AppVersion.parse('1.0.0+1').compareTo(AppVersion.parse('1.0.0+1')),
        0,
      );
    });
  });

  group('UpdatePolicy', () {
    const installed = AppVersion(major: 1, minor: 0, patch: 0, build: 1);

    test('installed equals latest → up to date', () {
      final manifest = SelloReleaseManifest(
        latest: installed,
        minimum: installed,
      );
      expect(
        UpdatePolicy.resolve(installed: installed, manifest: manifest),
        UpdateCheckStatus.upToDate,
      );
    });

    test('installed is older → update available', () {
      final manifest = SelloReleaseManifest(
        latest: const AppVersion(major: 1, minor: 0, patch: 1, build: 2),
      );
      expect(
        UpdatePolicy.resolve(installed: installed, manifest: manifest),
        UpdateCheckStatus.updateAvailable,
      );
    });

    test('installed below enforced minimum → update required', () {
      final manifest = SelloReleaseManifest(
        latest: const AppVersion(major: 1, minor: 0, patch: 1, build: 2),
        minimum: const AppVersion(major: 1, minor: 0, patch: 1, build: 2),
        minimumEnforced: true,
      );
      expect(
        UpdatePolicy.resolve(installed: installed, manifest: manifest),
        UpdateCheckStatus.updateRequired,
      );
    });

    test('minimum is ignored when not enforced', () {
      final manifest = SelloReleaseManifest(
        latest: installed,
        minimum: const AppVersion(major: 2, minor: 0, patch: 0, build: 1),
      );
      expect(
        UpdatePolicy.resolve(installed: installed, manifest: manifest),
        UpdateCheckStatus.upToDate,
      );
    });
  });

  group('SelloReleaseManifest parsing', () {
    test('reads platform-specific destinations', () {
      final manifest = SelloReleaseManifest.parse({
        'schema_version': 1,
        'latest': {
          'version': '1.0.1',
          'build': 4,
          'released_at': '2026-08-17',
          'notes': 'Bug fixes',
        },
        'minimum': {
          'version': '1.0.0',
          'build': 1,
          'enforced': false,
        },
        'platforms': {
          'android': {
            'destination_kind': 'apk',
            'destination_url': 'https://cdn.example/sello.apk',
          },
          'ios': {
            'destination_kind': 'testflight',
            'destination_url': 'https://testflight.apple.com/join/abc',
          },
          'web': {
            'destination_kind': 'web',
            'destination_url': 'https://app.sello.example',
          },
        },
      });

      expect(manifest.latest.identity, '1.0.1+4');
      expect(manifest.minimumEnforced, isFalse);
      expect(
        manifest.channelFor(AppReleasePlatform.android).destinationUrl,
        'https://cdn.example/sello.apk',
      );
      expect(
        manifest.channelFor(AppReleasePlatform.ios).destinationKind,
        ReleaseDestinationKind.testFlight,
      );
      expect(
        manifest.channelFor(AppReleasePlatform.web).hasDestination,
        isTrue,
      );
    });

    test('rejects missing latest version', () {
      expect(
        () => SelloReleaseManifest.parse({'latest': {}}),
        throwsFormatException,
      );
      expect(SelloReleaseManifest.tryParse('nope'), isNull);
    });

    test('schema 2 selects sales_rep independently of owner_manager', () {
      final sales = SelloReleaseManifest.parse(
        _dualAppPayload(),
        app: ReleaseAppKind.salesRep,
      );
      final owner = SelloReleaseManifest.parse(
        _dualAppPayload(),
        app: ReleaseAppKind.ownerManager,
      );

      expect(sales.schemaVersion, 2);
      expect(sales.latest.identity, '1.0.2+3');
      expect(sales.notes, 'Testing the update flow.');
      expect(owner.latest.identity, '1.0.0+1');
      expect(owner.notes, isNull);
      expect(sales.latest, isNot(owner.latest));
    });

    test('schema 2 android destinations are app-specific', () {
      final payload = _dualAppPayload();
      expect(
        SelloReleaseManifest.parse(payload, app: ReleaseAppKind.salesRep)
            .channelFor(AppReleasePlatform.android)
            .destinationUrl,
        'https://cashro.pro/sello-updates/sales-rep/sello-sales-rep.apk',
      );
      expect(
        SelloReleaseManifest.parse(payload, app: ReleaseAppKind.ownerManager)
            .channelFor(AppReleasePlatform.android)
            .destinationUrl,
        'https://cashro.pro/sello-updates/owner-manager/sello-owner-manager.apk',
      );
    });

    test('schema 2 missing app entry fails safely', () {
      expect(
        SelloReleaseManifest.tryParse(
          {
            'schema_version': 2,
            'apps': {
              'owner_manager': {
                'latest': {'version': '1.0.0', 'build': 1},
              },
            },
          },
          app: ReleaseAppKind.salesRep,
        ),
        isNull,
      );
      expect(
        () => SelloReleaseManifest.parse(
          _dualAppPayload(),
        ),
        throwsFormatException,
      );
    });
  });

  group('ReleaseAppKind', () {
    test('maps workspace roles without duplicating a flavour system', () {
      expect(
        ReleaseAppKind.fromUserRole(UserRole.salesRepresentative),
        ReleaseAppKind.salesRep,
      );
      expect(
        ReleaseAppKind.fromUserRole(UserRole.owner),
        ReleaseAppKind.ownerManager,
      );
      expect(
        ReleaseAppKind.fromUserRole(UserRole.manager),
        ReleaseAppKind.ownerManager,
      );
    });
  });

  group('ReleaseManifestClient', () {
    test('parses a valid payload', () async {
      final client = ReleaseManifestClient(
        httpClient: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'latest': {'version': '1.2.0', 'build': 8},
            }),
            200,
          );
        }),
      );

      final manifest = await client.fetch(url: 'https://example.test/sello-release.json');
      expect(manifest.latest.identity, '1.2.0+8');
    });

    test('invalid JSON becomes a fetch exception', () async {
      final client = ReleaseManifestClient(
        httpClient: MockClient((_) async => http.Response('{', 200)),
      );

      expect(
        () => client.fetch(url: 'https://example.test/sello-release.json'),
        throwsA(isA<ReleaseManifestFetchException>()),
      );
    });

    test('network failure becomes a fetch exception', () async {
      final client = ReleaseManifestClient(
        httpClient: MockClient((_) async => throw TimeoutException('offline')),
      );

      expect(
        () => client.fetch(url: 'https://example.test/sello-release.json'),
        throwsA(isA<ReleaseManifestFetchException>()),
      );
    });
  });

  group('UpdateCheckService', () {
    test('network failure returns checkFailed and does not throw', () async {
      final service = _updateService(
        installed: const AppVersion(major: 1, minor: 0, patch: 0, build: 1),
        app: ReleaseAppKind.salesRep,
        httpClient: MockClient((_) async => throw Exception('offline')),
      );

      final snapshot = await service.check(force: true);
      expect(snapshot.status, UpdateCheckStatus.checkFailed);
      expect(snapshot.installed.versionName, '1.0.0');
    });

    test('invalid configuration returns checkFailed', () async {
      final service = _updateService(
        installed: const AppVersion(major: 1, minor: 0, patch: 0, build: 1),
        app: ReleaseAppKind.salesRep,
        httpClient: MockClient(
          (_) async => http.Response('{"latest":{}}', 200),
        ),
      );

      final snapshot = await service.check(force: true);
      expect(snapshot.status, UpdateCheckStatus.checkFailed);
    });

    test('missing app entry fails safely without blocking', () async {
      final service = _updateService(
        installed: const AppVersion(major: 1, minor: 0, patch: 1, build: 2),
        app: ReleaseAppKind.salesRep,
        payload: {
          'schema_version': 2,
          'apps': {
            'owner_manager': {
              'latest': {'version': '9.9.9', 'build': 99},
            },
          },
        },
      );

      final snapshot = await service.check(force: true);
      expect(snapshot.status, UpdateCheckStatus.checkFailed);
    });

    test('sales rep receives its own release, not owner/manager', () async {
      final snapshot = await _updateService(
        installed: const AppVersion(major: 1, minor: 0, patch: 1, build: 2),
        app: ReleaseAppKind.salesRep,
      ).check(force: true);

      expect(snapshot.status, UpdateCheckStatus.updateAvailable);
      expect(snapshot.latest?.identity, '1.0.2+3');
      expect(snapshot.notes, 'Testing the update flow.');
      expect(
        snapshot.channel?.destinationUrl,
        'https://cashro.pro/sello-updates/sales-rep/sello-sales-rep.apk',
      );
    });

    test('owner/manager receives its own release, not sales rep', () async {
      final snapshot = await _updateService(
        installed: const AppVersion(major: 1, minor: 0, patch: 0, build: 1),
        app: ReleaseAppKind.ownerManager,
      ).check(force: true);

      expect(snapshot.status, UpdateCheckStatus.upToDate);
      expect(snapshot.latest?.identity, '1.0.0+1');
      expect(
        snapshot.channel?.destinationUrl,
        'https://cashro.pro/sello-updates/owner-manager/sello-owner-manager.apk',
      );
    });

    test('sales rep does not treat owner/manager latest as its own', () async {
      final sales = await _updateService(
        installed: const AppVersion(major: 1, minor: 0, patch: 0, build: 1),
        app: ReleaseAppKind.salesRep,
      ).check(force: true);
      final owner = await _updateService(
        installed: const AppVersion(major: 1, minor: 0, patch: 0, build: 1),
        app: ReleaseAppKind.ownerManager,
      ).check(force: true);

      expect(sales.status, UpdateCheckStatus.updateAvailable);
      expect(owner.status, UpdateCheckStatus.upToDate);
      expect(sales.latest?.identity, isNot(owner.latest?.identity));
    });

    test('same version and build reports up to date', () async {
      final snapshot = await _updateService(
        installed: const AppVersion(major: 1, minor: 0, patch: 2, build: 3),
        app: ReleaseAppKind.salesRep,
      ).check(force: true);

      expect(snapshot.status, UpdateCheckStatus.upToDate);
    });

    test('required update still works for the selected app', () async {
      final snapshot = await _updateService(
        installed: const AppVersion(major: 1, minor: 0, patch: 0, build: 1),
        app: ReleaseAppKind.salesRep,
        payload: _dualAppPayload(
          salesRep: {
            'latest': {'version': '1.0.2', 'build': 3},
            'minimum': {
              'version': '1.0.2',
              'build': 3,
              'enforced': true,
            },
          },
        ),
      ).check(force: true);

      expect(snapshot.status, UpdateCheckStatus.updateRequired);
    });

    test('older install reports update available', () async {
      final service = _updateService(
        installed: const AppVersion(major: 1, minor: 0, patch: 0, build: 1),
        app: ReleaseAppKind.salesRep,
        payload: {
          'latest': {'version': '1.0.1', 'build': 2},
          'platforms': {
            'android': {
              'destination_kind': 'apk',
              'destination_url': 'https://cdn.example/sello.apk',
            },
          },
        },
      );

      final snapshot = await service.check(force: true);
      expect(snapshot.status, UpdateCheckStatus.updateAvailable);
      expect(snapshot.channel?.hasDestination, isTrue);
    });

    test('uses fallback manifest when the file URL is missing', () async {
      final service = UpdateCheckService(
        versionReader: _FixedVersionReader(
          const AppVersion(major: 1, minor: 0, patch: 1, build: 2),
        ),
        client: ReleaseManifestClient(),
        cache: _MemoryCache(),
        releaseApp: ReleaseAppKind.salesRep,
        fallbackManifest: () async => SelloReleaseManifest.parse({
          'latest': {'version': '1.0.1', 'build': 2},
        }),
      );

      final snapshot = await service.check(force: true);
      expect(snapshot.status, UpdateCheckStatus.upToDate);
      expect(snapshot.latest?.identity, '1.0.1+2');
    });
  });

  group('UpdateCheckMessages', () {
    const installed = AppVersion(major: 1, minor: 0, patch: 1, build: 2);

    test('up to date is not phrased as a failure', () {
      final snapshot = UpdateCheckSnapshot(
        status: UpdateCheckStatus.upToDate,
        installed: installed,
        latest: installed,
      );
      expect(
        UpdateCheckMessages.manualResult(snapshot),
        "You're on the latest version.",
      );
    });

    test('missing source is distinct from up to date', () {
      final snapshot = UpdateCheckSnapshot.failed(
        installed: installed,
        reason: 'Release information is not configured.',
      );
      expect(
        UpdateCheckMessages.manualResult(snapshot),
        contains('isn’t set up'),
      );
    });
  });
}

class _FixedVersionReader implements AppVersionReader {
  const _FixedVersionReader(this.version);
  final AppVersion version;

  @override
  Future<AppVersion> read() async => version;
}

UpdateCheckService _updateService({
  required AppVersion installed,
  required ReleaseAppKind app,
  Map<String, dynamic>? payload,
  http.Client? httpClient,
  AppReleasePlatform platform = AppReleasePlatform.android,
}) {
  return UpdateCheckService(
    versionReader: _FixedVersionReader(installed),
    client: ReleaseManifestClient(
      httpClient: httpClient ??
          MockClient(
            (_) async => http.Response(
              jsonEncode(payload ?? _dualAppPayload()),
              200,
            ),
          ),
    ),
    cache: _MemoryCache(),
    platform: platform,
    releaseApp: app,
    manifestUrl: 'https://example.test/sello-release.json',
  );
}

Map<String, dynamic> _dualAppPayload({
  Map<String, dynamic>? salesRep,
  Map<String, dynamic>? ownerManager,
}) {
  return {
    'schema_version': 2,
    'app': 'sello',
    'apps': {
      'sales_rep': salesRep ??
          {
            'latest': {
              'version': '1.0.2',
              'build': 3,
              'released_at': '2026-08-18',
              'notes': 'Testing the update flow.',
            },
            'minimum': {
              'version': '1.0.0',
              'build': 1,
              'enforced': false,
            },
            'platforms': {
              'android': {
                'destination_kind': 'apk',
                'destination_url':
                    'https://cashro.pro/sello-updates/sales-rep/sello-sales-rep.apk',
              },
              'ios': {
                'destination_kind': 'testflight',
                'destination_url': '',
              },
              'web': {
                'destination_kind': 'web',
                'destination_url': '',
              },
            },
          },
      'owner_manager': ownerManager ??
          {
            'latest': {
              'version': '1.0.0',
              'build': 1,
              'released_at': '2026-08-18',
              'notes': '',
            },
            'minimum': {
              'version': '1.0.0',
              'build': 1,
              'enforced': false,
            },
            'platforms': {
              'android': {
                'destination_kind': 'apk',
                'destination_url':
                    'https://cashro.pro/sello-updates/owner-manager/sello-owner-manager.apk',
              },
              'ios': {
                'destination_kind': 'testflight',
                'destination_url': '',
              },
              'web': {
                'destination_kind': 'web',
                'destination_url': '',
              },
            },
          },
    },
  };
}

class _MemoryCache extends UpdateCheckCache {
  UpdateCheckSnapshot? stored;
  String? postponed;
  var fresh = false;

  @override
  Future<bool> isFresh() async => fresh;

  @override
  Future<UpdateCheckSnapshot?> load() async => stored;

  @override
  Future<void> save(UpdateCheckSnapshot snapshot) async {
    stored = snapshot;
  }

  @override
  Future<String?> postponedIdentity() async => postponed;

  @override
  Future<void> postpone(String identity) async {
    postponed = identity;
  }
}
