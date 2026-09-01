import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/products/application/product_fields_provider.dart';
import 'package:sello/shared/models/product_field.dart';
import 'package:sello/shared/models/product_image.dart';
import 'package:sello/shared/models/product_summary.dart';
import 'package:sello/shared/utils/country_catalog.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/badges/sello_badge.dart';
import 'package:sello/shared/widgets/buttons/sello_button.dart';
import 'package:sello/shared/widgets/dialogs/sello_form_dialog.dart';
import 'package:sello/shared/widgets/feedback/entity_activity_panel.dart';
import 'package:sello/shared/widgets/media/sello_image_lightbox.dart';
import 'package:sello/shared/widgets/media/sello_product_media_gallery.dart';
import 'package:sello/shared/widgets/products/product_dynamic_fields.dart';

/// Premium product profile dialog — showcase, not a CRUD form.
class ProductDetailsDialog extends ConsumerStatefulWidget {
  const ProductDetailsDialog({
    super.key,
    required this.product,
    required this.onEdit,
    required this.onToggleArchive,
    this.onDeletePermanently,
    this.currencySymbol = '\$',
  });

  final ProductSummary product;
  final VoidCallback onEdit;
  final VoidCallback onToggleArchive;
  final VoidCallback? onDeletePermanently;
  final String currencySymbol;

  @override
  ConsumerState<ProductDetailsDialog> createState() =>
      _ProductDetailsDialogState();
}

class _ProductDetailsDialogState extends ConsumerState<ProductDetailsDialog> {
  /// Hierarchy comes from spacing + dividers, not competing type sizes.
  static const double _sectionGap = 36;

  List<MediaGalleryDraft> _gallery = [];
  bool _galleryLoading = true;

  ProductSummary get product => widget.product;

