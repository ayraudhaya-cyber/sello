import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/responsive/responsive.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/documents/presentation/order_document_print.dart';
import 'package:sello/shared/models/document_issuer_identity.dart';
import 'package:sello/shared/models/order_document.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Public, token-gated document view. No workspace chrome.
///
/// Layout follows Cashro's public invoice: issuer + kind/number, Bill To,
/// line table, totals, thanks — using Sello colour, type, and cards.
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
            child: const Padding(
              padding: EdgeInsets.all(24),
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
    final compact = context.isMobile;

    return Theme(
      data: AppTheme.themed(doc.branding),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            if (!compact) _PrintToolbar(doc: doc),
            Expanded(
              child: SafeArea(
                top: compact,
                bottom: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 18 : 28,
                        compact ? 18 : 22,
                        compact ? 18 : 28,
                        compact ? 28 : 40,
                      ),
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: _DocumentIssuerHeader(
                                identity: doc.issuerIdentity,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Flexible(child: _KindHeader(doc: doc)),
                          ],
                        ),
                        if (doc.issuerIdentity.hasContactBlock) ...[
                          const SizedBox(height: 14),
                          _ContactStrip(identity: doc.issuerIdentity),
                        ],
                        const SizedBox(height: 16),
                        _BillToCard(doc: doc),
                        const SizedBox(height: 14),
                        if (doc.purpose.isPaymentDocument)
                          _PaymentBillCard(doc: doc)
                        else
                          _OrderBillCard(doc: doc, compact: compact),
                        const SizedBox(height: 16),
                        const _ThanksBanner(),
                        if (doc.issuerIdentity.hasTerms) ...[
                          const SizedBox(height: 22),
                          _DocumentTermsFooter(
                            terms: doc.issuerIdentity.terms!,
                          ),
                        ],
                        if (doc.issuerIdentity.hasTagline) ...[
                          const SizedBox(height: 16),
                          Text(
                            doc.issuerIdentity.tagline!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.45,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (compact) _PrintToolbar(doc: doc, docked: true),
          ],
        ),
      ),
    );
  }
}

class _PrintToolbar extends StatelessWidget {
  const _PrintToolbar({required this.doc, this.docked = false});

  final OrderDocument doc;
  final bool docked;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      child: SafeArea(
        top: !docked,
        bottom: docked,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            18,
            docked ? 10 : 10,
            18,
            docked ? 10 : 10,
          ),
          decoration: BoxDecoration(
            border: Border(
              top: docked
                  ? const BorderSide(color: AppColors.outlinePanel)
                  : BorderSide.none,
              bottom: docked
                  ? BorderSide.none
                  : const BorderSide(color: AppColors.outlinePanel),
            ),
          ),
          child: Align(
            alignment: docked ? Alignment.center : Alignment.centerRight,
            child: SelloButton(
              label: 'Print / Save PDF',
              variant: SelloButtonVariant.secondary,
              icon: Icons.print_outlined,
              onPressed: () => printOrderDocument(doc),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentIssuerHeader extends StatelessWidget {
  const _DocumentIssuerHeader({required this.identity});

  final DocumentIssuerIdentity identity;

  static const _nameStyle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (identity.showLogo && identity.logoUrl != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180, maxHeight: 56),
            child: Image.network(
              identity.logoUrl!,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, error, stackTrace) =>
                  Text(identity.businessName, style: _nameStyle),
            ),
          )
        else if (identity.showBusinessName)
          Text(identity.businessName, style: _nameStyle),
        if (identity.showLogo &&
            identity.logoUrl != null &&
            identity.showBusinessName) ...[
          const SizedBox(height: 8),
          Text(identity.businessName, style: _nameStyle.copyWith(fontSize: 16)),
        ],
      ],
    );
  }
}

class _KindHeader extends StatelessWidget {
  const _KindHeader({required this.doc});

