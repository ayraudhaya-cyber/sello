import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/supplier_summary.dart';
import 'package:sello/shared/utils/country_catalog.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/utils/phone_number.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Hub supplier profile workspace.
///
/// Shows live products + inventory activity; PO / GRN / payments remain reserved.
class SupplierDetailsDialog extends StatelessWidget {
  const SupplierDetailsDialog({
    super.key,
    required this.detail,
    this.onEdit,
    this.onToggleArchive,
    this.onDeletePermanently,
    this.currencySymbol = '\$',
  });

  final SupplierDetail detail;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleArchive;
  final VoidCallback? onDeletePermanently;
  final String currencySymbol;

  SupplierSummary get supplier => detail.supplier;

  static const double _sectionGap = 28;

  @override
  Widget build(BuildContext context) {
    final dash = '—';

    return SelloFormDialog(
      title: supplier.name,
      subtitle: [
        if (supplier.code != null) supplier.code!,
        if (supplier.category != null) supplier.category!,
        if (supplier.contactName != null) supplier.contactName!,
      ].join(' · '),
      maxWidth: kSelloDetailDialogWidth,
      fullscreenOnMobile: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SelloStatusBadge(
                label: supplier.isActive ? 'Active' : 'Archived',
                tone: supplier.isActive
                    ? SelloStatusTone.success
                    : SelloStatusTone.neutral,
              ),
              if (supplier.category != null)
                SelloMetaPill(value: supplier.category!),
              if (detail.productCount > 0)
                SelloMetaPill(
                  value: detail.productCount == 1
                      ? '1 product'
                      : '${detail.productCount} products',
                ),
            ],
          ),
          if (!supplier.isActive) ...[
            const SizedBox(height: 16),
            const Text(
              'This supplier is archived. Historical purchase orders and '
              'payments will remain available when those modules ship.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: _sectionGap),
          _Section(
            title: 'Business information',
            child: Column(
              children: [
                SelloFormRow(
                  left: _Field(label: 'Supplier name', value: supplier.name),
                  right: _Field(
                    label: 'Code',
                    value: supplier.code ?? dash,
                    muted: supplier.code == null,
                  ),
                ),
                const SizedBox(height: 14),
                SelloFormRow(
                  left: _Field(
                    label: 'Category',
                    value: supplier.category ?? dash,
                    muted: supplier.category == null,
                  ),
                  right: _Field(
                    label: 'Tax / VAT number',
                    value: supplier.taxNumber ?? dash,
                    muted: supplier.taxNumber == null,
                  ),
                ),
                const SizedBox(height: 14),
                SelloFormRow(
                  left: _Field(
                    label: 'Lead time (days)',
                    value: supplier.leadTimeDays?.toString() ?? dash,
                    muted: supplier.leadTimeDays == null,
                  ),
                  right: _Field(
                    label: 'Last purchase',
                    value: SelloFormatters.date(supplier.lastPurchaseAt),
                    muted: supplier.lastPurchaseAt == null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),
          _Section(
            title: 'Contact information',
            child: Column(
              children: [
                SelloFormRow(
                  left: _Field(
                    label: 'Contact person',
                    value: supplier.contactName ?? dash,
                    muted: supplier.contactName == null,
                  ),
                  right: _Field(
                    label: 'Phone',
                    value: PhoneNumber.displayOrNull(supplier.phone) ?? dash,
                    muted: supplier.phone == null,
                  ),
                ),
                const SizedBox(height: 14),
                SelloFormRow(
                  left: _Field(
                    label: 'Mobile / WhatsApp',
                    value: PhoneNumber.displayOrNull(supplier.whatsapp) ?? dash,
                    muted: supplier.whatsapp == null,
                  ),
                  right: _Field(
                    label: 'Email',
                    value: supplier.email ?? dash,
                    muted: supplier.email == null,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Multiple contact persons will be supported in a later release.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),
          _Section(
            title: 'Address',
            child: Column(
              children: [
                _Field(
                  label: 'Address',
                  value: _addressLines(supplier) ?? dash,
                  muted: _addressLines(supplier) == null,
                ),
                const SizedBox(height: 14),
                SelloFormRow(
                  left: _Field(
                    label: 'City',
                    value: supplier.city ?? dash,
                    muted: supplier.city == null,
                  ),
                  right: _Field(
                    label: 'State / region',
                    value: supplier.state ?? dash,
                    muted: supplier.state == null,
                  ),
                ),
                const SizedBox(height: 14),
                SelloFormRow(
                  left: _Field(
                    label: 'Postal code',
                    value: supplier.postalCode ?? dash,
                    muted: supplier.postalCode == null,
                  ),
                  right: _Field(
                    label: 'Country',
                    value: supplier.country == null
                        ? dash
                        : CountryCatalog.display(supplier.country!),
                    muted: supplier.country == null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),
          _Section(
            title: 'Payment information',
            child: Column(
              children: [
                SelloFormRow(
                  left: _Field(
                    label: 'Outstanding balance',
                    value: SelloFormatters.currency(
                      supplier.outstandingBalance,
                      symbol: currencySymbol,
                    ),
                  ),
                  right: _Field(
                    label: 'Opening balance',
                    value: SelloFormatters.currency(
                      supplier.openingBalance,
                      symbol: currencySymbol,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SelloFormRow(
                  left: _Field(
                    label: 'Credit limit',
                    value: SelloFormatters.currency(
                      supplier.creditLimit,
                      symbol: currencySymbol,
                    ),
                  ),
                  right: _Field(
                    label: 'Payment terms',
                    value: supplier.paymentTerms ?? dash,
                    muted: supplier.paymentTerms == null,
                  ),
                ),
                const SizedBox(height: 14),
                SelloFormRow(
                  left: _Field(
                    label: 'Bank name',
                    value: supplier.bankName ?? dash,
                    muted: supplier.bankName == null,
                  ),
                  right: _Field(
                    label: 'Bank account',
                    value: supplier.bankAccount ?? dash,
                    muted: supplier.bankAccount == null,
                  ),
                ),
              ],
            ),
          ),
          if (supplier.notes != null && supplier.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: _sectionGap),
            _Section(
              title: 'Notes',
              child: Text(
                supplier.notes!,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: _sectionGap),
          _Section(
            title: 'Products supplied',
            child: detail.products.isEmpty
                ? const Text(
                    'No products list this supplier as preferred yet. '
                    'Set a preferred supplier on a product to link sourcing.',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < detail.products.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _ProductRow(
                          product: detail.products[i],
                          currencySymbol: currencySymbol,
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: _sectionGap),
          _Section(
            title: 'Purchase history',
            child: Text(
              supplier.lastPurchaseAt == null
                  ? 'No purchases recorded yet. Purchase Orders and GRNs will '
                      'appear here.'
                  : 'Last purchase ${SelloFormatters.date(supplier.lastPurchaseAt)}. '
                      'Full PO / invoice history arrives with purchasing.',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: _sectionGap),
          _Section(
            title: 'Inventory activity',
            child: detail.recentMovements.isEmpty
                ? const Text(
                    'No stock movements on linked products yet.',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  )
                : Column(
                    children: [
                      for (final movement
                          in detail.recentMovements.take(8)) ...[
                        _MovementRow(movement: movement),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: _sectionGap),
          _Section(
            title: 'Coming next',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                SelloMetaPill(value: 'Purchase Orders'),
                SelloMetaPill(value: 'Goods Received'),
                SelloMetaPill(value: 'Supplier payments'),
                SelloMetaPill(value: 'Credit & performance'),
              ],
            ),
          ),
          const SizedBox(height: _sectionGap),
          _Section(
            title: 'Company activity',
            child: EntityActivityPanel(
              referenceType: 'supplier',
              referenceId: supplier.id,
              emptyMessage: 'Supplier activity will appear here.',
            ),
          ),
          const SizedBox(height: _sectionGap),
          _Section(
            title: 'Timeline',
            child: detail.timeline.isEmpty
                ? const Text(
                    'No recorded activity yet.',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  )
                : _Timeline(events: detail.timeline),
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: supplier.isActive ? 'Archive' : 'Restore',
        cancelVariant: SelloButtonVariant.ghost,
        onCancel: onToggleArchive,
        primaryLabel: 'Edit supplier',
        onPrimary: onEdit,
        destructiveLabel: supplier.isActive ? null : 'Delete permanently',
        onDestructive: supplier.isActive ? null : onDeletePermanently,
      ),
    );
  }

  static String? _addressLines(SupplierSummary supplier) {
    final parts = <String>[
      if (supplier.addressLine1 != null) supplier.addressLine1!,
      if (supplier.addressLine2 != null) supplier.addressLine2!,
    ];
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.currencySymbol,
  });

  final SupplierProductLink product;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    product.sku,
                    if (product.categoryName != null) product.categoryName!,
                    product.isActive ? 'Active' : 'Archived',
                  ].join(' · '),
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Stock ${SelloFormatters.quantity(product.currentStockQuantity)}',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Cost ${SelloFormatters.currency(product.costPrice, symbol: currencySymbol)}',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement});

  final StockMovementRef movement;

  @override
  Widget build(BuildContext context) {
    final delta = movement.quantityDelta;
    final signed = delta > 0 ? '+$delta' : '$delta';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.inventory_2_outlined,
          size: 16,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                movement.displayTitle,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                [
                  signed,
                  if (movement.createdByName != null) movement.createdByName!,
                  SelloFormatters.date(movement.createdAt),
                ].join(' · '),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.events});

  final List<SupplierTimelineEvent> events;

  IconData _iconFor(SupplierTimelineKind kind) {
    return switch (kind) {
      SupplierTimelineKind.created => Icons.fiber_new_rounded,
      SupplierTimelineKind.updated => Icons.edit_outlined,
      SupplierTimelineKind.archived => Icons.archive_outlined,
      SupplierTimelineKind.restored => Icons.unarchive_outlined,
      SupplierTimelineKind.productLinked => Icons.link_rounded,
      SupplierTimelineKind.stockMovement => Icons.inventory_2_outlined,
      SupplierTimelineKind.purchase => Icons.local_shipping_outlined,
      SupplierTimelineKind.note => Icons.sticky_note_2_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final event in events.take(20)) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _iconFor(event.kind),
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (event.subtitle != null &&
                        event.subtitle!.trim().isNotEmpty)
                      Text(
                        event.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    Text(
                      SelloFormatters.date(event.at),
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;
  final bool muted;

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
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: muted ? AppColors.textSecondary : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
