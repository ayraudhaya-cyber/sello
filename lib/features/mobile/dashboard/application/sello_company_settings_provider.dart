import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/utils/formatters.dart';

/// Sales-facing company preferences (no Hub draft state).
///
/// Falls back to [CompanySettings.defaults] while loading or on failure so
/// Home always has a full four-card grid.
final selloCompanySettingsProvider = FutureProvider<CompanySettings>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return CompanySettings.defaults;

  try {
    return await ref.read(companySettingsRepositoryProvider).fetchForCompany(
          session.company.id,
          employeeId: session.employee.id,
        );
  } catch (_) {
    return CompanySettings.defaults;
  }
});

/// Company currency display symbol for Sales money UI (e.g. LKR → `Rs `).
///
/// Watches [selloCompanySettingsProvider] so Hub currency changes apply on the
/// next Sales settings fetch / rebuild.
final selloCurrencySymbolProvider = Provider<String>((ref) {
  final currency =
      ref.watch(selloCompanySettingsProvider).valueOrNull?.currency;
  return SelloFormatters.currencySymbol(currency);
});
