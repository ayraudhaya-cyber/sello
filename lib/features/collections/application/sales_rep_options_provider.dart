import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/employee_summary.dart';

/// Sales representatives for filters (Owner / Manager only).
final salesRepOptionsProvider =
    FutureProvider.autoDispose<List<EmployeeSummary>>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return const [];
  final page = await ref.read(employeeRepositoryProvider).fetchEmployees(
        companyId: session.company.id,
        roleCode: 'sales_representative',
        pageSize: 200,
      );
  return page.items;
});
