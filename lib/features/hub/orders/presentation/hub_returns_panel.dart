import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/orders/application/hub_orders_provider.dart';
import 'package:sello/features/hub/orders/application/hub_returns_provider.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/shared/models/order_return.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

class HubReturnsPanel extends ConsumerStatefulWidget {
  const HubReturnsPanel({super.key, required this.currencySymbol});

  final String currencySymbol;

  @override
  ConsumerState<HubReturnsPanel> createState() => _HubReturnsPanelState();
}

class _HubReturnsPanelState extends ConsumerState<HubReturnsPanel> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final state = ref.read(hubReturnsProvider);
      if (!state.initialized) {
        ref.read(hubReturnsProvider.notifier).load();
      }
    });
  }

  Future<void> _cancel(OrderReturnSummary item) async {
    if (!item.canCancelToday) {
      await showSelloNotice(
        context: context,
        title: 'Return cannot be cancelled',
        message:
            'This return was recorded on an earlier day, so it cannot be cancelled. '
            'The goods, the balance, and the money stay as they are.',
      );
      return;
    }
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Cancel this return?',
      message:
          'Stock, what they owe, and any money given back or saved will be put back as they were. '
          '${item.returnNumber} stays in this list as Cancelled.',
      confirmLabel: 'Cancel return',
      cancelLabel: 'Keep it',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(orderReturnRepositoryProvider).cancel(item.id);
      if (!mounted) return;
      SelloSnackbars.success(context, '${item.returnNumber} cancelled.');
      await ref.read(hubReturnsProvider.notifier).load(showLoading: false);
      await ref.read(hubOrdersProvider.notifier).refreshAfterReturn();
    } on AppFailure catch (failure) {
      if (!mounted) return;
      await showSelloNotice(
        context: context,
        title: 'Return cannot be cancelled',
        message: failure.message,
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hubReturnsProvider);
    if (_searchController.text != state.search) {
      _searchController.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: context.isMobile ? double.infinity : 320,
              child: SelloSearchBar(
                controller: _searchController,
                hint: 'Return, order, or customer',
                onChanged: (value) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () => ref.read(hubReturnsProvider.notifier).setSearch(value),
                  );
                },
              ),
            ),
            SelloButton(
              label: 'Refresh',
              icon: Icons.refresh_rounded,
              variant: SelloButtonVariant.outline,
              loading: state.isLoading,
              onPressed: state.isLoading
                  ? null
                  : () => ref.read(hubReturnsProvider.notifier).load(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.mdPlus),
        SelloInlineRefreshBar(active: state.isLoading && state.items.isNotEmpty),
        if (state.errorMessage != null && state.items.isEmpty)
          SelloEmptyState(
            title: 'Unable to load returns',
            message: state.errorMessage,
            icon: Icons.error_outline_rounded,
            tone: EmptyStateTone.warning,
            actionLabel: 'Try again',
            onAction: () => ref.read(hubReturnsProvider.notifier).load(),
          )
        else if (state.isLoading && state.items.isEmpty)
          context.isMobile
              ? const SelloListSkeleton()
              : const SelloTableSkeleton(columns: 9, showMetrics: false)
        else if (state.isEmpty)
          SelloEmptyState(
            title: state.search.trim().isEmpty
                ? 'No returns yet'
                : 'No matching returns',
            message: state.search.trim().isEmpty
                ? 'When delivered items come back, they are listed here.'
                : 'Try another return number, order, or customer.',
            icon: Icons.assignment_return_outlined,
          )
        else
          SelloDataTable(
            minWidth: 980,
            flexColumnIndex: null,
            dataRowMaxHeight: _returnsRowHeight(state.items),
            columns: const [
              DataColumn(label: Text('Return')),
              DataColumn(label: Text('Customer')),
              DataColumn(label: Text('Order')),
              DataColumn(label: Text('Items')),
              DataColumn(label: Text('Value'), numeric: true),
              DataColumn(label: Text('Money')),
              DataColumn(label: Text('Stock')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final item in state.items)
                DataRow(
                  cells: [
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: SelloTableText(
                              item.returnNumber,
                              tone: SelloTableTone.strong,
                            ),
                          ),
                          if (item.isCancelled) ...[
                            const SizedBox(width: 6),
                            const SelloStatusBadge(
                              label: 'Cancelled',
                              tone: SelloStatusTone.neutral,
                              showDot: false,
                              compact: true,
                            ),
                          ],
                        ],
                      ),
                    ),
                    DataCell(SelloTableText(item.customerName)),
                    DataCell(SelloTableText(item.orderNumber)),
                    DataCell(_ItemsCell(lines: item.lines)),
                    DataCell(
                      SelloTableText(
                        SelloFormatters.currency(
                          item.returnValue,
                          symbol: widget.currencySymbol,
                        ),
                        tone: SelloTableTone.strong,
                        numeric: true,
                      ),
                    ),
                    DataCell(SelloTableText(item.moneyLabel)),
                    DataCell(SelloTableText(item.stockLabel)),
                    DataCell(
                      SelloTableText(
                        SelloFormatters.date(item.returnedAt),
                        tone: SelloTableTone.muted,
                      ),
                    ),
                    DataCell(
                      item.isCancelled
                          ? const SizedBox.shrink()
                          : SelloRowIconButton(
                              tooltip: 'Cancel return',
                              icon: Icons.undo_rounded,
                              onPressed: () => _cancel(item),
                            ),
                    ),
                  ],
                ),
            ],
            footer: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SelloButton(
                    label: 'Previous',
                    size: SelloButtonSize.small,
                    variant: SelloButtonVariant.outline,
                    onPressed: state.page <= 0
                        ? null
                        : () => ref
                              .read(hubReturnsProvider.notifier)
                              .goToPage(state.page - 1),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Page ${state.page + 1}',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  SelloButton(
                    label: 'Next',
                    size: SelloButtonSize.small,
                    variant: SelloButtonVariant.outline,
                    onPressed: state.hasMore
                        ? () => ref
                              .read(hubReturnsProvider.notifier)
                              .goToPage(state.page + 1)
                        : null,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

double _returnsRowHeight(List<OrderReturnSummary> items) {
  var lines = 1;
  for (final item in items) {
    if (item.lines.length > lines) lines = item.lines.length;
  }
  return math.max(88, 20 + lines * 24);
}

class _ItemsCell extends StatelessWidget {
  const _ItemsCell({required this.lines});

  final List<OrderReturnLineLabel> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SelloTableText('—');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: SelloTableText(lines[i].title)),
              const SizedBox(width: 12),
              SelloTableText(
                SelloFormatters.quantity(lines[i].quantity),
                tone: SelloTableTone.strong,
                numeric: true,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
