import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/mobile/dashboard/application/sello_home_provider.dart';
import 'package:sello/shared/models/customer_summary.dart';

/// Area used for Home discovery. Defaults to today's assigned territory.
final selloHomeNearAreaProvider =
    NotifierProvider<SelloHomeNearAreaNotifier, String?>(
  SelloHomeNearAreaNotifier.new,
);

class SelloHomeNearAreaNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.listen(selloHomeDayProvider, (previous, next) {
      final nextArea = next.primaryArea;
      if (state == null && nextArea != null && nextArea.trim().isNotEmpty) {
        state = nextArea.trim();
      }
    });
    return ref.read(selloHomeDayProvider).primaryArea;
  }

  void setArea(String? area) {
    final trimmed = area?.trim();
    state = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

/// Customers worth a look right now — not a revenue ranking.
final selloConsiderCustomersProvider = FutureProvider<List<CustomerSummary>>((
  ref,
) async {
  final area = ref.watch(selloHomeNearAreaProvider);
  final day = ref.watch(selloHomeDayProvider);
  final result = await ref.read(customerRepositoryProvider).fetchCustomers(
        isActive: true,
        pageSize: 80,
      );

  final plannedIds = {
    for (final stop in day.plannedVisits)
      if (stop.customerId != null) stop.customerId!,
  };
  final inProgressId = day.visits
      .where((v) => v.isInProgress)
      .map((v) => v.customerId)
      .whereType<String>()
      .firstOrNull;

  final ranked = result.items
      .where(
        (customer) =>
            customer.id != inProgressId && !plannedIds.contains(customer.id),
      )
      .toList()
    ..sort((a, b) => _considerScore(
          b,
          area: area,
        ).compareTo(_considerScore(
          a,
          area: area,
        )));

  return ranked.take(5).toList(growable: false);
});

final selloHomeCustomerSearchProvider =
    FutureProvider.autoDispose.family<List<CustomerSummary>, String>((
  ref,
  query,
) async {
  final needle = query.trim();
  if (needle.length < 2) return const [];
  final area = ref.watch(selloHomeNearAreaProvider);
  final result = await ref.read(customerRepositoryProvider).fetchCustomers(
        search: needle,
        isActive: true,
        pageSize: 8,
      );
  if (area == null || area.isEmpty) return result.items;
  final inArea = result.items.where((c) => _matchesArea(c, area)).toList();
  if (inArea.isNotEmpty) return inArea;
  return result.items;
});

int _considerScore(
  CustomerSummary customer, {
  required String? area,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var score = 0;

  if (area != null && area.isNotEmpty && _matchesArea(customer, area)) {
    score += 40;
  }

  final next = customer.nextVisitAt;
  if (next != null) {
    final nextDay = DateTime(next.year, next.month, next.day);
    if (!nextDay.isAfter(today)) score += 50;
  }

  final lastVisit = customer.lastVisitAt;
  if (lastVisit == null) {
    score += 18;
  } else {
    final days = today.difference(DateTime(
      lastVisit.year,
      lastVisit.month,
      lastVisit.day,
    )).inDays;
    if (days >= 14) {
      score += 22;
    } else if (days >= 7) {
      score += 14;
    } else {
      score += 8;
    }
  }

  final lastOrder = customer.lastPurchaseAt;
  if (lastOrder != null) {
    final days = today.difference(DateTime(
      lastOrder.year,
      lastOrder.month,
      lastOrder.day,
    )).inDays;
    if (days >= 7 && days < 45) score += 12;
    if (days < 7) score += 6;
  }

  return score;
}

bool _matchesArea(CustomerSummary customer, String area) {
  final city = (customer.city ?? '').toLowerCase().trim();
  if (city.isEmpty) return false;
  final a = area.toLowerCase().trim();
  if (a.isEmpty) return false;
  if (city.contains(a) || a.contains(city)) return true;
  for (final part in a.split(RegExp(r'[–\-]'))) {
    final p = part.trim();
    if (p.isEmpty) continue;
    final suburb = p.replaceFirst(RegExp(r'^colombo\s*\d*\s*'), '').trim();
    if (suburb.isNotEmpty && (city.contains(suburb) || suburb.contains(city))) {
      return true;
    }
    if (city.contains(p) || p.contains(city)) return true;
  }
  return false;
}