  final OrderDocument doc;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            doc.kindLabel.toUpperCase(),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              height: 1.15,
              color: AppColors.primary,
            ),
          ),
          if (doc.kindNumber.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              doc.kindNumber,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w500,
                height: 1.15,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactStrip extends StatelessWidget {
  const _ContactStrip({required this.identity});

  final DocumentIssuerIdentity identity;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (identity.address != null) identity.address!,
      if (identity.phone != null) identity.phone!,
      if (identity.email != null) identity.email!,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    final compact = context.isMobile;
    const style = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 12,
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: AppColors.textSecondary,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: compact
          ? Column(
              children: [
                for (var i = 0; i < parts.length; i++)
                  Text(parts[i], textAlign: TextAlign.center, style: style),
              ],
            )
          : Text.rich(
              TextSpan(
                style: style,
                children: [
                  for (var i = 0; i < parts.length; i++) ...[
                    if (i > 0)
                      const TextSpan(
                        text: '  |  ',
                        style: TextStyle(color: AppColors.textFaint),
                      ),
                    TextSpan(text: parts[i]),
                  ],
                ],
              ),
              textAlign: TextAlign.center,
            ),
    );
  }
}

class _BillToCard extends StatelessWidget {
  const _BillToCard({required this.doc});

  final OrderDocument doc;

  @override
  Widget build(BuildContext context) {
    final compact = context.isMobile;
    final date = SelloFormatters.date(doc.completedAt ?? doc.orderedAt);

    final party = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'BILL TO',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          doc.customerName,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.25,
            color: AppColors.textPrimary,
          ),
        ),
        if (doc.customerPhone != null) _PartyLine(doc.customerPhone!),
        if (doc.customerAddress != null) _PartyLine(doc.customerAddress!),
        if (doc.salesRepName != null)
          _PartyLine('Sales Rep: ${doc.salesRepName}'),
      ],
    );

    final meta = Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        const Text(
          'DATE',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          date,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (doc.collectionStatusTag != null) ...[
          const SizedBox(height: 10),
          SelloStatusBadge(
            label: doc.collectionStatusTag!,
            tone: doc.collectionReview.showsPaymentDetails
                ? SelloStatusTone.success
                : SelloStatusTone.warning,
          ),
        ],
      ],
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        boxShadow: AppShadows.panel,
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [party, const SizedBox(height: 16), meta],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: party),
                const SizedBox(width: 24),
                Expanded(flex: 4, child: meta),
              ],
            ),
    );
  }
}

class _PartyLine extends StatelessWidget {
  const _PartyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13,
          height: 1.35,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _OrderBillCard extends StatelessWidget {
  const _OrderBillCard({required this.doc, required this.compact});

  final OrderDocument doc;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _BillSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (compact) _MobileLines(doc: doc) else _DesktopLineTable(doc: doc),
          const Divider(height: 1, color: AppColors.outlinePanel),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              children: [
                _TotalRow(label: 'Subtotal', value: doc.money(doc.subtotal)),
                if (doc.discountAmount > 0)
                  _TotalRow(
                    label: 'Discount',
                    value: '- ${doc.money(doc.discountAmount)}',
                  ),
                if (doc.taxAmount > 0)
                  _TotalRow(label: 'Tax', value: doc.money(doc.taxAmount)),
                const SizedBox(height: 8),
                _GrandTotal(label: 'Total', value: doc.money(doc.total)),
              ],
            ),
          ),
          if (_hasPaymentMeta(doc)) ...[
            const Divider(height: 1, color: AppColors.outlinePanel),
            _PaymentDetails(doc: doc),
          ],
          if (doc.notes != null) _Notes(doc.notes!),
        ],
      ),
    );
  }
}

class _PaymentBillCard extends StatelessWidget {
  const _PaymentBillCard({required this.doc});

  final OrderDocument doc;

  @override
  Widget build(BuildContext context) {
    final isPending = doc.isCollectionAcknowledgement && doc.pendingReview;
    final method = doc.paymentMethod?.replaceAll('_', ' ');

    return _BillSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isPending) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warningContainer,
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
              const SizedBox(height: 16),
            ],
            if (method != null && method.isNotEmpty)
              _MetaLine(label: 'Method', value: method),
            if (doc.reference != null)
              _MetaLine(label: 'Reference', value: doc.reference!),
            _MetaLine(
              label: 'Status',
              value: isPending
                  ? 'Pending Review'
                  : (doc.paymentStatus ?? 'Recorded'),
            ),
            const SizedBox(height: 12),
            _GrandTotal(
              label: isPending ? 'Amount submitted' : 'Amount',
              value: doc.money(doc.total),
            ),
            if (doc.notes != null) _Notes(doc.notes!),
          ],
        ),
      ),
    );
  }
}

