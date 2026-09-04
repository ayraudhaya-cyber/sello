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

/// Internal staff Order Details workspace — not the customer invoice document.
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

  static const double _sectionGap = 26;

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
    final hasNotes = order.notes != null && order.notes!.trim().isNotEmpty;
    final hasAccountExtras = detail.customerWallet != null ||
        detail.customerCreditAllowed != null;

    return SelloFormDialog(
      header: _OrderHero(order: order),
      maxWidth: kSelloDetailDialogWidth,
      fullscreenOnMobile: true,
      bodyPadding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 32,
        isMobile ? 12 : 16,
        isMobile ? 20 : 32,
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
          _InfoGrid(
            customer: _InfoBlock(
              title: 'Customer',
              fields: [
                _InfoField(
                  label: 'Name',
                  value: order.customerName ?? dash,
                  muted: order.customerName == null,
                ),
                _InfoField(
                  label: 'Phone',
                  value: order.customerPhone ?? dash,
                  muted: order.customerPhone == null,
                ),
                if (detail.customerOutstanding != null)
                  _InfoField(
                    label: 'Outstanding balance',
                    value: SelloFormatters.currency(
                      detail.customerOutstanding!,
                      symbol: currencySymbol,
                    ),
                  ),
              ],
            ),
            order: _InfoBlock(
              title: 'Order',
              fields: [
                _InfoField(
                  label: 'Order date',
                  value: SelloFormatters.date(order.orderedAt),
                ),
                _InfoField(
                  label: 'Sales representative',
                  value: order.employeeName ?? dash,
                  muted: order.employeeName == null,
                ),
                if (order.paymentMethod != null)
                  _InfoField(
                    label: 'Payment method',
                    value: order.paymentMethod!.label,
                  ),
              ],
            ),
            delivery: order.isDraft
                ? null
                : _InfoBlock(
                    title: 'Delivery',
                    fields: [
                      _InfoField(
                        label: 'Ordered',
                        value: SelloFormatters.quantity(totalOrdered),
                      ),
                      _InfoField(
                        label: 'Delivered',
                        value: SelloFormatters.quantity(totalDelivered),
                      ),
                      _InfoField(
                        label: 'Remaining',
                        value: SelloFormatters.quantity(totalRemaining),
                      ),
                      if (totalCancelled > 0)
                        _InfoField(
                          label: 'Cancelled',
                          value: SelloFormatters.quantity(totalCancelled),
                        ),
                    ],
                    trailing: canFulfill && onFulfillAll != null
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: SelloButton(
                              label: 'Deliver remaining',
                              variant: SelloButtonVariant.outline,
                              size: SelloButtonSize.small,
                              onPressed: onFulfillAll,
                            ),
                          )
                        : null,
                  ),
          ),
          if (hasAccountExtras) ...[
            const SizedBox(height: 10),
            _AccountExtras(
              currencySymbol: currencySymbol,
              wallet: detail.customerWallet,
              creditAllowed: detail.customerCreditAllowed,
              creditLimit: detail.customerCreditLimit,
            ),
          ],
          const SizedBox(height: _sectionGap),
          _Section(
            label: 'Products',
            child: detail.lines.isEmpty
                ? Text(
                    'No products on this order.',
                    style: _Type.meta,
                  )
                : _ProductsTable(
                    lines: detail.lines,
                    currencySymbol: currencySymbol,
                    catalogFields: fieldConfig.forCatalog,
                    showDelivery: !order.isDraft,
                  ),
          ),
          const SizedBox(height: _sectionGap),
          _Section(
            label: 'Totals',
            child: _TotalsBlock(
              currencySymbol: currencySymbol,
              subtotal: order.subtotal,
              discount: order.discountAmount,
              tax: order.taxAmount,
              total: order.total,
            ),
          ),
          if (hasNotes) ...[
            const SizedBox(height: _sectionGap),
            _Section(
              label: 'Notes',
              child: Text(
                order.notes!.trim(),
                style: _Type.body,
              ),
            ),
          ],
          const SizedBox(height: _sectionGap),
          _Section(
            label: 'Activity',
            child: detail.timeline.isEmpty
                ? Text(
                    'No activity recorded yet.',
                    style: _Type.meta,
                  )
                : _CompactTimeline(events: detail.timeline),
          ),
          const SizedBox(height: 18),
          _Section(
            label: 'Company activity',
            child: EntityActivityPanel(
              referenceType: 'order',
              referenceId: order.id,
              emptyMessage: 'Company activity for this order will appear here.',
            ),
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
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
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
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(meta.join(' · '), style: _Type.subtitle),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: _Type.body),
          ),
        ],
      ),
    );
  }
}

