import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/data/repositories/company_settings_repository.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/services/storage/media_storage_service.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/company.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/employee.dart';
import 'package:sello/shared/models/role.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('HubSettingsNotifier', () {
    test('waits for session during bootstrap instead of showing an error', () async {
      final repo = _FakeCompanySettingsRepository();
      final auth = _RecordingAuthSession();
      final container = ProviderContainer(
        overrides: [
          companySettingsRepositoryProvider.overrideWithValue(repo),
          authSessionProvider.overrideWith(() => auth),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(hubSettingsProvider);
      expect(state.isLoading, isTrue);
      expect(state.settings, isNull);
      expect(state.errorMessage, isNull);

      await pumpMicrotasks();
      expect(container.read(hubSettingsProvider).errorMessage, isNull);

      auth.authenticate(_session());
      await pumpMicrotasks();
      await pumpMicrotasks();

      final loaded = container.read(hubSettingsProvider);
      expect(loaded.settings, isNotNull);
      expect(loaded.errorMessage, isNull);
      expect(repo.fetchCount, greaterThanOrEqualTo(1));
    });
  });
}

class _FakeCompanySettingsRepository extends CompanySettingsRepository {
  _FakeCompanySettingsRepository()
      : super(
          client: _testClient,
          storage: MediaStorageService(client: _testClient),
        );

  int fetchCount = 0;

  @override
  Future<CompanySettings> fetchForCompany(
    String companyId, {
    String? employeeId,
  }) async {
    fetchCount++;
    return CompanySettings.defaults;
  }
}

class _RecordingAuthSession extends AuthSessionNotifier {
  @override
  AuthSessionState build() =>
      const AuthSessionState(status: AuthStatus.unknown, isLoading: true);

  void authenticate(AppSession session) {
    state = AuthSessionState(status: AuthStatus.authenticated, session: session);
  }
}

AppSession _session() {
  return AppSession(
    authUser: User(
      id: 'user-1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00.000Z',
    ),
    employee: Employee(
      id: 'emp-1',
      companyId: 'co-1',
      roleId: 'role-1',
      email: 'owner@example.com',
      fullName: 'Owner',
    ),
    company: const Company(
      id: 'co-1',
      name: 'Unitech',
      companyCode: 'UNI',
      slug: 'unitech',
    ),
    role: Role(id: 'role-1', code: 'owner', name: 'owner'),
    ownerSetupCompleted: true,
  );
}

Future<void> pumpMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final _testClient = SupabaseClient('https://example.supabase.co', 'anon');
