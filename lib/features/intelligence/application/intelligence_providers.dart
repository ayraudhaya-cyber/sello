import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/features/mobile/dashboard/application/sello_company_settings_provider.dart';
import 'package:sello/features/mobile/dashboard/application/sello_home_provider.dart';
import 'package:sello/services/intelligence/intelligence_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/intelligence_insight.dart';
import 'package:sello/shared/models/user_role.dart';

export 'package:sello/services/intelligence/intelligence_providers.dart';

/// Hub (Owner / Manager) proactive insights for Action Center + Reports.
final hubIntelligenceProvider =
    FutureProvider.autoDispose<IntelligenceSnapshot>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null || !session.appRole.usesHub) {
    return IntelligenceSnapshot.empty(role: session?.appRole);
  }

  final settings = await ref.watch(selloCompanySettingsProvider.future);
  return ref.read(intelligenceServiceProvider).generate(
        session: session,
        settings: settings,
      );
});

/// Sales Home insights — mirrors [SalesDaySnapshot.intelligenceHints].
final selloIntelligenceProvider = Provider<IntelligenceSnapshot>((ref) {
  final session = ref.watch(currentSessionProvider);
  final day = ref.watch(selloHomeDayProvider);
  if (session == null || session.appRole != UserRole.salesRepresentative) {
    return IntelligenceSnapshot.empty(role: session?.appRole);
  }
  return IntelligenceSnapshot(
    insights: day.intelligenceHints,
    generatedAt: DateTime.now(),
    role: session.appRole,
  );
});