class _InfoField {
  const _InfoField({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool muted;
}

class _InfoBlock {
  const _InfoBlock({
    required this.title,
    required this.fields,
    this.trailing,
  });

  final String title;
  final List<_InfoField> fields;
  final Widget? trailing;
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({
    required this.customer,
    required this.order,
    this.delivery,
  });

  final _InfoBlock customer;
  final _InfoBlock order;
  final _InfoBlock? delivery;

  @override
  Widget build(BuildContext context) {
    final blocks = <_InfoBlock>[
      customer,
      order,
      ?delivery,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720 && blocks.length > 1;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < blocks.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 18),
                  const Divider(height: 1, color: AppColors.outlinePanel),
                  const SizedBox(height: 18),
                ],
                _InfoBlockView(block: blocks[i]),
              ],
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < blocks.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(width: 20),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: AppColors.outlinePanel,
                  ),
                  const SizedBox(width: 20),
                ],
                Expanded(child: _InfoBlockView(block: blocks[i])),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _InfoBlockView extends StatelessWidget {
  const _InfoBlockView({required this.block});

  final _InfoBlock block;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(block.title.toUpperCase(), style: _Type.section),
        const SizedBox(height: 12),
        for (var i = 0; i < block.fields.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _CompactField(field: block.fields[i]),
        ],
        if (block.trailing != null) ...[
          const SizedBox(height: 12),
          block.trailing!,
        ],
      ],
    );
  }
}

class _CompactField extends StatelessWidget {
  const _CompactField({required this.field});

  final _InfoField field;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.label, style: _Type.label),
        const SizedBox(height: 3),
        Text(
          field.value,
          style: _Type.value.copyWith(
            color: field.muted ? AppColors.textFaint : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _AccountExtras extends StatelessWidget {
  const _AccountExtras({
    required this.currencySymbol,
    this.wallet,
    this.creditAllowed,
    this.creditLimit,
  });

  final String currencySymbol;
  final num? wallet;
  final bool? creditAllowed;
  final num? creditLimit;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        visualDensity: VisualDensity.compact,
        title: Text(
          'Customer account',
          style: _Type.label.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Wallet and credit details',
          style: _Type.meta,
        ),
        children: [
          if (wallet != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CompactField(
                field: _InfoField(
                  label: 'Wallet',
                  value: SelloFormatters.currency(
                    wallet!,
                    symbol: currencySymbol,
                  ),
                ),
              ),
            ),
          if (creditAllowed != null)
            _CompactField(
              field: _InfoField(
                label: 'Credit',
                value: creditAllowed == true
                    ? SelloFormatters.currency(
                        creditLimit ?? 0,
                        symbol: currencySymbol,
                      )
                    : 'Not allowed',
                muted: creditAllowed != true,
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductsTable extends StatelessWidget {
  const _ProductsTable({
    required this.lines,
    required this.currencySymbol,
    required this.catalogFields,
    required this.showDelivery,
  });

  final List<OrderLineItem> lines;
  final String currencySymbol;
  final List<CompanyProductField> catalogFields;
  final bool showDelivery;

  static const double _qtyW = 64;
  static const double _priceW = 100;
  static const double _amountW = 108;
  static const double _indexW = 28;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTable = constraints.maxWidth >= 560;
        if (!useTable) {
          return Column(
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, color: AppColors.outlinePanel),
                  ),
                _ProductMobileRow(
                  index: i + 1,
                  line: lines[i],
                  currencySymbol: currencySymbol,
                  catalogFields: catalogFields,
                  showDelivery: showDelivery,
                ),
              ],
            ],
          );
        }

        return Column(
          children: [
            const _ProductHeaderRow(
              indexW: _indexW,
              qtyW: _qtyW,
              priceW: _priceW,
              amountW: _amountW,
            ),
            const Divider(height: 1, color: AppColors.outlinePanel),
            for (var i = 0; i < lines.length; i++) ...[
              _ProductDataRow(
                index: i + 1,
                line: lines[i],
                currencySymbol: currencySymbol,
                catalogFields: catalogFields,
                showDelivery: showDelivery,
                indexW: _indexW,
                qtyW: _qtyW,
                priceW: _priceW,
                amountW: _amountW,
              ),
              if (i < lines.length - 1)
                const Divider(height: 1, color: AppColors.outlinePanel),
            ],
          ],
        );
      },
    );
  }
}

