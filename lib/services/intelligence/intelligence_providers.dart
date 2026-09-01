import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/intelligence/intelligence_service.dart';

/// Shared Intelligence engine — Hub and Sales both consume this.
final intelligenceServiceProvider = Provider<IntelligenceService>(
  (ref) => IntelligenceService(
    inventory: ref.watch(inventoryRepositoryProvider),
    payments: ref.watch(paymentRepositoryProvider),
    orders: ref.watch(orderRepositoryProvider),
    visits: ref.watch(visitRepositoryProvider),
    employees: ref.watch(employeeRepositoryProvider),
    reports: ref.watch(reportRepositoryProvider),
  ),
);
