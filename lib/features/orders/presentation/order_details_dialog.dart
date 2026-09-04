import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/products/application/product_fields_provider.dart';
import 'package:sello/shared/models/order_status.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/models/order_timeline.dart';
import 'package:sello/shared/models/payment_status.dart';
import 'package:sello/shared/models/product_field.dart';
import 'package:sello/shared/utils/country_catalog.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/badges/sello_badge.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/dialogs/sello_form_dialog.dart';
import 'package:sello/shared/widgets/feedback/entity_activity_panel.dart';

/// Order Workspace — operational profile for a sale.
class OrderDetailsDialog extends ConsumerWidget {
  const OrderDetailsDialog({
    super.key,
    required this.detail,
    required this.currencySymbol,
    this.onEdit,
    this.onComplete,
    this.completeLabel = 'Mark as delivered',
    this.onFulfill,
    this.onFulfillAll,
    this.onCancelRemaining,
    this.onCancelOrder,
    this.onArchive,
    this.onViewInvoice,
    this.onWhatsAppInvoice,
    this.onSmsInvoice,
    this.readOnly = false,
  });

  final OrderDetail detail;
  final String currencySymbol;
  final VoidCallback? onEdit;
  final VoidCallback? onComplete;
  final String completeLabel;
  final VoidCallback? onFulfill;
  final VoidCallback? onFulfillAll;
  final VoidCallback? onCancelRemaining;
  final VoidCallback? onCancelOrder;
  final VoidCallback? onArchive;

  /// Opens the customer invoice document in the browser.
  final VoidCallback? onViewInvoice;

  /// Opens WhatsApp with the invoice confirmation prefilled.
  final VoidCallback? onWhatsAppInvoice;

  /// Sends the invoice confirmation SMS to the customer.
  final VoidCallback? onSmsInvoice;

  final bool readOnly;

  static const double _sectionGap = 32;

  OrderSummary get order => detail.summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = context.isMobile;
    final dash = '—';
    final canManageDraft = !readOnly && order.isEditable;
    final canFulfill = !readOnly &&
        order.status.canFulfill &&
        onFulfill != null;
    final canArchive = !readOnly &&
        onArchive != null &&
        (order.status == OrderStatus.completed ||
            order.status == OrderStatus.cancelled);
    final totalOrdered = detail.lines.fold<num>(0, (s, l) => s + l.quantity);
    final totalDelivered =
        detail.lines.fold<num>(0, (s, l) => s + l.deliveredQuantity);
    final totalRemaining =
        detail.lines.fold<num>(0, (s, l) => s + l.remainingQuantity);
    final totalCancelled =
        detail.lines.fold<num>(0, (s, l) => s + l.cancelledQuantity);
    final fieldConfig = ref.watch(productFieldConfigProvider).valueOrNull ??
        ProductFieldConfig(fields: []);

