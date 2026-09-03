import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/hub/dashboard/application/hub_needs_attention_provider.dart';
import 'package:sello/features/hub/inventory/application/hub_inventory_provider.dart';
import 'package:sello/features/hub/orders/application/hub_orders_provider.dart';
import 'package:sello/services/dashboard/needs_attention.dart';
import 'package:sello/shared/models/stock_movement_type.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Compact Owner/Manager operational alerts — not an activity feed.
class HubNeedsAttentionCard extends ConsumerWidget {
  const HubNeedsAttentionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(hubNeedsAttentionProvider);

    return async.when(
      data: (counts) {
        final items = NeedsAttentionLogic.build(counts);
        if (items.isEmpty) {
          return SelloDashboardCard(
            title: 'Needs attention',
            countBadge: '0',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                "You're all caught up.",
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          );
        }

        return SelloDashboardCard(
          title: 'Needs attention',
          countBadge: '${items.length}',
          action: SelloViewAllLink(
            onTap: () => _openOrders(ref, context, OrderStatusFilter.openFulfillment),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++)
                _NeedsAttentionRow(
                  item: items[i],
                  showDivider: i < items.length - 1,
                  onTap: () => _openItem(ref, context, items[i]),
                ),
            ],
          ),
        );
      },
      loading: () => const SelloDashboardCard(
        title: 'Needs attention',
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ),
      error: (_, _) => SelloDashboardCard(
        title: 'Needs attention',
        action: SelloViewAllLink(
          onTap: () => ref.invalidate(hubNeedsAttentionProvider),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'Couldn\'t load these alerts right now.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openItem(
    WidgetRef ref,
    BuildContext context,
    NeedsAttentionItem item,
  ) async {
    switch (item.kind) {
      case NeedsAttentionKind.negativeStock:
        await ref
            .read(hubInventoryProvider.notifier)
            .setStatusFilter(StockStatusFilter.negativeStock);
        if (!context.mounted) return;
        context.go(RoutePaths.hubInventory);
      case NeedsAttentionKind.waitingForStock:
        await _openOrders(ref, context, OrderStatusFilter.openFulfillment);
      case NeedsAttentionKind.placedAwaitingFulfillment:
        await _openOrders(ref, context, OrderStatusFilter.placed);
      case NeedsAttentionKind.partiallyDelivered:
        await _openOrders(ref, context, OrderStatusFilter.partiallyDelivered);
    }
  }

  Future<void> _openOrders(
    WidgetRef ref,
    BuildContext context,
    OrderStatusFilter filter,
  ) async {
    await ref.read(hubOrdersProvider.notifier).setStatusFilter(filter);
    if (!context.mounted) return;
    context.go(RoutePaths.hubOrders);
  }
}

class _NeedsAttentionRow extends StatefulWidget {
  const _NeedsAttentionRow({
    required this.item,
    required this.onTap,
    required this.showDivider,
  });

  final NeedsAttentionItem item;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  State<_NeedsAttentionRow> createState() => _NeedsAttentionRowState();
}

class _NeedsAttentionRowState extends State<_NeedsAttentionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final high = widget.item.priority == NeedsAttentionPriority.high;
    final tone = high ? AppColors.attention : AppColors.warning;
    final soft = high ? AppColors.attentionSoft : AppColors.warningContainer;
    final icon = switch (widget.item.kind) {
      NeedsAttentionKind.negativeStock => Icons.error_outline_rounded,
      NeedsAttentionKind.waitingForStock => Icons.inventory_2_outlined,
      NeedsAttentionKind.placedAwaitingFulfillment =>
        Icons.local_shipping_outlined,
      NeedsAttentionKind.partiallyDelivered => Icons.timelapse_rounded,
    };

    return Column(
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Material(
            color: _hover ? soft.withValues(alpha: 0.55) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: soft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 15, color: tone),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.item.title,
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.outlinePanel.withValues(alpha: 0.7),
          ),
      ],
    );
  }
}
