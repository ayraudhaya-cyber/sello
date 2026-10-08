import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/payments/application/pending_collections_count_provider.dart';
import 'package:sello/services/dashboard/needs_attention.dart';
import 'package:sello/services/session/session_provider.dart';

/// Live Hub Needs Attention snapshot (company orders + session-branch inventory).
final hubNeedsAttentionProvider =
    FutureProvider.autoDispose<NeedsAttentionCounts>((ref) async {
      final session = ref.watch(currentSessionProvider);
      final branchId = session?.branch?.id;

      final orderRepo = ref.read(orderRepositoryProvider);
      final inventoryRepo = ref.read(inventoryRepositoryProvider);

      final fulfillmentFuture = orderRepo.fetchFulfillmentAttention();
      final inventoryFuture = inventoryRepo.fetchDashboardStats(
        branchId: branchId,
      );
      final pending = ref.watch(pendingCollectionsCountProvider);
      final fulfillment = await fulfillmentFuture;
      final inventoryStats = await inventoryFuture;

      return NeedsAttentionCounts(
        placed: fulfillment.placed,
        partiallyDelivered: fulfillment.partiallyDelivered,
        waitingPlaced: fulfillment.waitingPlaced,
        waitingPartial: fulfillment.waitingPartial,
        negativeStock: inventoryStats.negativeStock,
        pendingCollections: pending,
      );
    });