    return SelloFormDialog(
      header: _OrderHero(order: order),
      maxWidth: kSelloDetailDialogWidth,
      fullscreenOnMobile: true,
      bodyPadding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 36,
        isMobile ? 16 : 20,
        isMobile ? 20 : 36,
        16,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (order.status == OrderStatus.cancelled) ...[
            const _NoticeBanner(
              icon: Icons.info_outline_rounded,
              tone: AppColors.info,
              background: AppColors.infoContainer,
              message:
                  'Cancelled orders do not affect inventory. Historical totals stay available for reporting.',
            ),
            const SizedBox(height: _sectionGap),
          ],
          _Section(
            label: 'Customer',
            child: Column(
              children: [
                SelloFormRow(
                  left: _Field(
                    label: 'Name',
                    value: order.customerName ?? dash,
                    mutedEmpty: order.customerName == null,
                  ),
                  right: _Field(
                    label: 'Phone',
                    value: order.customerPhone ?? dash,
                    mutedEmpty: order.customerPhone == null,
                  ),
                ),
                if (detail.customerOutstanding != null ||
                    detail.customerWallet != null) ...[
                  const SizedBox(height: 18),
                  SelloFormRow(
                    left: _Field(
                      label: 'Outstanding balance',
                      value: SelloFormatters.currency(
                        detail.customerOutstanding ?? 0,
                        symbol: currencySymbol,
                      ),
                    ),
                    right: _Field(
                      label: 'Wallet',
                      value: SelloFormatters.currency(
                        detail.customerWallet ?? 0,
                        symbol: currencySymbol,
                      ),
                    ),
                  ),
                ],
                if (detail.customerCreditAllowed != null) ...[
                  const SizedBox(height: 18),
                  SelloFormRow(
                    left: _Field(
                      label: 'Credit',
                      value: detail.customerCreditAllowed == true
                          ? SelloFormatters.currency(
                              detail.customerCreditLimit ?? 0,
                              symbol: currencySymbol,
                            )
                          : 'Not allowed',
                      mutedEmpty: detail.customerCreditAllowed != true,
                    ),
                    right: _Field(
                      label: 'Sales representative',
                      value: order.employeeName ?? dash,
                      mutedEmpty: order.employeeName == null,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),
          if (!order.isDraft) ...[
            _Section(
              label: 'Delivery',
              child: Column(
                children: [
                  SelloFormRow(
                    left: _Field(
                      label: 'Ordered',
                      value: SelloFormatters.quantity(totalOrdered),
                    ),
                    right: _Field(
                      label: 'Delivered',
                      value: SelloFormatters.quantity(totalDelivered),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SelloFormRow(
                    left: _Field(
                      label: 'Remaining',
                      value: SelloFormatters.quantity(totalRemaining),
                    ),
                    right: _Field(
                      label: 'Cancelled',
                      value: totalCancelled > 0
                          ? SelloFormatters.quantity(totalCancelled)
                          : dash,
                      mutedEmpty: totalCancelled <= 0,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SelloFormRow(
                    left: _Field(
                      label: 'Order date',
                      value: SelloFormatters.date(order.orderedAt),
                    ),
                    right: _Field(
                      label: 'Payment',
                      value: order.paymentStatus.label,
                    ),
                  ),
                  if (canFulfill && onFulfillAll != null) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelloButton(
                        label: 'Deliver remaining',
                        variant: SelloButtonVariant.outline,
                        size: SelloButtonSize.small,
                        onPressed: onFulfillAll,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: _sectionGap),
          ],
          _Section(
            label: 'Products',
            child: detail.lines.isEmpty
                ? Text(
                    'No products on this order.',
                    style: _Type.label.copyWith(color: AppColors.textFaint),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < detail.lines.length; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        _LineRow(
                          line: detail.lines[i],
                          currencySymbol: currencySymbol,
                          catalogFields: fieldConfig.forCatalog,
                          showFulfillment: !order.isDraft,
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: _sectionGap),
          _Section(
            label: 'Totals',
            child: Column(
              children: [
                SelloFormRow(
                  left: _Field(
                    label: 'Subtotal',
                    value: SelloFormatters.currency(
                      order.subtotal,
                      symbol: currencySymbol,
                    ),
                  ),
                  right: _Field(
                    label: 'Discount',
                    value: SelloFormatters.currency(
                      order.discountAmount,
                      symbol: currencySymbol,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SelloFormRow(
                  left: _Field(
                    label: 'Tax',
                    value: order.taxAmount > 0
                        ? SelloFormatters.currency(
                            order.taxAmount,
                            symbol: currencySymbol,
                          )
                        : 'Reserved',
                    mutedEmpty: order.taxAmount <= 0,
                  ),
                  right: _Field(
                    label: 'Grand total',
                    value: SelloFormatters.currency(
                      order.total,
                      symbol: currencySymbol,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SelloFormRow(
                  left: _Field(
                    label: 'Payment status',
                    value: order.paymentStatus.label,
                  ),
                  right: _Field(
                    label: 'Order status',
                    value: order.status.label,
                  ),
                ),
                const SizedBox(height: 18),
                _Field(
                  label: 'Payment method',
                  value: order.paymentMethod?.label ?? dash,
                  mutedEmpty: order.paymentMethod == null,
                ),
              ],
            ),
          ),
          if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: _sectionGap),
            _Section(
              label: 'Notes',
              child: Text(
                order.notes!,
                style: _Type.value.copyWith(
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: _sectionGap),
          _Section(
            label: 'Company activity',
            child: EntityActivityPanel(
              referenceType: 'order',
              referenceId: order.id,
              emptyMessage: 'Company activity for this order will appear here.',
            ),
          ),
          const SizedBox(height: _sectionGap),
          _Section(
            label: 'Timeline',
            child: detail.timeline.isEmpty
                ? Text(
                    'No activity recorded yet.',
                    style: _Type.label.copyWith(color: AppColors.textFaint),
                  )
                : _Timeline(events: detail.timeline),
          ),
        ],
      ),
      footer: canManageDraft
          ? SelloDialogFooter(
              destructiveLabel: 'Cancel order',
              onDestructive: onCancelOrder,
              cancelLabel: 'Edit draft',
              cancelVariant: SelloButtonVariant.outline,
              onCancel: onEdit,
              primaryLabel: completeLabel,
              onPrimary: onComplete,
            )
          : canFulfill
              ? SelloDialogFooter(
                  destructiveLabel: totalDelivered > 0
                      ? 'Cancel remaining'
                      : 'Cancel order',
                  onDestructive: totalDelivered > 0
                      ? onCancelRemaining
                      : onCancelOrder,
                  cancelLabel: 'Close',
                  cancelVariant: SelloButtonVariant.outline,
                  onCancel: () => Navigator.of(context).maybePop(),
                  primaryLabel: 'Record delivery',
                  onPrimary: onFulfill,
                )
              : SelloDialogFooter(
                  destructiveLabel: canArchive ? 'Archive' : null,
                  onDestructive: canArchive ? onArchive : null,
                  leading: _InvoiceFooterLinks(
                    onViewInvoice: onViewInvoice,
                    onWhatsAppInvoice: onWhatsAppInvoice,
                    onSmsInvoice: onSmsInvoice,
                  ),
                  cancelLabel: 'Close',
                  cancelVariant: SelloButtonVariant.outline,
                  onCancel: () => Navigator.of(context).maybePop(),
                  primaryLabel: 'Done',
                  onPrimary: () => Navigator.of(context).maybePop(),
                ),
    );
  }
}

/// Quiet invoice actions for the completed-order footer.
class _InvoiceFooterLinks extends StatelessWidget {
  const _InvoiceFooterLinks({
    this.onViewInvoice,
    this.onWhatsAppInvoice,
    this.onSmsInvoice,
  });

  final VoidCallback? onViewInvoice;
  final VoidCallback? onWhatsAppInvoice;
  final VoidCallback? onSmsInvoice;

  bool get _hasAny =>
      onViewInvoice != null ||
      onWhatsAppInvoice != null ||
      onSmsInvoice != null;

  @override
  Widget build(BuildContext context) {
    if (!_hasAny) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (onViewInvoice != null)
          _InvoiceLink(
            label: 'View invoice',
            icon: Icons.open_in_new_rounded,
            onPressed: onViewInvoice!,
          ),
        if (onWhatsAppInvoice != null)
          _InvoiceLink(
            label: 'WhatsApp',
            icon: Icons.chat_bubble_outline_rounded,
            onPressed: onWhatsAppInvoice!,
          ),
        if (onSmsInvoice != null)
          _InvoiceLink(
            label: 'SMS',
            icon: Icons.sms_outlined,
            onPressed: onSmsInvoice!,
          ),
      ],
    );
  }
}

class _InvoiceLink extends StatelessWidget {
  const _InvoiceLink({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: AppColors.textSecondary),
      label: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _OrderHero extends StatelessWidget {
  const _OrderHero({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (order.customerName != null) order.customerName!,
      if (order.employeeName != null) order.employeeName!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(order.orderNumber, style: _Type.title),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(meta.join(' · '), style: _Type.subtitle),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SelloStatusBadge(
              label: order.status.label,
              tone: switch (order.status) {
                OrderStatus.draft => SelloStatusTone.neutral,
                OrderStatus.placed => SelloStatusTone.info,
                OrderStatus.partiallyDelivered => SelloStatusTone.warning,
                OrderStatus.completed => SelloStatusTone.success,
                OrderStatus.cancelled => SelloStatusTone.danger,
              },
            ),
            SelloStatusBadge(
              label: order.paymentStatus.label,
              tone: switch (order.paymentStatus) {
                PaymentStatus.paid => SelloStatusTone.success,
                PaymentStatus.partial => SelloStatusTone.info,
                PaymentStatus.refunded => SelloStatusTone.warning,
                PaymentStatus.unpaid => SelloStatusTone.warning,
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({
    required this.icon,
    required this.tone,
    required this.background,
    required this.message,
  });

  final IconData icon;
  final Color tone;
  final Color background;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: _Type.label.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.events});

  final List<OrderTimelineEvent> events;

  IconData _iconFor(OrderTimelineKind kind) {
    return switch (kind) {
      OrderTimelineKind.created => Icons.fiber_new_rounded,
      OrderTimelineKind.updated => Icons.edit_outlined,
      OrderTimelineKind.submitted => Icons.send_rounded,
      OrderTimelineKind.completed => Icons.check_circle_outline_rounded,
      OrderTimelineKind.cancelled => Icons.cancel_outlined,
      OrderTimelineKind.stockMoved => Icons.inventory_2_outlined,
      OrderTimelineKind.paymentReceived => Icons.payments_outlined,
      OrderTimelineKind.archived => Icons.archive_outlined,
      OrderTimelineKind.note => Icons.sticky_note_2_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < events.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.outlinePanel),
                ),
                child: Icon(
                  _iconFor(events[i].kind),
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(events[i].title, style: _Type.value),
                    const SizedBox(height: 2),
                    Text(
                      SelloFormatters.dateTime(events[i].at),
                      style: _Type.label.copyWith(color: AppColors.textFaint),
                    ),
                    if (events[i].detail != null &&
                        events[i].detail!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        events[i].detail!,
                        style: _Type.label.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label.toUpperCase(), style: _Type.section),
        const SizedBox(height: 14),
        child,
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.mutedEmpty = false,
  });

  final String label;
  final String value;
  final bool mutedEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _Type.label),
        const SizedBox(height: 6),
        Text(
          value,
          style: _Type.value.copyWith(
            color: mutedEmpty ? AppColors.textFaint : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.currencySymbol,
    required this.catalogFields,
    this.showFulfillment = false,
  });

  final OrderLineItem line;
  final String currencySymbol;
  final List<CompanyProductField> catalogFields;
  final bool showFulfillment;

  String? _specLine() {
    final parts = <String>[];
    if (line.productSku != null && line.productSku!.isNotEmpty) {
      parts.add(line.productSku!);
    }
    if (line.productBrand != null && line.productBrand!.trim().isNotEmpty) {
      parts.add(line.productBrand!.trim());
    }
    for (final field in catalogFields) {
      if (field.definition.storage != ProductFieldStorage.attribute) continue;
      final raw = line.productAttributes[field.fieldKey];
      if (raw == null || raw.trim().isEmpty) continue;
      final display = field.definition.fieldType == ProductFieldType.country
          ? CountryCatalog.display(raw)
          : raw.trim();
      parts.add(display);
      if (parts.length >= 4) break;
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final specs = _specLine();
    final discount = line.discount != null && line.discount! > 0
        ? ' · Disc ${line.discountType == 'percentage' ? '${line.discount}%' : SelloFormatters.currency(line.discount!, symbol: currencySymbol)}'
        : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.productName ?? 'Product',
                style: _Type.value.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                '${SelloFormatters.quantity(line.quantity)} × '
                '${SelloFormatters.currency(line.unitPrice, symbol: currencySymbol)}'
                '$discount',
                style: _Type.label.copyWith(color: AppColors.textSecondary),
              ),
              if (showFulfillment) ...[
                const SizedBox(height: 4),
                Text(
                  '${SelloFormatters.quantity(line.deliveredQuantity)} delivered · '
                  '${SelloFormatters.quantity(line.remainingQuantity)} remaining'
                  '${line.cancelledQuantity > 0 ? ' · ${SelloFormatters.quantity(line.cancelledQuantity)} cancelled' : ''}',
                  style: _Type.label.copyWith(color: AppColors.textFaint),
                ),
              ],
              if (specs != null) ...[
                const SizedBox(height: 4),
                Text(
                  specs,
                  style: _Type.label.copyWith(color: AppColors.textFaint),
                ),
              ],
            ],
          ),
        ),
        Text(
          SelloFormatters.currency(line.lineTotal, symbol: currencySymbol),
          style: _Type.value,
        ),
      ],
    );
  }
}

abstract final class _Type {
  static const TextStyle title = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.45,
    height: 1.15,
    color: AppColors.textPrimary,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const TextStyle section = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.08 * 11,
    height: 1.2,
    color: AppColors.textFaint,
  );

  static const TextStyle label = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.textSecondary,
  );

  static const TextStyle value = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
    color: AppColors.textPrimary,
  );
}
