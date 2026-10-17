import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/collections/application/collections_excel_exporter.dart';
import 'package:sello/features/collections/application/collections_pdf_exporter.dart';
import 'package:sello/features/collections/application/collections_summary.dart';
import 'package:sello/features/collections/application/sales_rep_options_provider.dart';
import 'package:sello/features/hub/reports/application/collections_report_excel.dart';
import 'package:sello/features/hub/reports/application/collections_report_pdf.dart';
import 'package:sello/features/hub/reports/application/report_pdf_chrome.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/collections_report.dart';
import 'package:sello/shared/utils/browser_file_download.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Payments export. Collected is money already received. Still to collect is
/// the same as-of list as Reports → Collections Report.
class CollectionsExportDialog extends ConsumerStatefulWidget {
  const CollectionsExportDialog({super.key, this.initialEmployeeId});

  final String? initialEmployeeId;

  @override
  ConsumerState<CollectionsExportDialog> createState() =>
      _CollectionsExportDialogState();
}

class _CollectionsExportDialogState
    extends ConsumerState<CollectionsExportDialog> {
  _ExportKind _kind = _ExportKind.collected;
  CollectionsPeriod? _period = CollectionsPeriod.thisMonth;
  late DateTime _from;
  late DateTime _to; // inclusive day
  late DateTime _asOf;
  String? _employeeId;
  _ExportFile? _exporting;

  @override
  void initState() {
    super.initState();
    _employeeId = widget.initialEmployeeId;
    final today = DateTime.now();
    _asOf = DateTime(today.year, today.month, today.day);
    _applyPeriod(CollectionsPeriod.thisMonth);
  }

  void _applyPeriod(CollectionsPeriod period) {
    final range = period.range();
    _period = period;
    _from = range.from;
    _to = range.before.subtract(const Duration(days: 1));
  }

  Future<void> _pick({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      _period = null;
      final day = DateTime(picked.year, picked.month, picked.day);
      if (isFrom) {
        _from = day;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = day;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
  }

  ReportPdfCompany _company() {
    final session = ref.read(currentSessionProvider);
    final settings = ref.read(companySettingsProvider);
    final name = session?.company.name.trim() ?? '';
    return ReportPdfCompany(
      name: name.isEmpty ? 'Company' : name,
      address: settings.documentAddress,
      phone: settings.documentPhone,
      email: settings.documentEmail,
    );
  }

  Future<void> _export(_ExportFile file) async {
    if (_exporting != null) return;
    setState(() => _exporting = file);
    try {
      if (_kind == _ExportKind.stillToCollect) {
        await _exportStillToCollect(file);
      } else {
        await _exportCollected(file);
      }
    } on AppFailure catch (failure) {
      if (!mounted) return;
      SelloSnackbars.error(context, failure.message);
    } on UnsupportedError {
      if (!mounted) return;
      SelloSnackbars.warning(
        context,
        'Export download is available in the web app.',
      );
    } catch (_) {
      if (!mounted) return;
      SelloSnackbars.error(context, 'Unable to export collections right now.');
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  Future<void> _exportCollected(_ExportFile file) async {
    final reps = ref.read(salesRepOptionsProvider).value ?? const [];
    final repName = _employeeId == null
        ? 'All sales reps'
        : reps
                  .where((r) => r.id == _employeeId)
                  .map((r) => r.fullName)
                  .firstOrNull ??
              'Selected sales rep';

    final rows = await ref
        .read(paymentRepositoryProvider)
        .fetchCollections(
          employeeId: _employeeId,
          from: _from,
          before: _to.add(const Duration(days: 1)),
        );
    if (!mounted) return;
    if (rows.isEmpty) {
      SelloSnackbars.info(
        context,
        'No collections found for this period and sales rep.',
      );
      return;
    }

    if (file == _ExportFile.pdf) {
      final bytes = await CollectionsPdfExporter.buildBytes(
        rows: rows,
        from: _from,
        to: _to,
        repLabel: repName,
        currencySymbol: SelloFormatters.currencySymbol(
          ref.read(companySettingsProvider).currency,
        ),
        company: _company(),
      );
      if (!mounted) return;
      downloadBrowserFile(
        bytes: bytes,
        filename: CollectionsPdfExporter.filename(from: _from, to: _to),
        mimeType: 'application/pdf',
      );
    } else {
      downloadBrowserFile(
        bytes: CollectionsExcelExporter.buildBytes(
          rows: rows,
          from: _from,
          to: _to,
          repLabel: repName,
        ),
        filename: CollectionsExcelExporter.filename(from: _from, to: _to),
        mimeType: 'application/vnd.ms-excel',
      );
    }
    SelloSnackbars.success(context, 'Collections export downloaded.');
    Navigator.of(context).pop();
  }

  Future<void> _exportStillToCollect(_ExportFile file) async {
    final reps = ref.read(salesRepOptionsProvider).value ?? const [];
    final selectedId = _employeeId;
    final selectedName = selectedId == null
        ? null
        : reps
              .where((rep) => rep.id == selectedId)
              .map((rep) => rep.fullName)
              .firstOrNull;
    final snapshot = await ref
        .read(reportRepositoryProvider)
        .fetchCollectionsReport(
          asOfDate: _asOf,
          employeeIds: selectedId == null ? const [] : [selectedId],
          salesRepsLabel: CollectionsReportMath.salesRepsLabel(
            selectedIds: selectedId == null ? const [] : [selectedId],
            selectedNames: [if (selectedName != null) selectedName],
          ),
          currencySymbol: SelloFormatters.currencySymbol(
            ref.read(companySettingsProvider).currency,
          ),
          collectionDueDays: ref
              .read(companySettingsProvider)
              .collectionDueDays,
        );
    if (!mounted) return;
    if (snapshot.isEmpty) {
      SelloSnackbars.info(
        context,
        'Nothing left to collect for this date and sales rep.',
      );
      return;
    }

    if (file == _ExportFile.pdf) {
      final bytes = await CollectionsReportPdf.buildBytes(
        snapshot,
        company: _company(),
      );
      if (!mounted) return;
      downloadBrowserFile(
        bytes: bytes,
        filename: CollectionsReportPdf.filename(asOf: _asOf),
        mimeType: 'application/pdf',
      );
    } else {
      downloadBrowserFile(
        bytes: CollectionsReportExcelExporter.buildBytes(snapshot),
        filename: CollectionsReportExcelExporter.filename(asOf: _asOf),
        mimeType: 'application/vnd.ms-excel',
      );
    }
    SelloSnackbars.success(context, 'Still to collect export downloaded.');
    Navigator.of(context).pop();
  }

  Future<void> _pickAsOf() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _asOf,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      _asOf = DateTime(picked.year, picked.month, picked.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final repsAsync = ref.watch(salesRepOptionsProvider);
    final reps = repsAsync.value ?? const [];
    final knownRep = reps.any((rep) => rep.id == _employeeId);

    final stillToCollect = _kind == _ExportKind.stillToCollect;

    return SelloFormDialog(
      title: 'Export collections',
      subtitle: stillToCollect
          ? 'What customers still owe, as of the date you pick.'
          : 'Money collected by your team, with a summary per sales rep.',
      maxWidth: kSelloFormDialogWidth,
      fullscreenOnMobile: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SelloFieldLabel(label: 'Report'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final kind in _ExportKind.values)
                ChoiceChip(
                  label: Text(kind.label),
                  selected: _kind == kind,
                  showCheckmark: false,
                  selectedColor: AppColors.surfaceSelected,
                  onSelected: (_) => setState(() => _kind = kind),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (stillToCollect) ...[
            _DateField(label: 'As of', value: _asOf, onTap: _pickAsOf),
          ] else ...[
            const SelloFieldLabel(label: 'Period'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final period in CollectionsPeriod.values)
                  ChoiceChip(
                    label: Text(period.label),
                    selected: _period == period,
                    showCheckmark: false,
                    selectedColor: AppColors.surfaceSelected,
                    onSelected: (_) => setState(() => _applyPeriod(period)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'From',
                    value: _from,
                    onTap: () => _pick(isFrom: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'To',
                    value: _to,
                    onTap: () => _pick(isFrom: false),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const SelloFieldLabel(label: 'Sales rep'),
          const SizedBox(height: 8),
          SelloDropdown<String>(
            value: knownRep ? _employeeId! : '',
            hint: 'All sales reps',
            onChanged: (value) => setState(
              () => _employeeId = value == null || value.isEmpty ? null : value,
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('All sales reps')),
              for (final rep in reps)
                DropdownMenuItem(value: rep.id, child: Text(rep.fullName)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            stillToCollect
                ? 'Unpaid placed, partly delivered, and completed orders, '
                      'plus opening balances. Each row shows how many days are '
                      'left, using the due days in Settings. After the due date, '
                      'the row names the sales rep, or the owner when no sales '
                      'rep is set. Opening balances are included only when All '
                      'sales reps is selected.'
                : 'Includes collected payments and payments awaiting approval '
                      '(listed separately, not counted as collected). '
                      'Unpaid orders are not included.',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        leading: SelloButton(
          label: 'Export PDF',
          variant: SelloButtonVariant.outline,
          loading: _exporting == _ExportFile.pdf,
          onPressed: _exporting != null ? null : () => _export(_ExportFile.pdf),
        ),
        primaryLabel: 'Export Excel',
        primaryLoading: _exporting == _ExportFile.excel,
        primaryEnabled: _exporting == null,
        onPrimary: () => _export(_ExportFile.excel),
      ),
    );
  }
}

enum _ExportFile { pdf, excel }

enum _ExportKind {
  collected('Collected'),
  stillToCollect('Still to collect');

  const _ExportKind(this.label);

  final String label;
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.inputAll,
      child: InputDecorator(
        decoration: InputDecoration(
          label: SelloFieldLabel(label: label),
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          SelloFormatters.date(value),
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