class _ProductHeaderRow extends StatelessWidget {
  const _ProductHeaderRow({
    required this.indexW,
    required this.qtyW,
    required this.priceW,
    required this.amountW,
  });

  final double indexW;
  final double qtyW;
  final double priceW;
  final double amountW;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: indexW,
            child: Text('#', style: _Type.tableHead),
          ),
          Expanded(child: Text('Product', style: _Type.tableHead)),
          SizedBox(
            width: qtyW,
            child: Text('Qty', textAlign: TextAlign.right, style: _Type.tableHead),
          ),
          SizedBox(
            width: priceW,
            child: Text(
              'Unit price',
              textAlign: TextAlign.right,
              style: _Type.tableHead,
            ),
          ),
          SizedBox(
            width: amountW,
            child: Text(
              'Amount',
              textAlign: TextAlign.right,
              style: _Type.tableHead,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductDataRow extends StatelessWidget {
  const _ProductDataRow({
    required this.index,
    required this.line,
    required this.currencySymbol,
    required this.catalogFields,
    required this.showDelivery,
    required this.indexW,
    required this.qtyW,
    required this.priceW,
    required this.amountW,
  });

  final int index;
  final OrderLineItem line;
  final String currencySymbol;
  final List<CompanyProductField> catalogFields;
  final bool showDelivery;
  final double indexW;
  final double qtyW;
  final double priceW;
  final double amountW;

  @override
  Widget build(BuildContext context) {
    final specs = _productSpecs(line, catalogFields);
    final delivery = showDelivery ? _deliveryLine(line) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: indexW,
            child: Text('$index', style: _Type.meta),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.productName ?? 'Product',
                  style: _Type.productName,
                ),
                if (specs != null) ...[
                  const SizedBox(height: 2),
                  Text(specs, style: _Type.meta),
                ],
                if (delivery != null) ...[
                  const SizedBox(height: 2),
                  Text(delivery, style: _Type.meta),
                ],
              ],
            ),
          ),
          SizedBox(
            width: qtyW,
            child: Text(
              SelloFormatters.quantity(line.quantity),
              textAlign: TextAlign.right,
              style: _Type.tableCell,
            ),
          ),
          SizedBox(
            width: priceW,
            child: Text(
              SelloFormatters.currency(line.unitPrice, symbol: currencySymbol),
              textAlign: TextAlign.right,
              style: _Type.tableCell,
            ),
          ),
          SizedBox(
            width: amountW,
            child: Text(
              SelloFormatters.currency(line.lineTotal, symbol: currencySymbol),
              textAlign: TextAlign.right,
              style: _Type.amount,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductMobileRow extends StatelessWidget {
  const _ProductMobileRow({
    required this.index,
    required this.line,
    required this.currencySymbol,
    required this.catalogFields,
    required this.showDelivery,
  });

  final int index;
  final OrderLineItem line;
  final String currencySymbol;
  final List<CompanyProductField> catalogFields;
  final bool showDelivery;

  @override
  Widget build(BuildContext context) {
    final specs = _productSpecs(line, catalogFields);
    final delivery = showDelivery ? _deliveryLine(line) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$index.', style: _Type.meta),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                line.productName ?? 'Product',
                style: _Type.productName,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              SelloFormatters.currency(line.lineTotal, symbol: currencySymbol),
              style: _Type.amount,
            ),
          ],
        ),
        if (specs != null) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(specs, style: _Type.meta),
          ),
        ],
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 18),
          child: Text(
            '${SelloFormatters.quantity(line.quantity)} × '
            '${SelloFormatters.currency(line.unitPrice, symbol: currencySymbol)}',
            style: _Type.tableCell,
          ),
        ),
        if (delivery != null) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(delivery, style: _Type.meta),
          ),
        ],
      ],
    );
  }
}

