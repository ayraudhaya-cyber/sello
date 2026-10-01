import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/reports/application/collections_report_excel.dart';
import 'package:sello/features/hub/reports/application/collections_report_pdf.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/collections_report.dart';
import 'package:sello/shared/models/employee_summary.dart';
import 'package:sello/shared/utils/browser_file_download.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Dedicated Collections Report preview — as-of AR by sales representative.
class CollectionsReportDialog extends ConsumerStatefulWidget {
  const CollectionsReportDialog({super.key});

  @override
  ConsumerState<CollectionsReportDialog> createState() =>
      _CollectionsReportDialogState();
}

class _CollectionsReportDialogState
    extends ConsumerState<CollectionsReportDialog> {
  DateTime _asOf = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  final Set<String> _selectedRepIds = {};
  List<EmployeeSummary> _reps = const [];
  CollectionsReportSnapshot? _snapshot;
  bool _loadingReps = true;
  bool _loadingReport = false;
  bool _exportingPdf = false;
  bool _exportingExcel = false;
  String? _error;

  String get _currencySymbol => SelloFormatters.currencySymbol(
        ref.read(companySettingsProvider).currency,
      );

  List<String> get _selectedNames => [
        for (final rep in _reps)
          if (_selectedRepIds.contains(rep.id)) rep.fullName,
      ];

  String get _salesRepsLabel => CollectionsReportMath.salesRepsLabel(
        selectedIds: _selectedRepIds.toList(),
        selectedNames: _selectedNames,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    await _loadReps();
    await _loadReport();
  }

  Future<void> _loadReps() async {
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      setState(() {
        _loadingReps = false;
        _error = 'Sign in required.';
      });
      return;
    }
    setState(() {
      _loadingReps = true;
      _error = null;
    });
    try {
      final page = await ref.read(employeeRepositoryProvider).fetchEmployees(
            companyId: session.company.id,
            roleCode: 'sales_representative',
            pageSize: 200,
          );
      if (!mounted) return;
      setState(() {
        _reps = page.items;
        _loadingReps = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadingReps = false;
        _error = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingReps = false;
        _error = 'Unable to load sales representatives.';
      });
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      _loadingReport = true;
      _error = null;
    });
    try {
      final snapshot = await ref
          .read(reportRepositoryProvider)
          .fetchCollectionsReport(
            asOfDate: _asOf,
            employeeIds: _selectedRepIds.toList(),
            salesRepsLabel: _salesRepsLabel,
            currencySymbol: _currencySymbol,
          );
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loadingReport = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadingReport = false;
        _error = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingReport = false;
        _error = 'Unable to load the collections report.';
      });
    }
  }

  Future<void> _pickAsOf() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOf,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      _asOf = DateTime(picked.year, picked.month, picked.day);
    });
  }

  void _selectAllReps() {
    setState(() => _selectedRepIds.clear());
  }

  void _toggleRep(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedRepIds.add(id);
      } else {
        _selectedRepIds.remove(id);
      }
    });
  }

  Future<void> _exportExcel() async {
    final snapshot = _snapshot;
    if (snapshot == null || _exportingExcel) return;
    setState(() => _exportingExcel = true);
    try {
      downloadBrowserFile(
        bytes: CollectionsReportExcelExporter.buildBytes(snapshot),
        filename: CollectionsReportExcelExporter.filename(asOf: snapshot.asOfDate),
        mimeType: 'application/vnd.ms-excel',
      );
      if (!mounted) return;
      SelloSnackbars.success(context, 'Excel export downloaded.');
    } on UnsupportedError {
      if (!mounted) return;
      SelloSnackbars.warning(
        context,
        'Export download is available in the web app.',
      );
    } catch (_) {
      if (!mounted) return;
      SelloSnackbars.error(context, 'Unable to export Excel right now.');
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  Future<void> _exportPdf() async {
    final snapshot = _snapshot;
    if (snapshot == null || _exportingPdf) return;
    setState(() => _exportingPdf = true);
    try {
      final bytes = await CollectionsReportPdf.buildBytes(snapshot);
      downloadBrowserFile(
        bytes: bytes,
        filename: CollectionsReportPdf.filename(asOf: snapshot.asOfDate),
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      SelloSnackbars.success(context, 'PDF export downloaded.');
    } on UnsupportedError {
      if (!mounted) return;
      SelloSnackbars.warning(
        context,
        'Export download is available in the web app.',
      );
    } catch (_) {
      if (!mounted) return;
      SelloSnackbars.error(context, 'Unable to export PDF right now.');
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    String money(num value) =>
        SelloFormatters.currency(value, symbol: _currencySymbol);

    return SelloFormDialog(
      title: kCollectionsReportTitle,
      subtitle: kCollectionsReportQuestion,
      maxWidth: kSelloFormDialogWidth,
      fullscreenOnMobile: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Filters(
            asOf: _asOf,
            reps: _reps,
            selectedRepIds: _selectedRepIds,
            loadingReps: _loadingReps,
            applying: _loadingReport,
            onPickAsOf: _pickAsOf,
            onSelectAll: _selectAllReps,
            onToggleRep: _toggleRep,
            onApply: _loadingReport ? null : _loadReport,
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_loadingReport && snapshot == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (snapshot == null)
            const SizedBox.shrink()
          else ...[
            Text(
              'As of ${SelloFormatters.date(snapshot.asOfDate)}',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Sales reps: ${snapshot.salesRepsLabel}',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            if (snapshot.isEmpty)
              const SelloEmptyState(
                title: 'No open invoices',
                message:
                    'Nothing is outstanding for this as-of date and sales-rep selection.',
                icon: Icons.receipt_long_outlined,
              )
            else ...[
              for (final group in snapshot.groups) ...[
                _CustomerGroupCard(group: group, money: money),
                const SizedBox(height: 16),
              ],
              _GrandTotal(total: snapshot.grandTotal, money: money),
            ],
          ],
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Close',
        primaryLabel: 'Export PDF',
        primaryLoading: _exportingPdf,
        primaryEnabled: snapshot != null && !_exportingPdf,
        onPrimary: _exportPdf,
        leading: SelloButton(
          label: 'Export Excel',
          variant: SelloButtonVariant.outline,
          icon: Icons.table_chart_outlined,
          loading: _exportingExcel,
          onPressed: snapshot == null || _exportingExcel ? null : _exportExcel,
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.asOf,
    required this.reps,
    required this.selectedRepIds,
    required this.loadingReps,
    required this.applying,
    required this.onPickAsOf,
    required this.onSelectAll,
    required this.onToggleRep,
    required this.onApply,
  });

  final DateTime asOf;
  final List<EmployeeSummary> reps;
  final Set<String> selectedRepIds;
  final bool loadingReps;
  final bool applying;
  final VoidCallback onPickAsOf;
  final VoidCallback onSelectAll;
  final void Function(String id, bool selected) onToggleRep;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final allSelected = selectedRepIds.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: 220,
              child: InkWell(
                onTap: onPickAsOf,
                borderRadius: AppRadius.inputAll,
                child: InputDecorator(
                  decoration: InputDecoration(
                    label: const SelloFieldLabel(label: 'As of'),
                    suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                  ),
                  child: Text(
                    SelloFormatters.date(asOf),
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            SelloButton(
              label: 'Apply',
              icon: Icons.refresh_rounded,
              variant: SelloButtonVariant.outline,
              loading: applying,
              onPressed: onApply,
            ),
          ],
        ),
        const SizedBox(height: 14),
        const SelloFieldLabel(label: 'Sales reps'),
        const SizedBox(height: 8),
        if (loadingReps)
          const Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('All Sales Reps'),
                selected: allSelected,
                onSelected: (_) => onSelectAll(),
                showCheckmark: false,
                selectedColor: AppColors.surfaceSelected,
                side: BorderSide(
                  color: allSelected
                      ? AppColors.outlineStrong
                      : AppColors.outlinePanel,
                ),
                labelStyle: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12.5,
                  fontWeight: allSelected ? FontWeight.w600 : FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
              for (final rep in reps)
                FilterChip(
                  label: Text(rep.fullName),
                  selected: selectedRepIds.contains(rep.id),
                  onSelected: (selected) => onToggleRep(rep.id, selected),
                  showCheckmark: false,
                  selectedColor: AppColors.surfaceSelected,
                  side: BorderSide(
                    color: selectedRepIds.contains(rep.id)
                        ? AppColors.outlineStrong
                        : AppColors.outlinePanel,
                  ),
                  labelStyle: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    fontWeight: selectedRepIds.contains(rep.id)
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _CustomerGroupCard extends StatelessWidget {
  const _CustomerGroupCard({required this.group, required this.money});

  final CollectionsReportCustomerGroup group;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    return SelloCard(
      elevation: SelloCardElevation.flat,
      enableHoverLift: false,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            group.customerName,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          if (group.customerPhone != null && group.customerPhone!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                group.customerPhone!,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12.5,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              group.salesRepLabel,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12.5,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _InvoiceTable(group: group, money: money),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total ${group.customerName}',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                money(group.subtotal),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InvoiceTable extends StatelessWidget {
  const _InvoiceTable({required this.group, required this.money});

  final CollectionsReportCustomerGroup group;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    const headerStyle = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.textTertiary,
    );
    const cellStyle = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 13,
      color: AppColors.textSecondary,
    );

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.1),
        1: FlexColumnWidth(1.4),
        2: FlexColumnWidth(1.3),
        3: FlexColumnWidth(1.2),
        4: FlexColumnWidth(1.0),
        5: FlexColumnWidth(1.3),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        const TableRow(
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Invoice', style: headerStyle),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('No.', style: headerStyle),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Old invoice / reference', style: headerStyle),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Date', style: headerStyle),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text('Aging (days)', style: headerStyle),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text('Open Balance', style: headerStyle),
              ),
            ),
          ],
        ),
        for (final invoice in group.invoices)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(invoice.documentType, style: cellStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(invoice.orderNumber, style: cellStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(invoice.referenceNumber ?? '—', style: cellStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  SelloFormatters.date(invoice.orderedAt),
                  style: cellStyle,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('${invoice.agingDays}', style: cellStyle),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(money(invoice.openBalance), style: cellStyle),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _GrandTotal extends StatelessWidget {
  const _GrandTotal({required this.total, required this.money});

  final num total;
  final String Function(num) money;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'GRAND TOTAL',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            money(total),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