  String get _unitLabel {
    final unit = product.unitLabel?.trim();
    if (unit == null || unit.isEmpty) return 'units';
    return unit;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadGallery);
  }

  Future<void> _loadGallery() async {
    try {
      final images = await ref
          .read(productRepositoryProvider)
          .media
          .fetchForProduct(product.id);
      if (!mounted) return;
      setState(() {
        _gallery = [
          for (final image in images) MediaGalleryDraft.fromProductImage(image),
        ];
        if (_gallery.isEmpty &&
            product.imageStoragePath != null &&
            product.imageStoragePath!.isNotEmpty) {
          _gallery = [
            MediaGalleryDraft(
              clientId: 'legacy_primary',
              networkUrl: product.imageUrl,
              storagePath: product.imageStoragePath,
              isPrimary: true,
              sortOrder: 0,
            ),
          ];
        }
        _galleryLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (product.imageUrl != null || product.imageStoragePath != null) {
          _gallery = [
            MediaGalleryDraft(
              clientId: 'legacy_primary',
              networkUrl: product.imageUrl,
              storagePath: product.imageStoragePath,
              isPrimary: true,
              sortOrder: 0,
            ),
          ];
        }
        _galleryLoading = false;
      });
    }
  }

  void _openLightbox(int index) {
    showSelloImageLightbox(
      context,
      images: _gallery,
      initialIndex: index,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;

    return SelloFormDialog(
      header: _ProductHero(product: product),
      maxWidth: kSelloDetailDialogWidth,
      fullscreenOnMobile: true,
      bodyPadding: EdgeInsets.fromLTRB(
        isMobile ? 20 : 36,
        isMobile ? 16 : 20,
        isMobile ? 20 : 36,
        16,
      ),
      body: isMobile ? _buildMobileBody() : _buildDesktopBody(),
      footer: SelloDialogFooter(
        cancelLabel: product.isActive ? 'Archive' : 'Restore',
        cancelVariant: SelloButtonVariant.ghost,
        onCancel: widget.onToggleArchive,
        primaryLabel: 'Edit Product',
        onPrimary: widget.onEdit,
        destructiveLabel:
            product.isActive ? null : 'Delete permanently',
        onDestructive: product.isActive ? null : widget.onDeletePermanently,
      ),
    );
  }

  Widget _buildGallery() {
    if (_galleryLoading) {
      return Container(
        height: 360,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return SelloProductMediaGallery(
      items: _gallery,
      readOnly: true,
      showcase: true,
      onChanged: (_) {},
      onPreviewTap: _gallery.isEmpty ? null : _openLightbox,
    );
  }

  Widget _buildDesktopBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 340, child: _buildGallery()),
        const SizedBox(width: 48),
        Expanded(child: _buildProfileContent()),
      ],
    );
  }

  Widget _buildMobileBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGallery(),
        const SizedBox(height: _sectionGap),
        _buildProfileContent(),
      ],
    );
  }

  Widget _buildProfileContent() {
    final dash = '—';
    final fieldConfigAsync = ref.watch(productFieldConfigProvider);
    final fieldConfig = fieldConfigAsync.valueOrNull ??
        ProductFieldConfig(fields: []);
    final configReady = fieldConfigAsync.hasValue;
    final showBarcode = !configReady || fieldConfig.isEnabled('barcode');
    final showBrand = !configReady || fieldConfig.isEnabled('brand');
    final showReorder =
        !configReady || fieldConfig.isEnabled('reorder_level');
    // Description is a standard product field — not gated by Product Details config.
    final hasDescription =
        product.description != null && product.description!.trim().isNotEmpty;

    final catalogSpecs = fieldConfig.forCatalog
        .where((f) => f.definition.storage == ProductFieldStorage.attribute)
        .toList(growable: false);
    final listOnlySpecs = fieldConfig.forList
        .where(
          (f) =>
              f.definition.storage == ProductFieldStorage.attribute &&
              !f.showInCatalog,
        )
        .toList(growable: false);
    final specFields = <CompanyProductField>[
      ...catalogSpecs,
      ...listOnlySpecs,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final filledSpecs = <(CompanyProductField, String)>[];
    for (final field in specFields) {
      final raw = productFieldRawValue(product, field.fieldKey);
      if (raw == null || raw.trim().isEmpty) continue;
      final display = field.definition.fieldType == ProductFieldType.country
          ? CountryCatalog.display(raw)
          : raw.trim();
      filledSpecs.add((field, display));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!product.isActive) ...[
          const _ArchivedNotice(),
          const SizedBox(height: _sectionGap),
        ],
        _ProfileSection(
          label: 'Pricing',
          child: SelloFormRow(
            left: _ProfileField(
              label: 'Selling price',
              value: SelloFormatters.currency(
                product.sellingPrice,
                symbol: widget.currencySymbol,
              ),
            ),
            right: _ProfileField(
              label: 'Cost price',
              value: SelloFormatters.currency(
                product.costPrice,
                symbol: widget.currencySymbol,
              ),
            ),
          ),
        ),
        const SizedBox(height: _sectionGap),
        _ProfileSection(
          label: 'Sourcing',
          child: _ProfileField(
            label: 'Preferred supplier',
            value: product.preferredSupplierName ?? dash,
            mutedEmpty: product.preferredSupplierName == null,
          ),
        ),
        const SizedBox(height: _sectionGap),
        _ProfileSection(
          label: 'Inventory',
          child: showReorder
              ? SelloFormRow(
                  left: _ProfileField(
                    label: 'Current stock',
                    value:
                        '${SelloFormatters.quantity(product.currentStockQuantity)} $_unitLabel',
                  ),
                  right: _ProfileField(
                    label: 'Reorder level',
                    value:
                        '${SelloFormatters.quantity(product.reorderLevel ?? 0)} $_unitLabel',
                  ),
                )
              : _ProfileField(
                  label: 'Current stock',
                  value:
                      '${SelloFormatters.quantity(product.currentStockQuantity)} $_unitLabel',
                ),
        ),
        if (filledSpecs.isNotEmpty || showBarcode || showBrand) ...[
          const SizedBox(height: _sectionGap),
          _ProfileSection(
            label: 'Product Details',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showBarcode || showBrand)
                  showBarcode && showBrand
                      ? SelloFormRow(
                          left: _ProfileField(
                            label: 'Barcode',
                            value: product.barcode?.trim().isNotEmpty == true
                                ? product.barcode!
                                : dash,
                            mutedEmpty:
                                product.barcode?.trim().isNotEmpty != true,
                          ),
                          right: _ProfileField(
                            label: 'Brand',
                            value: product.brand?.trim().isNotEmpty == true
                                ? product.brand!
                                : dash,
                            mutedEmpty:
                                product.brand?.trim().isNotEmpty != true,
                          ),
                        )
                      : showBarcode
                          ? _ProfileField(
                              label: 'Barcode',
                              value: product.barcode?.trim().isNotEmpty == true
                                  ? product.barcode!
                                  : dash,
                              mutedEmpty:
                                  product.barcode?.trim().isNotEmpty != true,
                            )
                          : _ProfileField(
                              label: 'Brand',
                              value: product.brand?.trim().isNotEmpty == true
                                  ? product.brand!
                                  : dash,
                              mutedEmpty:
                                  product.brand?.trim().isNotEmpty != true,
                            ),
                if ((showBarcode || showBrand) && filledSpecs.isNotEmpty)
                  const SizedBox(height: 16),
                if (filledSpecs.isNotEmpty)
                  _SpecGrid(entries: filledSpecs),
              ],
            ),
          ),
        ],
        if (hasDescription) ...[
          const SizedBox(height: _sectionGap),
          _ProfileSection(
            label: 'Additional Information',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'DESCRIPTION',
                  style: _ProductDetailType.label.copyWith(
                    fontSize: 11,
                    letterSpacing: 0.4,
                    color: AppColors.textFaint,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  product.description!,
                  style: _ProductDetailType.value.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: _sectionGap),
        _ProfileSection(
          label: 'Activity',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelloFormRow(
                left: _ProfileField(
                  label: 'Created',
                  value: product.createdAt != null
                      ? SelloFormatters.date(product.createdAt)
                      : dash,
                  mutedEmpty: product.createdAt == null,
                ),
                right: _ProfileField(
                  label: 'Updated',
                  value: SelloFormatters.date(product.updatedAt),
                ),
              ),
              const SizedBox(height: 16),
              EntityActivityPanel(
                referenceType: 'product',
                referenceId: product.id,
                emptyMessage: 'Product activity will appear here.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Closed typography set — five roles only.
abstract final class _ProductDetailType {
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

class _ProductHero extends StatelessWidget {
  const _ProductHero({required this.product});

  final ProductSummary product;

  @override
  Widget build(BuildContext context) {
    final metaParts = <String>[
      product.sku,
      product.categoryName ?? 'Uncategorized',
      if (product.unitLabel?.trim().isNotEmpty == true) product.unitLabel!.trim(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(product.name, style: _ProductDetailType.title),
        const SizedBox(height: 8),
        Text(metaParts.join(' · '), style: _ProductDetailType.subtitle),
        const SizedBox(height: 14),
        SelloStatusBadge(
          label: product.isActive ? 'Active' : 'Archived',
          tone: product.isActive
              ? SelloStatusTone.success
              : SelloStatusTone.neutral,
        ),
      ],
    );
  }
}

class _ArchivedNotice extends StatelessWidget {
  const _ArchivedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.infoContainer,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.info,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Archived products are hidden from sales but remain available '
              'for reports and history.',
              style: _ProductDetailType.label.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, thickness: 1, color: AppColors.outlinePanel),
        const SizedBox(height: 14),
        Text(label.toUpperCase(), style: _ProductDetailType.section),
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
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
        Text(label, style: _ProductDetailType.label),
        const SizedBox(height: 6),
        Text(
          value,
          style: mutedEmpty
              ? _ProductDetailType.value.copyWith(
                  color: AppColors.textFaint.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w500,
                )
              : _ProductDetailType.value,
        ),
      ],
    );
  }
}

class _SpecGrid extends StatelessWidget {
  const _SpecGrid({required this.entries});

  final List<(CompanyProductField, String)> entries;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i += 2) {
      final left = entries[i];
      final right = i + 1 < entries.length ? entries[i + 1] : null;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: right != null || i + 2 < entries.length ? 16 : 0),
          child: right == null
              ? _ProfileField(label: left.$1.label, value: left.$2)
              : SelloFormRow(
                  left: _ProfileField(label: left.$1.label, value: left.$2),
                  right: _ProfileField(label: right.$1.label, value: right.$2),
                ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