String? _productSpecs(
  OrderLineItem line,
  List<CompanyProductField> catalogFields,
) {
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

String _deliveryLine(OrderLineItem line) {
  return '${SelloFormatters.quantity(line.deliveredQuantity)} delivered · '
      '${SelloFormatters.quantity(line.remainingQuantity)} remaining'
      '${line.cancelledQuantity > 0 ? ' · ${SelloFormatters.quantity(line.cancelledQuantity)} cancelled' : ''}';
}

class _TotalsBlock extends StatelessWidget {
  const _TotalsBlock({
    required this.currencySymbol,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
  });

  final String currencySymbol;
  final num subtotal;
  final num discount;
  final num tax;
  final num total;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TotalLine(
              label: 'Subtotal',
              value: SelloFormatters.currency(
                subtotal,
                symbol: currencySymbol,
              ),
            ),
            const SizedBox(height: 8),
            _TotalLine(
              label: 'Discount',
              value: SelloFormatters.currency(
                discount,
                symbol: currencySymbol,
              ),
            ),
            const SizedBox(height: 8),
            _TotalLine(
              label: 'Tax',
              value: tax > 0
                  ? SelloFormatters.currency(tax, symbol: currencySymbol)
                  : '—',
              muted: tax <= 0,
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppColors.outlinePanel),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: _TotalLine(
                label: 'Grand total',
                value: SelloFormatters.currency(
                  total,
                  symbol: currencySymbol,
                ),
                emphasize: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: emphasize
                ? _Type.productName
                : _Type.label.copyWith(fontSize: 13.5),
          ),
        ),
        Text(
          value,
          style: emphasize
              ? _Type.amount.copyWith(fontSize: 16)
              : _Type.tableCell.copyWith(
                  color: muted ? AppColors.textFaint : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
        ),
      ],
    );
  }
}

class _CompactTimeline extends StatelessWidget {
  const _CompactTimeline({required this.events});

  final List<OrderTimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < events.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.brandViolet,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(events[i].title, style: _Type.productName),
                    const SizedBox(height: 2),
                    Text(
                      SelloFormatters.dateTime(events[i].at),
                      style: _Type.meta,
                    ),
                    if (events[i].detail != null &&
                        events[i].detail!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        events[i].detail!,
                        style: _Type.body,
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
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

abstract final class _Type {
  static const TextStyle title = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.15,
    color: AppColors.textPrimary,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.35,
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
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.textTertiary,
  );

  static const TextStyle value = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 14.5,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static const TextStyle productName = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 14.5,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static const TextStyle tableHead = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.textTertiary,
  );

  static const TextStyle tableCell = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static const TextStyle amount = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 14.5,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.15,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static const TextStyle meta = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.35,
    color: AppColors.textFaint,
  );

  static const TextStyle body = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    height: 1.45,
    color: AppColors.textSecondary,
  );
}
