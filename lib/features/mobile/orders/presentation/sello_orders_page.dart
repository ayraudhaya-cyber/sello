import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/documents/presentation/order_document_print.dart';
import 'package:sello/features/mobile/dashboard/application/sello_company_settings_provider.dart';
import 'package:sello/features/mobile/orders/application/sello_orders_provider.dart';
import 'package:sello/features/orders/presentation/order_confirmation_share_sheet.dart';
import 'package:sello/features/orders/presentation/order_details_dialog.dart';
import 'package:sello/features/orders/presentation/order_editor_dialog.dart';
import 'package:sello/features/orders/presentation/order_fulfillment_dialog.dart';
import 'package:sello/services/notifications/order_confirmation_dispatcher.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';
import 'package:sello/services/notifications/outbound/outbound_sms.dart';
import 'package:sello/shared/models/order_confirmation.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/payment_status.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sales Rep orders — create and complete sales with shared domain logic.
class SelloOrdersPage extends ConsumerStatefulWidget {
  const SelloOrdersPage({super.key});

  @override
  ConsumerState<SelloOrdersPage> createState() => _SelloOrdersPageState();
}

class _SelloOrdersPageState extends ConsumerState<SelloOrdersPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _openedFromQuery = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_openedFromQuery) return;
    final newOrder = GoRouterState.of(context).uri.queryParameters['new'];
    if (newOrder == '1' || newOrder == 'true') {
      _openedFromQuery = true;
      final visitId = GoRouterState.of(context).uri.queryParameters['visit'];
      final customerId = GoRouterState.of(
        context,
      ).uri.queryParameters['customer'];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openEditor(
          visitId: (visitId != null && visitId.isNotEmpty) ? visitId : null,
          initialCustomerId: (customerId != null && customerId.isNotEmpty)
              ? customerId
              : null,
        );
        context.go(RoutePaths.selloOrders);
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _currencySymbol => ref.watch(selloCurrencySymbolProvider);

  bool get _salesCanRecordDelivery =>
      ref
          .watch(selloCompanySettingsProvider)
          .valueOrNull
          ?.salesRepsCanRecordDelivery ??
      true;

  Future<void> _openEditor({
    OrderDetail? existing,
    String? visitId,
    String? initialCustomerId,
  }) async {
    final result = await showDialog<OrderEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => OrderEditorDialog(
        existing: existing,
        currencySymbol: _currencySymbol,
        visitId: visitId,
        initialCustomerId: initialCustomerId,
      ),
    );
    if (result == null) return;

    final saved = await ref
        .read(selloOrdersProvider.notifier)
        .saveOrder(
          result.input,
          complete: result.complete,
          place: result.place,
        );
    if (!mounted) return;
    if (!saved.isOk) {
      SelloSnackbars.error(context, saved.error!);
    } else if (result.place) {
      SelloSnackbars.success(context, 'Order submitted.');
    } else if (result.complete) {
      await presentOrderConfirmation(
        context,
        saved.confirmation,
        completed: true,
      );
    } else {
      SelloSnackbars.success(context, 'Saved for later.');
    }
  }

  String? _openingOrderId;

  Future<void> _openDetails(OrderSummary order) async {
    if (_openingOrderId != null) return;
    setState(() => _openingOrderId = order.id);
    final OrderDetail? fetched;
    try {
      fetched = await ref.read(orderRepositoryProvider).fetchById(order.id);
    } catch (_) {
      if (mounted) {
        setState(() => _openingOrderId = null);
        SelloSnackbars.error(context, 'Unable to open this order.');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _openingOrderId = null);
    if (fetched == null) return;
    final detail = fetched;

    await showDialog<void>(
      context: context,
      builder: (context) => OrderDetailsDialog(
        detail: detail,
        currencySymbol: _currencySymbol,
        onEdit: detail.summary.isEditable
            ? () {
                Navigator.of(context).pop();
                _openEditor(existing: detail);
              }
            : null,
        onComplete: detail.summary.isEditable
            ? () async {
                final nav = Navigator.of(context);
                nav.pop();
                await _submitDraft(detail.summary);
              }
            : null,
        completeLabel: 'Submit order',
        onCancelOrder: detail.summary.isEditable
            ? () async {
                final nav = Navigator.of(context);
                nav.pop();
                await _cancel(detail.summary);
              }
            : null,
        onViewInvoice: detail.summary.status.canShareInvoice
            ? () => _viewInvoice(detail.summary)
            : null,
        onPrintInvoice: detail.summary.status.canShareInvoice
            ? () => _printInvoice(detail.summary)
            : null,
        onWhatsAppInvoice: detail.summary.status.canShareInvoice
            ? () => _whatsAppInvoice(detail.summary)
            : null,
        onSmsInvoice: detail.summary.status.canShareInvoice
            ? () => _smsInvoice(detail.summary)
            : null,
        onFulfill: _salesCanRecordDelivery && detail.summary.status.canFulfill
            ? () async {
                final nav = Navigator.of(context);
                nav.pop();
                await _recordDelivery(detail);
              }
            : null,
        onFulfillAll:
            _salesCanRecordDelivery && detail.summary.status.canFulfill
            ? () async {
                final nav = Navigator.of(context);
                nav.pop();
                await _fulfillAll(detail.summary);
              }
            : null,
        onCollectionSaved: () {
          ref.read(selloOrdersProvider.notifier).refresh();
        },
      ),
    );
  }

  Future<OrderConfirmationOutcome?> _prepareInvoiceShare(String orderId) {
    return ref
        .read(orderConfirmationDispatcherProvider)
        .dispatch(orderId, smsMode: OrderConfirmationSmsMode.shareActions);
  }

  Future<String> _messagingUnavailableMessage() async {
    final policies = await ref
        .read(orderDocumentRepositoryProvider)
        .fetchOutboundPolicies();
    return policies.inactiveOrderMessagingReason() ??
        'Unable to prepare the confirmation for this order.';
  }

  Future<void> _viewInvoice(OrderSummary order) async {
    try {
      final url = await ref
          .read(orderDocumentRepositoryProvider)
          .invoiceUrlForOrder(order.id);
      if (!mounted) return;
      final parsed = Uri.tryParse(url);
      if (parsed == null) {
        SelloSnackbars.error(context, 'Unable to open the invoice.');
        return;
      }
      final ok = await launchUrl(parsed, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        SelloSnackbars.error(context, 'Unable to open the invoice.');
      }
    } on AppFailure catch (failure) {
      if (!mounted) return;
      SelloSnackbars.warning(context, failure.message);
    } catch (_) {
      if (!mounted) return;
      SelloSnackbars.error(context, 'Unable to open the invoice.');
    }
  }

  Future<void> _printInvoice(OrderSummary order) async {
    try {
      final doc = await ref
          .read(orderDocumentRepositoryProvider)
          .documentForOrder(order.id);
      if (!mounted) return;
      printOrderDocument(doc);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      SelloSnackbars.warning(context, failure.message);
    } catch (_) {
      if (!mounted) return;
      SelloSnackbars.error(context, 'Unable to print the invoice.');
    }
  }

  Future<void> _whatsAppInvoice(OrderSummary order) async {
    try {
      final outcome = await _prepareInvoiceShare(order.id);
      if (!mounted) return;
      if (outcome == null) {
        final message = await _messagingUnavailableMessage();
        if (!mounted) return;
        SelloSnackbars.warning(context, message);
        return;
      }
      final customerWa = outcome.customerActions
          .where((a) => a.channel == OutboundChannel.whatsapp)
          .toList();
      if (customerWa.isEmpty) {
        SelloSnackbars.warning(
          context,
          outcome.customerSkippedReason ??
              'No WhatsApp number on this customer, or WhatsApp is disabled '
                  'for Order confirmation.',
        );
        return;
      }
      final uri = Uri.tryParse(customerWa.first.launchUri);
      if (uri == null) {
        SelloSnackbars.error(context, 'Unable to open WhatsApp.');
        return;
      }
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        SelloSnackbars.error(context, 'Unable to open WhatsApp.');
      }
    } on AppFailure catch (failure) {
      if (!mounted) return;
      SelloSnackbars.warning(context, failure.message);
    } catch (_) {
      if (!mounted) return;
      SelloSnackbars.error(
        context,
        'Unable to prepare WhatsApp for this order.',
      );
    }
  }

  Future<void> _smsInvoice(OrderSummary order) async {
    try {
      final outcome = await _prepareInvoiceShare(order.id);
      if (!mounted) return;
      if (outcome == null) {
        final message = await _messagingUnavailableMessage();
        if (!mounted) return;
        SelloSnackbars.warning(context, message);
        return;
      }
      final customerSms = outcome.customerActions
          .where((a) => a.channel == OutboundChannel.sms)
          .toList();
      if (customerSms.isEmpty) {
        SelloSnackbars.warning(
          context,
          outcome.customerSkippedReason ??
              'No phone number on this customer, or SMS is disabled '
                  'for Order confirmation.',
        );
        return;
      }
      await _sendInvoiceSms(outcome, customerSms.first);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      SelloSnackbars.warning(context, failure.message);
    } catch (_) {
      if (!mounted) return;
      SelloSnackbars.error(context, 'Unable to prepare SMS for this order.');
    }
  }

  Future<void> _sendInvoiceSms(
    OrderConfirmationOutcome outcome,
    OrderConfirmationAction action,
  ) async {
    final result = await ref
        .read(orderConfirmationDispatcherProvider)
        .sendSmsAction(outcome: outcome, action: action);
    if (!mounted) return;
    switch (result.status) {
      case OutboundSmsStatus.sent:
        SelloSnackbars.success(context, 'SMS sent to the customer.');
      case OutboundSmsStatus.alreadySent:
        SelloSnackbars.success(context, 'SMS was already sent for this order.');
      case OutboundSmsStatus.skippedMissingSender:
        SelloSnackbars.warning(
          context,
          'SMS Sender ID is not configured for this company.',
        );
      case OutboundSmsStatus.skipped:
        SelloSnackbars.warning(
          context,
          'SMS was skipped. Check Notifications and the customer phone.',
        );
      case OutboundSmsStatus.failed:
        SelloSnackbars.error(
          context,
          'Unable to send SMS. Try again in a moment.',
        );
    }
  }

  Future<void> _submitDraft(OrderSummary order) async {
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Submit order?',
      message:
          '${order.orderNumber} will be submitted. Stock will not be reduced yet.',
      confirmLabel: 'Submit order',
      cancelLabel: 'Keep draft',
    );
    if (confirmed != true || !mounted) return;

    final saved = await ref
        .read(selloOrdersProvider.notifier)
        .placeExisting(order);
    if (!mounted) return;
    if (!saved.isOk) {
      SelloSnackbars.error(context, saved.error!);
    } else {
      SelloSnackbars.success(context, 'Order submitted.');
    }
  }

  Future<void> _recordDelivery(OrderDetail detail) async {
    final result = await OrderFulfillmentDialog.show(
      context: context,
      detail: detail,
      currencySymbol: _currencySymbol,
    );
    if (result == null || !mounted) return;

    final error = await ref
        .read(selloOrdersProvider.notifier)
        .fulfillOrderItems(orderId: detail.summary.id, lines: result.lines);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
      await _openDetails(detail.summary);
    } else {
      SelloSnackbars.success(context, 'Delivery recorded.');
      await _openDetails(detail.summary);
    }
  }

  Future<void> _fulfillAll(OrderSummary order) async {
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Deliver remaining?',
      message:
          '${order.orderNumber}: deliver every remaining unit now. '
          'Stock will be reduced only for remaining quantities. Payment is not settled automatically.',
      confirmLabel: 'Deliver remaining',
      cancelLabel: 'Back',
    );
    if (confirmed != true || !mounted) return;

    final saved = await ref
        .read(selloOrdersProvider.notifier)
        .completeExisting(order);
    if (!mounted) return;
    if (!saved.isOk) {
      SelloSnackbars.error(
        context,
        saved.error ?? 'Unable to record this delivery.',
      );
      return;
    }
    SelloSnackbars.success(context, 'Delivery recorded.');
    await _openDetails(order);
  }

  Future<void> _cancel(OrderSummary order) async {
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Cancel order?',
      message: '${order.orderNumber} will be cancelled. Stock is not affected.',
      confirmLabel: 'Cancel order',
      cancelLabel: 'Keep draft',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final error = await ref
        .read(selloOrdersProvider.notifier)
        .cancelOrder(order);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(context, 'Order cancelled.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(selloOrdersProvider);
    ref.watch(selloCompanySettingsProvider);
    final currencySymbol = _currencySymbol;

    if (_searchController.text != state.search) {
      _searchController.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }

    return AppPageScaffold(
      title: 'Orders',
      showBreadcrumbs: false,
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.sm,
      inlineActions: true,
      onRefresh: () => ref.read(selloOrdersProvider.notifier).refresh(),
      onNearEnd: () => ref.read(selloOrdersProvider.notifier).loadMore(),
      actions: [
        SelloHeaderAction(
          icon: Icons.refresh_rounded,
          label: 'Refresh',
          onPressed: state.isLoading
              ? null
              : () => ref.read(selloOrdersProvider.notifier).refresh(),
        ),
        SelloHeaderAction(
          icon: Icons.payments_outlined,
          label: 'My collections',
          onPressed: () => context.push(RoutePaths.selloCollections),
        ),
        SelloButton(
          label: 'New order',
          icon: Icons.add_rounded,
          size: SelloButtonSize.small,
          onPressed: state.isSaving ? null : () => _openEditor(),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelloTextField(
            controller: _searchController,
            hint: 'Search orders or customers',
            prefixIcon: Icons.search_rounded,
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(
                const Duration(milliseconds: 300),
                () => ref.read(selloOrdersProvider.notifier).setSearch(value),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'In progress',
                  selected:
                      !state.showAllStatuses &&
                      state.statusFilter == OrderStatus.draft,
                  onTap: () => ref
                      .read(selloOrdersProvider.notifier)
                      .setStatusFilter(OrderStatus.draft),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Completed',
                  selected:
                      !state.showAllStatuses &&
                      state.statusFilter == OrderStatus.completed,
                  onTap: () => ref
                      .read(selloOrdersProvider.notifier)
                      .setStatusFilter(OrderStatus.completed),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'All',
                  selected: state.showAllStatuses,
                  onTap: () => ref
                      .read(selloOrdersProvider.notifier)
                      .setStatusFilter(null, all: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SelloInlineRefreshBar(
            active: state.isLoading && state.items.isNotEmpty,
          ),
          if (state.errorMessage != null && state.items.isNotEmpty)
            SelloInlineErrorBar(
              message: state.errorMessage,
              onRetry: () => ref.read(selloOrdersProvider.notifier).refresh(),
            ),
          if (state.isLoading && state.items.isEmpty)
            const SelloListSkeleton()
          else if (state.errorMessage != null && state.items.isEmpty)
            SelloStateView.error(
              title: 'Unable to load orders',
              message: state.errorMessage,
              actionLabel: 'Try again',
              onAction: () => ref.read(selloOrdersProvider.notifier).refresh(),
            )
          else if (state.isEmpty)
            SelloEmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'No orders yet',
              message:
                  'Start with a customer, add products, and submit the sale.',
              actionLabel: 'New order',
              onAction: () => _openEditor(),
            )
          else ...[
            for (final order in state.items) ...[
              _OrderCard(
                order: order,
                currencySymbol: currencySymbol,
                opening: _openingOrderId == order.id,
                onTap: () => _openDetails(order),
              ),
              const SizedBox(height: 10),
            ],
            SelloLoadMoreFooter(active: state.isLoadingMore),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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

Color _orderStatusColor(OrderStatus status) {
  return switch (status) {
    OrderStatus.cancelled => AppColors.error,
    OrderStatus.completed => AppColors.success,
    _ => AppColors.textSecondary,
  };
}

Color _paymentStatusColor(PaymentStatus status) {
  return switch (status) {
    PaymentStatus.paid => AppColors.success,
    PaymentStatus.unpaid => AppColors.warning,
    PaymentStatus.partial => AppColors.info,
    PaymentStatus.refunded => AppColors.error,
  };
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.currencySymbol,
    required this.onTap,
    this.opening = false,
  });

  final OrderSummary order;
  final String currencySymbol;
  final VoidCallback onTap;
  final bool opening;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.outlinePanel),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.orderNumber,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    SelloFormatters.currency(
                      order.total,
                      symbol: currencySymbol,
                    ),
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontWeight: FontWeight.w700,
                      color: context.brandAccent,
                    ),
                  ),
                  if (opening) ...[
                    const SizedBox(width: 10),
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.brandAccent,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                  children: [
                    TextSpan(text: order.customerName ?? 'Customer'),
                    const TextSpan(text: ' · '),
                    TextSpan(
                      text: order.status.label,
                      style: TextStyle(
                        color: _orderStatusColor(order.status),
                        fontWeight: order.status == OrderStatus.cancelled
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    const TextSpan(text: ' · '),
                    TextSpan(
                      text: order.paymentStatus.label,
                      style: TextStyle(
                        color: _paymentStatusColor(order.paymentStatus),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