class _BillSurface extends StatelessWidget {
  const _BillSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        boxShadow: AppShadows.panel,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _DesktopLineTable extends StatelessWidget {
  const _DesktopLineTable({required this.doc});

  final OrderDocument doc;

  static const _headStyle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    color: AppColors.textTertiary,
  );

  static const _cellStyle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 13.5,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(36),
          1: FlexColumnWidth(4),
          2: FlexColumnWidth(1.1),
          3: FlexColumnWidth(1.6),
          4: FlexColumnWidth(1.6),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          const TableRow(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('#', style: _headStyle),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Description', style: _headStyle),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Qty',
                  textAlign: TextAlign.right,
                  style: _headStyle,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Rate',
                  textAlign: TextAlign.right,
                  style: _headStyle,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Amount',
                  textAlign: TextAlign.right,
                  style: _headStyle,
                ),
              ),
            ],
          ),
          for (var i = 0; i < doc.lines.length; i++)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    '${i + 1}',
                    style: _cellStyle.copyWith(color: AppColors.textTertiary),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 9,
                    horizontal: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.lines[i].displayTitle,
                        style: _cellStyle.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (doc.lines[i].sku?.trim().isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            doc.lines[i].sku!.trim(),
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 11.5,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    SelloFormatters.quantity(doc.lines[i].quantity),
                    textAlign: TextAlign.right,
                    style: _cellStyle,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    doc.money(doc.lines[i].unitPrice),
                    textAlign: TextAlign.right,
                    style: _cellStyle,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    doc.money(doc.lines[i].lineTotal),
                    textAlign: TextAlign.right,
                    style: _cellStyle.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MobileLines extends StatelessWidget {
  const _MobileLines({required this.doc});

  final OrderDocument doc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          for (var i = 0; i < doc.lines.length; i++) ...[
            if (i > 0)
              const Divider(height: 18, color: AppColors.outlineSubtle),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.lines[i].displayTitle,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${SelloFormatters.quantity(doc.lines[i].quantity)} × ${doc.money(doc.lines[i].unitPrice)}',
                              style: const TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 12.5,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                          Text(
                            doc.money(doc.lines[i].lineTotal),
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GrandTotal extends StatelessWidget {
  const _GrandTotal({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentDetails extends StatelessWidget {
  const _PaymentDetails({required this.doc});

  final OrderDocument doc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Payment details',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          if (doc.collectionPaymentNumber != null)
            _MetaLine(label: 'Payment', value: doc.collectionPaymentNumber!),
          if (doc.collectionMethodLabel != null)
            _MetaLine(label: 'Method', value: doc.collectionMethodLabel!),
          if (doc.collectionPaymentAmount != null)
            _MetaLine(
              label: 'Amount received',
              value: doc.money(doc.collectionPaymentAmount!),
            ),
          if (doc.collectionReceivedAt != null)
            _MetaLine(
              label: 'Recorded on',
              value: SelloFormatters.date(doc.collectionReceivedAt!),
            ),
          if (doc.outstandingBalance != null)
            _MetaLine(
              label: 'Outstanding balance',
              value: doc.money(doc.outstandingBalance!),
              warning: doc.outstandingBalance! > 0,
            ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? AppColors.warning : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: warning ? AppColors.warning : AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Notes extends StatelessWidget {
  const _Notes(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13,
          height: 1.4,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _ThanksBanner extends StatelessWidget {
  const _ThanksBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primaryContainer,
            child: Icon(
              Icons.favorite_rounded,
              size: 16,
              color: AppColors.attention,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Thank you for your business!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: AppColors.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentTermsFooter extends StatelessWidget {
  const _DocumentTermsFooter({required this.terms});

  final String terms;

  @override
  Widget build(BuildContext context) {
    return Text(
      terms,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: AppTypography.fontFamily,
        fontSize: 12.5,
        height: 1.45,
        color: AppColors.textSecondary,
      ),
    );
  }
}

bool _hasPaymentMeta(OrderDocument doc) {
  return doc.collectionReview.showsPaymentDetails ||
      doc.outstandingBalance != null;
}
