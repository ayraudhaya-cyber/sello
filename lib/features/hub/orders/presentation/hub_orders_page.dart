import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/orders/application/hub_orders_provider.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/orders/presentation/order_confirmation_share_sheet.dart';
import 'package:sello/features/orders/presentation/order_details_dialog.dart';
import 'package:sello/features/orders/presentation/order_editor_dialog.dart';
import 'package:sello/features/orders/presentation/order_fulfillment_dialog.dart';
import 'package:sello/services/notifications/order_confirmation_dispatcher.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';
import 'package:sello/services/notifications/outbound/outbound_sms.dart';
import 'package:sello/shared/models/order_confirmation.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/payment_status.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/quick_new_query.dart';
import 'package:sello/shared/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

class HubOrdersPage extends ConsumerStatefulWidget {
  const HubOrdersPage({super.key});

  @override
  ConsumerState<HubOrdersPage> createState() => _HubOrdersPageState();
}

class _HubOrdersPageState extends ConsumerState<HubOrdersPage>
    with QuickNewQueryMixin {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    consumeQuickNewQuery(
      cleanPath: RoutePaths.hubOrders,
      open: () => _openEditor(),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _currencySymbol() {
    final currency = ref.read(companySettingsProvider).currency;
    return SelloFormatters.currencySymbol(currency);
  }

  Future<void> _openEditor({OrderDetail? existing}) async {
    final result = await showDialog<OrderEditorResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => OrderEditorDialog(
        existing: existing,
        currencySymbol: _currencySymbol(),
      ),
    );
    if (result == null) return;

    final saved = await ref.read(hubOrdersProvider.notifier).saveOrder(
          result.input,
          complete: result.complete,
          place: result.place,
        );
    if (!mounted) return;
    if (!saved.isOk) {
      SelloSnackbars.error(context, saved.error!);
    } else if (result.complete) {
      if (saved.confirmation != null) {
        await presentOrderConfirmation(
          context,
          saved.confirmation,
          completed: true,
        );
      } else {
        SelloSnackbars.success(context, 'Order marked as delivered.');
      }
    } else if (result.place) {
      SelloSnackbars.success(context, 'Order placed.');
    } else {
      SelloSnackbars.success(
        context,
        'Saved for later.',
      );
    }
  }

  Future<void> _openDetails(OrderSummary order) async {
    final detail =
        await ref.read(orderRepositoryProvider).fetchById(order.id);
    if (!mounted) return;
    if (detail == null) {
      SelloSnackbars.error(context, 'Unable to load that order.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => OrderDetailsDialog(
        detail: detail,
        currencySymbol: _currencySymbol(),
        completeLabel: 'Mark as delivered',
        onEdit: detail.summary.isEditable
            ? () {
                Navigator.of(context).pop();
                _openEditor(existing: detail);
              }
            : null,
        onComplete: detail.summary.isEditable
            ? () async {
                Navigator.of(context).pop();
                await _fulfillAll(detail.summary, fromDraft: true);
              }
            : null,
        onFulfill: detail.summary.status.canFulfill
            ? () async {
                Navigator.of(context).pop();
                await _recordDelivery(detail);
              }
            : null,
        onFulfillAll: detail.summary.status.canFulfill
            ? () async {
                Navigator.of(context).pop();
                await _fulfillAll(detail.summary);
              }
            : null,
        onCancelRemaining: detail.summary.status.canFulfill
            ? () async {
                Navigator.of(context).pop();
                await _cancelRemaining(detail.summary);
              }
            : null,
        onCancelOrder: detail.summary.isEditable ||
                detail.summary.status == OrderStatus.placed
            ? () async {
                Navigator.of(context).pop();
                await _cancel(detail.summary);
              }
            : null,
        onArchive: detail.summary.status == OrderStatus.completed ||
                detail.summary.status == OrderStatus.cancelled
            ? () async {
                Navigator.of(context).pop();
                await _archive(detail.summary);
              }
            : null,
        onViewInvoice: detail.summary.status == OrderStatus.completed
            ? () => _viewInvoice(detail.summary)
            : null,
        onWhatsAppInvoice: detail.summary.status == OrderStatus.completed
            ? () => _whatsAppInvoice(detail.summary)
            : null,
        onSmsInvoice: detail.summary.status == OrderStatus.completed
            ? () => _smsInvoice(detail.summary)
            : null,
      ),
    );
  }

  Future<OrderConfirmationOutcome?> _prepareInvoiceShare(
    String orderId,
  ) async {
    return ref.read(orderConfirmationDispatcherProvider).dispatch(
          orderId,
          smsMode: OrderConfirmationSmsMode.shareActions,
        );
  }

  Future<String> _messagingUnavailableMessage() async {
    final policies =
        await ref.read(orderDocumentRepositoryProvider).fetchOutboundPolicies();
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
      if (customerWa.length == 1 &&
          outcome.hubActions.isEmpty &&
          outcome.salesRepActions.isEmpty) {
        final uri = Uri.tryParse(customerWa.first.launchUri);
        if (uri == null) {
          SelloSnackbars.error(context, 'Unable to open WhatsApp.');
          return;
        }
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && mounted) {
          SelloSnackbars.error(context, 'Unable to open WhatsApp.');
        }
        return;
      }
      await showOrderInvoiceShareSheet(
        context,
        outcome,
        onSendSms: (action) => _sendInvoiceSms(outcome, action),
      );
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
      if (customerSms.length == 1) {
        await _sendInvoiceSms(outcome, customerSms.first);
        return;
      }
      await showOrderInvoiceShareSheet(
        context,
        outcome,
        onSendSms: (action) => _sendInvoiceSms(outcome, action),
      );
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
        SelloSnackbars.success(
          context,
          'SMS was already sent for this order.',
        );
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

  Future<void> _recordDelivery(OrderDetail detail) async {
    final result = await OrderFulfillmentDialog.show(
      context: context,
      detail: detail,
      currencySymbol: _currencySymbol(),
    );
    if (result == null || !mounted) return;

    final error = await ref.read(hubOrdersProvider.notifier).fulfillOrderItems(
          orderId: detail.summary.id,
          lines: result.lines,
        );
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
      // Re-open details so the Owner can adjust and retry.
      await _openDetails(detail.summary);
    } else {
      SelloSnackbars.success(context, 'Delivery recorded.');
      await _openDetails(detail.summary);
    }
  }

  Future<void> _fulfillAll(
    OrderSummary order, {
    bool fromDraft = false,
  }) async {
    final confirmed = await showSelloDialog(
      context: context,
      title: fromDraft ? 'Mark as delivered?' : 'Deliver remaining?',
      message: fromDraft
          ? '${order.orderNumber} will be placed and all quantities delivered. '
              'Stock will be reduced for every line. Payment is not settled automatically.'
          : '${order.orderNumber}: deliver every remaining unit now. '
              'Stock will be reduced only for remaining quantities. Payment is not settled automatically.',
      confirmLabel: fromDraft ? 'Mark as delivered' : 'Deliver remaining',
      cancelLabel: 'Back',
    );
    if (confirmed != true || !mounted) return;

    if (fromDraft) {
      final saved =
          await ref.read(hubOrdersProvider.notifier).completeExisting(order);
      if (!mounted) return;
      if (!saved.isOk) {
        SelloSnackbars.error(
          context,
          saved.error ?? 'Unable to mark this order as delivered.',
        );
      } else {
        if (saved.confirmation != null) {
          await presentOrderConfirmation(
            context,
            saved.confirmation,
            completed: true,
          );
        } else {
          SelloSnackbars.success(context, 'Order marked as delivered.');
        }
      }
      return;
    }

    final saved =
        await ref.read(hubOrdersProvider.notifier).fulfillAllRemaining(order);
    if (!mounted) return;
    if (!saved.isOk) {
      SelloSnackbars.error(
        context,
        saved.error ?? 'Unable to deliver remaining items.',
      );
    } else {
      if (saved.confirmation != null) {
        await presentOrderConfirmation(
          context,
          saved.confirmation,
          completed: true,
        );
      } else {
        SelloSnackbars.success(context, 'Remaining items delivered.');
      }
    }
  }

  Future<void> _cancelRemaining(OrderSummary order) async {
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Cancel remaining?',
      message:
          'Close unmet quantities on ${order.orderNumber}. '
          'Already delivered quantities stay recorded. Stock is not changed for cancelled units.',
      confirmLabel: 'Cancel remaining',
      cancelLabel: 'Keep open',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final error = await ref
        .read(hubOrdersProvider.notifier)
        .cancelOrderRemaining(order.id);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(context, 'Remaining quantities cancelled.');
    }
  }

  Future<void> _archive(OrderSummary order) async {
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Archive order?',
      message:
          '${order.orderNumber} will be hidden from the Orders list. '
          'History remains available for reporting.',
      confirmLabel: 'Archive',
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final error =
        await ref.read(hubOrdersProvider.notifier).archiveOrder(order);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(context, 'Order archived.');
    }
  }

  Future<void> _cancel(OrderSummary order) async {
    final confirmed = await showSelloDialog(
      context: context,
      title: 'Cancel order?',
      message: order.status == OrderStatus.placed
          ? '${order.orderNumber} will be cancelled. No inventory will change.'
          : '${order.orderNumber} will be cancelled. Draft and cancelled orders '
              'never reduce inventory.',
      confirmLabel: 'Cancel order',
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    final error =
        await ref.read(hubOrdersProvider.notifier).cancelOrder(order);
    if (!mounted) return;
    if (error != null) {
      SelloSnackbars.error(context, error);
    } else {
      SelloSnackbars.success(context, 'Order cancelled.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hubOrdersProvider);
    ref.watch(hubSettingsProvider);
    final currencySymbol = _currencySymbol();

    if (_searchController.text != state.search) {
      _searchController.value = TextEditingValue(
        text: state.search,
        selection: TextSelection.collapsed(offset: state.search.length),
      );
    }

    return AppPageScaffold(
      title: 'Orders',
      subtitle:
          'Your sales workspace — create drafts, complete sales, and keep stock in sync.',
      maxWidth: AppSpacing.contentMax,
      headerSpacing: AppSpacing.lg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OrdersToolbar(
            searchController: _searchController,
            state: state,
            onSearchChanged: (value) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(
                const Duration(milliseconds: 300),
                () => ref.read(hubOrdersProvider.notifier).setSearch(value),
              );
            },
            onStatusChanged: (value) {
              if (value != null) {
                ref.read(hubOrdersProvider.notifier).setStatusFilter(value);
              }
            },
            onPaymentChanged: (value) {
              if (value != null) {
                ref.read(hubOrdersProvider.notifier).setPaymentFilter(value);
              }
            },
            onDateChanged: (value) {
              if (value != null) {
                ref.read(hubOrdersProvider.notifier).setDateFilter(value);
              }
            },
            onRepChanged: (value) {
              ref.read(hubOrdersProvider.notifier).setEmployeeFilter(
                    value == _allReps ? null : value,
                  );
            },
            onRefresh: state.isLoading
                ? null
                : () => ref.read(hubOrdersProvider.notifier).refresh(),
            onAdd: state.isSaving ? null : () => _openEditor(),
          ),
          const SizedBox(height: AppSpacing.mdPlus),
          if (state.isLoading && state.items.isEmpty) ...[
            if (context.isMobile)
              const SelloListSkeleton()
            else
              const SelloTableSkeleton(columns: 8),
          ] else ...[
            _OrdersSummaryRow(counts: state.counts),
            const SizedBox(height: AppSpacing.lg),
            if (state.errorMessage != null && state.items.isEmpty)
              SizedBox(
                height: 320,
                child: SelloStateView.error(
                  title: 'Unable to load orders',
                  message: state.errorMessage,
                  actionLabel: 'Try again',
                  onAction: () =>
                      ref.read(hubOrdersProvider.notifier).refresh(),
                ),
              )
            else if (state.isEmpty)
              SelloCard(
                child: SelloEmptyState(
                  title: 'No orders yet',
                  message:
                      'Create your first order: pick a customer, add products, '
                      'then save a draft or complete the sale. Completing an '
                      'order reduces branch inventory automatically.',
                  icon: Icons.receipt_long_rounded,
                  actionLabel: 'New Order',
                  onAction: () => _openEditor(),
                ),
              )
            else if (context.isMobile)
              SelloFadeIn(
                child: Column(
                  children: [
                    for (final order in state.items) ...[
                      _OrderMobileCard(
                        order: order,
                        currencySymbol: currencySymbol,
                        onOpen: () => _openDetails(order),
                        onEdit: order.isEditable
                            ? () async {
                                final detail = await ref
                                    .read(orderRepositoryProvider)
                                    .fetchById(order.id);
                                if (detail != null && mounted) {
                                  await _openEditor(existing: detail);
                                }
                              }
                            : null,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _OrdersPager(
                      page: state.page,
                      hasMore: state.hasMore,
                      onPrev: state.page <= 0
                          ? null
                          : () => ref
                              .read(hubOrdersProvider.notifier)
                              .goToPage(state.page - 1),
                      onNext: !state.hasMore
                          ? null
                          : () => ref
                              .read(hubOrdersProvider.notifier)
                              .goToPage(state.page + 1),
                    ),
                  ],
                ),
              )
            else
              SelloFadeIn(
                child: SelloDataTable(
                  columns: [
                    selloDataColumn('Invoice No'),
                    selloDataColumn('Customer'),
                    selloDataColumn('Representative'),
                    selloDataColumn('Total', numeric: true),
                    selloDataColumn('Payment'),
                    selloDataColumn('Status'),
                    selloDataColumn('Created'),
                    selloDataColumn('Actions'),
                  ],
                  rows: [
                    for (final order in state.items)
                      DataRow(
                        cells: [
                          DataCell(
                            SelloTableText(
                              order.orderNumber,
                              tone: SelloTableTone.strong,
                            ),
                          ),
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SelloTableText(
                                  order.customerName ?? '—',
                                  tone: SelloTableTone.strong,
                                ),
                                if (order.customerPhone != null) ...[
                                  const SizedBox(height: 2),
                                  SelloTableText(
                                    order.customerPhone!,
                                    tone: SelloTableTone.muted,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          DataCell(
                            SelloTableText(order.employeeName ?? '—'),
                          ),
                          DataCell(
                            SelloTableText(
                              SelloFormatters.currency(
                                order.total,
                                symbol: currencySymbol,
                              ),
                              tone: SelloTableTone.strong,
                              numeric: true,
                            ),
                          ),
                          DataCell(_paymentBadge(order.paymentStatus)),
                          DataCell(_statusBadge(order.status)),
                          DataCell(
                            SelloTableText(
                              SelloFormatters.date(order.orderedAt),
                              tone: SelloTableTone.muted,
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SelloButton(
                                  label: 'View',
                                  size: SelloButtonSize.small,
                                  variant: SelloButtonVariant.ghost,
                                  onPressed: () => _openDetails(order),
                                ),
                                if (order.isEditable) ...[
                                  const SizedBox(width: 4),
                                  SelloButton(
                                    label: 'Edit',
                                    size: SelloButtonSize.small,
                                    variant: SelloButtonVariant.outline,
                                    onPressed: () async {
                                      final detail = await ref
                                          .read(orderRepositoryProvider)
                                          .fetchById(order.id);
                                      if (detail != null && mounted) {
                                        await _openEditor(existing: detail);
                                      }
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                  footer: _OrdersPager(
                    page: state.page,
                    hasMore: state.hasMore,
                    onPrev: state.page <= 0
                        ? null
                        : () => ref
                            .read(hubOrdersProvider.notifier)
                            .goToPage(state.page - 1),
                    onNext: !state.hasMore
                        ? null
                        : () => ref
                            .read(hubOrdersProvider.notifier)
                            .goToPage(state.page + 1),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

const _allReps = '__all__';

Widget _statusBadge(OrderStatus status) {
  return SelloStatusBadge(
    label: status.label,
    tone: switch (status) {
      OrderStatus.draft => SelloStatusTone.neutral,
      OrderStatus.placed => SelloStatusTone.info,
      OrderStatus.partiallyDelivered => SelloStatusTone.warning,
      OrderStatus.completed => SelloStatusTone.success,
      OrderStatus.cancelled => SelloStatusTone.danger,
    },
  );
}

Widget _paymentBadge(PaymentStatus status) {
  return SelloStatusBadge(
    label: status.label,
    tone: switch (status) {
      PaymentStatus.paid => SelloStatusTone.success,
      PaymentStatus.partial => SelloStatusTone.info,
      PaymentStatus.refunded => SelloStatusTone.warning,
      PaymentStatus.unpaid => SelloStatusTone.warning,
    },
  );
}

class _OrdersToolbar extends StatelessWidget {
  const _OrdersToolbar({
    required this.searchController,
    required this.state,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onPaymentChanged,
    required this.onDateChanged,
    required this.onRepChanged,
    required this.onRefresh,
    required this.onAdd,
  });

  final TextEditingController searchController;
  final HubOrdersState state;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<OrderStatusFilter?> onStatusChanged;
  final ValueChanged<OrderPaymentFilter?> onPaymentChanged;
  final ValueChanged<OrderDateFilter?> onDateChanged;
  final ValueChanged<String?> onRepChanged;
  final VoidCallback? onRefresh;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final status = SizedBox(
      width: context.isMobile ? double.infinity : 140,
      child: SelloDropdown<OrderStatusFilter>(
        value: state.statusFilter,
        compact: true,
        hint: 'Status',
        onChanged: onStatusChanged,
        items: const [
          DropdownMenuItem(value: OrderStatusFilter.all, child: Text('All')),
          DropdownMenuItem(
            value: OrderStatusFilter.draft,
            child: Text('Open'),
          ),
          DropdownMenuItem(
            value: OrderStatusFilter.openFulfillment,
            child: Text('Waiting to deliver'),
          ),
          DropdownMenuItem(
            value: OrderStatusFilter.placed,
            child: Text('Placed'),
          ),
          DropdownMenuItem(
            value: OrderStatusFilter.partiallyDelivered,
            child: Text('Partially delivered'),
          ),
          DropdownMenuItem(
            value: OrderStatusFilter.completed,
            child: Text('Completed'),
          ),
          DropdownMenuItem(
            value: OrderStatusFilter.cancelled,
            child: Text('Cancelled'),
          ),
        ],
      ),
    );

    final payment = SizedBox(
      width: context.isMobile ? double.infinity : 140,
      child: SelloDropdown<OrderPaymentFilter>(
        value: state.paymentFilter,
        compact: true,
        hint: 'Payment',
        onChanged: onPaymentChanged,
        items: const [
          DropdownMenuItem(
            value: OrderPaymentFilter.all,
            child: Text('All'),
          ),
          DropdownMenuItem(
            value: OrderPaymentFilter.unpaid,
            child: Text('Unpaid'),
          ),
          DropdownMenuItem(
            value: OrderPaymentFilter.partial,
            child: Text('Partial'),
          ),
          DropdownMenuItem(
            value: OrderPaymentFilter.paid,
            child: Text('Paid'),
          ),
        ],
      ),
    );

    final date = SizedBox(
      width: context.isMobile ? double.infinity : 148,
      child: SelloDropdown<OrderDateFilter>(
        value: state.dateFilter,
        compact: true,
        hint: 'Date',
        onChanged: onDateChanged,
        items: const [
          DropdownMenuItem(
            value: OrderDateFilter.all,
            child: Text('All time'),
          ),
          DropdownMenuItem(
            value: OrderDateFilter.today,
            child: Text('Today'),
          ),
          DropdownMenuItem(
            value: OrderDateFilter.last7Days,
            child: Text('Last 7 days'),
          ),
          DropdownMenuItem(
            value: OrderDateFilter.thisMonth,
            child: Text('This month'),
          ),
        ],
      ),
    );

    final rep = SizedBox(
      width: context.isMobile ? double.infinity : 168,
      child: SelloDropdown<String>(
        value: state.employeeId ?? _allReps,
        compact: true,
        hint: 'Representative',
        onChanged: onRepChanged,
        items: [
          const DropdownMenuItem(value: _allReps, child: Text('All reps')),
          for (final person in state.reps)
            DropdownMenuItem(value: person.id, child: Text(person.name)),
        ],
      ),
    );

    final refresh = SelloButton(
      label: 'Refresh',
      icon: Icons.refresh_rounded,
      variant: SelloButtonVariant.outline,
      onPressed: onRefresh,
    );

    final add = SelloButton(
      label: 'New Order',
      icon: Icons.add_rounded,
      variant: SelloButtonVariant.primary,
      onPressed: onAdd,
    );

    final search = SelloSearchBar(
      controller: searchController,
      hint: 'Search invoice, customer, phone, rep or product…',
      onChanged: onSearchChanged,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.mdPlus),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.panelAll,
        border: Border.all(color: AppColors.outlinePanel),
        boxShadow: AppShadows.panel,
      ),
      child: context.isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: AppSpacing.sm),
                status,
                const SizedBox(height: AppSpacing.sm),
                payment,
                const SizedBox(height: AppSpacing.sm),
                date,
                const SizedBox(height: AppSpacing.sm),
                rep,
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: refresh),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: add),
                  ],
                ),
              ],
            )
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: AppSpacing.sm),
                    status,
                    const SizedBox(width: AppSpacing.sm),
                    payment,
                    const SizedBox(width: AppSpacing.sm),
                    date,
                    const SizedBox(width: AppSpacing.sm),
                    rep,
                    const SizedBox(width: AppSpacing.sm),
                    refresh,
                    const SizedBox(width: AppSpacing.xs),
                    add,
                  ],
                ),
              ],
            ),
    );
  }
}

class _OrdersSummaryRow extends StatelessWidget {
  const _OrdersSummaryRow({required this.counts});

  final OrderCounts counts;

  @override
  Widget build(BuildContext context) {
    return SelloStatCardGrid(
      children: [
        SelloStatCard(
          label: 'Total',
          value: '${counts.total}',
          hint: 'All orders',
          icon: Icons.receipt_long_outlined,
          tone: context.brandAccent,
        ),
        SelloStatCard(
          label: 'Open',
          value: '${counts.draft}',
          hint: 'Draft, placed, partial',
          icon: Icons.edit_note_rounded,
          tone: AppColors.textTertiary,
        ),
        SelloStatCard(
          label: 'Completed',
          value: '${counts.completed}',
          hint: 'All goods delivered',
          icon: Icons.check_circle_outline_rounded,
          tone: AppColors.success,
        ),
        SelloStatCard(
          label: 'Cancelled',
          value: '${counts.cancelled}',
          hint: 'No stock impact',
          icon: Icons.cancel_outlined,
          tone: AppColors.error,
        ),
      ],
    );
  }
}

class _OrderMobileCard extends StatelessWidget {
  const _OrderMobileCard({
    required this.order,
    required this.currencySymbol,
    required this.onOpen,
    this.onEdit,
  });

  final OrderSummary order;
  final String currencySymbol;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return SelloCard(
      onTap: onOpen,
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
                    fontSize: 16,
                  ),
                ),
              ),
              _statusBadge(order.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            order.customerName ?? 'Customer',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                SelloFormatters.currency(
                  order.total,
                  symbol: currencySymbol,
                ),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (onEdit != null)
                SelloButton(
                  label: 'Edit',
                  size: SelloButtonSize.small,
                  variant: SelloButtonVariant.outline,
                  onPressed: onEdit,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrdersPager extends StatelessWidget {
  const _OrdersPager({
    required this.page,
    required this.hasMore,
    this.onPrev,
    this.onNext,
  });

  final int page;
  final bool hasMore;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SelloButton(
            label: 'Previous',
            size: SelloButtonSize.small,
            variant: SelloButtonVariant.outline,
            onPressed: onPrev,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Page ${page + 1}',
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
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
