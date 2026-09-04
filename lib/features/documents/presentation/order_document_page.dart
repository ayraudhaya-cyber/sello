import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/documents/presentation/order_document_print.dart';
import 'package:sello/shared/models/document_issuer_identity.dart';
import 'package:sello/shared/models/order_document.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Public, token-gated document view. No workspace chrome.
class OrderDocumentPage extends ConsumerStatefulWidget {
  const OrderDocumentPage({super.key, required this.token});

  final String token;

  @override
  ConsumerState<OrderDocumentPage> createState() => _OrderDocumentPageState();
}

class _OrderDocumentPageState extends ConsumerState<OrderDocumentPage> {
  OrderDocument? _document;
  var _loading = true;
  var _missing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final doc = await ref
        .read(orderDocumentRepositoryProvider)
        .fetchByToken(widget.token);
    if (!mounted) return;
    setState(() {
      _document = doc;
      _missing = doc == null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_missing || _document == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelloEmptyState(
                icon: Icons.link_off_rounded,
                title: 'Document not available',
                message:
                    'This link is invalid, expired, or is not shared with you.',
              ),
            ),
          ),
        ),
      );
    }

    final doc = _document!;
    final branding = doc.branding;

    return Theme(
      data: AppTheme.themed(branding),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                children: [
                  _DocumentIssuerHeader(identity: doc.issuerIdentity),
                  const SizedBox(height: 22),
                  if (doc.purpose.isPaymentDocument)
                    _PaymentDocumentCard(doc: doc)
                  else
                    _OrderDocumentCard(doc: doc),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelloButton(
                      label: 'Print',
                      variant: SelloButtonVariant.secondary,
                      icon: Icons.print_outlined,
                      onPressed: printOrderDocument,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tenant issuer mark — logo and/or business name. Never the Sello logo.
class _DocumentIssuerHeader extends StatelessWidget {
  const _DocumentIssuerHeader({required this.identity});

  final DocumentIssuerIdentity identity;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (identity.showLogo && identity.logoUrl != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220, maxHeight: 48),
              child: Image.network(
                identity.logoUrl!,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, error, stackTrace) => Text(
                  identity.businessName,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          if (identity.showBusinessName) const SizedBox(height: 14),
        ],
        if (identity.showBusinessName)
          Text(
            identity.businessName,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: AppColors.textPrimary,
            ),
          ),
      ],
    );
  }
}

class _PaymentDocumentCard extends StatelessWidget {
  const _PaymentDocumentCard({required this.doc});

  final OrderDocument doc;

  @override
  Widget build(BuildContext context) {
    final isPending = doc.isCollectionAcknowledgement && doc.pendingReview;
    final method = doc.paymentMethod?.replaceAll('_', ' ');

    return SelloCard(
      enableHoverLift: false,
      elevation: SelloCardElevation.soft,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      borderRadius: AppRadius.panelAll,
      borderColor: AppColors.outlinePanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            doc.documentTitle,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            SelloFormatters.date(doc.orderedAt),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
          if (isPending) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.28),
                ),
              ),
              child: const Text(
                'Pending Review — this collection was submitted and is waiting '
                'for owner/manager approval. Outstanding balances are not '
                'updated until it is approved.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Divider(height: 1, color: AppColors.outlinePanel),
          const SizedBox(height: 16),
          _MetaRow(label: 'Customer', value: doc.customerName),
          if (doc.customerPhone != null)
            _MetaRow(label: 'Phone', value: doc.customerPhone!),
          if (doc.salesRepName != null)
            _MetaRow(label: 'Sales representative', value: doc.salesRepName!),
          if (method != null && method.isNotEmpty)
            _MetaRow(label: 'Method', value: method),
          if (doc.reference != null)
            _MetaRow(label: 'Reference', value: doc.reference!),
          _MetaRow(
            label: 'Status',
            value: isPending
                ? 'Pending Review'
                : (doc.paymentStatus ?? 'Recorded'),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.outlinePanel),
          const SizedBox(height: 12),
          _TotalRow(
            label: isPending ? 'Amount submitted' : 'Amount',
            value: doc.money(doc.total),
            emphasize: true,
          ),
          if (doc.notes != null) ...[
            const SizedBox(height: 16),
            Text(
              doc.notes!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderDocumentCard extends StatelessWidget {
  const _OrderDocumentCard({required this.doc});

  final OrderDocument doc;

  @override
  Widget build(BuildContext context) {
    return SelloCard(
      enableHoverLift: false,
      elevation: SelloCardElevation.soft,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      borderRadius: AppRadius.panelAll,
      borderColor: AppColors.outlinePanel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            doc.documentTitle,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            SelloFormatters.date(doc.completedAt ?? doc.orderedAt),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: AppColors.outlinePanel),
          const SizedBox(height: 16),
          _MetaRow(label: 'Customer', value: doc.customerName),
          if (doc.customerPhone != null)
            _MetaRow(label: 'Phone', value: doc.customerPhone!),
          if (doc.customerAddress != null)
            _MetaRow(label: 'Address', value: doc.customerAddress!),
          if (doc.salesRepName != null)
            _MetaRow(label: 'Sales representative', value: doc.salesRepName!),
          if (doc.outstandingBalance != null)
            _MetaRow(
              label: 'Outstanding balance',
              value: doc.money(doc.outstandingBalance!),
            ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.outlinePanel),
          const SizedBox(height: 14),
          const Text(
            'Items',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          for (final line in doc.lines) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.name,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${SelloFormatters.quantity(line.quantity)} × ${doc.money(line.unitPrice)}',
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 12.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  doc.money(line.lineTotal),
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          const Divider(height: 1, color: AppColors.outlinePanel),
          const SizedBox(height: 12),
          _TotalRow(label: 'Subtotal', value: doc.money(doc.subtotal)),
          if (doc.discountAmount > 0)
            _TotalRow(
              label: 'Discount',
              value: '- ${doc.money(doc.discountAmount)}',
            ),
          if (doc.taxAmount > 0)
            _TotalRow(label: 'Tax', value: doc.money(doc.taxAmount)),
          const SizedBox(height: 8),
          _TotalRow(
            label: 'Total',
            value: doc.money(doc.total),
            emphasize: true,
          ),
          if (doc.notes != null) ...[
            const SizedBox(height: 16),
            Text(
              doc.notes!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: emphasize ? 15 : 13.5,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                color: emphasize
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: emphasize ? 16 : 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
