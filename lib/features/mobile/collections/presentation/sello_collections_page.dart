import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/collections/application/collections_summary.dart';
import 'package:sello/features/mobile/collections/application/sello_collections_provider.dart';
import 'package:sello/features/mobile/dashboard/application/sello_company_settings_provider.dart';
import 'package:sello/shared/models/payment_record_status.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// "My collections" — everything the signed-in Sales Rep collected, so they
/// can see what counts toward their bonus. Collected = approved/completed;
/// awaiting-approval rows are shown but kept out of the collected total.
class SelloCollectionsPage extends ConsumerWidget {
  const SelloCollectionsPage({super.key});

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.selloOrders);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(selloCollectionsProvider);
    final symbol = ref.watch(selloCurrencySymbolProvider);
    final summary = state.summary;
    String money(num value) => SelloFormatters.currency(value, symbol: symbol);

    final notifier = ref.read(selloCollectionsProvider.notifier);

    return AppPageScaffold(
      title: 'My collections',
      showBreadcrumbs: false,
      inlineActions: true,
      maxWidth: 720,
      headerSpacing: AppSpacing.md,
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => _back(context),
      ),
      actions: [
        SelloHeaderAction(
          icon: Icons.refresh_rounded,
          label: 'Refresh',
          onPressed: state.isLoading ? null : notifier.refresh,
        ),
      ],
      onRefresh: notifier.refresh,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final period in CollectionsPeriod.values) ...[
                  _PeriodChip(
                    label: period.label,
                    selected: state.period == period,
                    onTap: () => notifier.setPeriod(period),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _TotalsCard(summary: summary, money: money),
          const SizedBox(height: AppSpacing.md),
          SelloInlineRefreshBar(
            active: state.isLoading && state.items.isNotEmpty,
          ),
          if (state.errorMessage != null && state.items.isNotEmpty)
            SelloInlineErrorBar(
              message: state.errorMessage,
              onRetry: notifier.refresh,
            ),
          if (state.isLoading && state.items.isEmpty)
            const SelloListSkeleton(cards: 4)
          else if (state.errorMessage != null && state.items.isEmpty)
            SelloStateView.error(
              title: 'Unable to load collections',
              message: state.errorMessage,
              actionLabel: 'Try again',
              onAction: notifier.refresh,
            )
          else if (state.items.isEmpty)
            const SelloEmptyState(
              icon: Icons.payments_outlined,
              title: 'No collections in this period',
              message: 'Payments you record from customers will appear here.',
            )
          else
            for (final payment in state.items) ...[
              _CollectionCard(payment: payment, money: money),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: context.brandAccentContainer,
      labelStyle: TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontWeight: FontWeight.w600,
        color: selected ? context.brandAccent : AppColors.textSecondary,
      ),
      side: BorderSide(
        color: selected
            ? context.brandAccent.withValues(alpha: 0.35)
            : AppColors.outlinePanel,
      ),
      backgroundColor: AppColors.surface,
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.summary, required this.money});

  final CollectionsSummary summary;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.outlinePanel),
        boxShadow: AppShadows.panel,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Collected',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            money(summary.collected),
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: context.brandAccent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${summary.collectedCount} '
            '${summary.collectedCount == 1 ? 'collection' : 'collections'}',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'For orders',
                  value: money(summary.orderCollected),
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'For opening balances',
                  value: money(summary.openingCollected),
                ),
              ),
            ],
          ),
          if (summary.pendingCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            _MiniStat(
              label: 'Awaiting approval (not counted yet)',
              value:
                  '${money(summary.pending)} · ${summary.pendingCount} '
                  '${summary.pendingCount == 1 ? 'payment' : 'payments'}',
              valueColor: AppColors.warning,
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.payment, required this.money});

  final PaymentSummary payment;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    final status = payment.status;
    final showStatus = status != PaymentRecordStatus.completed;
    final statusColor = switch (status) {
      PaymentRecordStatus.pending => AppColors.warning,
      PaymentRecordStatus.rejected => AppColors.error,
      _ => AppColors.textSecondary,
    };
    final statusText = status == PaymentRecordStatus.pending
        ? 'Awaiting approval'
        : payment.displayStatusLabel;
    final paidFor = payment.allocationSummary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  payment.customerName ?? 'Customer',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                money(payment.amount),
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: status == PaymentRecordStatus.rejected
                      ? AppColors.textFaint
                      : AppColors.textPrimary,
                  decoration: status == PaymentRecordStatus.rejected
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Tag(text: payment.collectionTypeLabel),
              _Tag(text: payment.method.label),
              if (showStatus)
                _Tag(text: statusText, color: statusColor, strong: true),
            ],
          ),
          const SizedBox(height: 8),
          if (paidFor.isNotEmpty)
            Text(
              paidFor,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${SelloFormatters.dateTime(payment.receivedAt.toLocal())} · '
              '${payment.paymentNumber}',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          if (status == PaymentRecordStatus.rejected &&
              (payment.rejectionReason ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Reason: ${payment.rejectionReason}',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12.5,
                  color: AppColors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.color, this.strong = false});

  final String text;
  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (color ?? AppColors.textSecondary).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 11.5,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          color: tone,
        ),
      ),
    );
  }
}
