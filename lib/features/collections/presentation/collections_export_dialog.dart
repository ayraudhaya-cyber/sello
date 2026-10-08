import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/collections/application/collections_excel_exporter.dart';
import 'package:sello/features/collections/application/collections_summary.dart';
import 'package:sello/features/collections/application/sales_rep_options_provider.dart';
import 'package:sello/shared/utils/browser_file_download.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Owner / Manager export of money actually collected (and awaiting approval).
/// Unpaid orders and outstanding balances are not part of this file — that is
/// the as-of Collections Report under Reports.
class CollectionsExportDialog extends ConsumerStatefulWidget {
  const CollectionsExportDialog({super.key, this.initialEmployeeId});

  final String? initialEmployeeId;

  @override
  ConsumerState<CollectionsExportDialog> createState() =>
      _CollectionsExportDialogState();
}

class _CollectionsExportDialogState
    extends ConsumerState<CollectionsExportDialog> {
  CollectionsPeriod? _period = CollectionsPeriod.thisMonth;
  late DateTime _from;
  late DateTime _to; // inclusive day
  String? _employeeId;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _employeeId = widget.initialEmployeeId;
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

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final reps = ref.read(salesRepOptionsProvider).value ?? const [];
      final repName = _employeeId == null
          ? 'All sales reps'
          : reps
                  .where((r) => r.id == _employeeId)
                  .map((r) => r.fullName)
                  .firstOrNull ??
              'Selected sales rep';

      final rows = await ref.read(paymentRepositoryProvider).fetchCollections(
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
      SelloSnackbars.success(context, 'Collections export downloaded.');
      Navigator.of(context).pop();
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
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repsAsync = ref.watch(salesRepOptionsProvider);
    final reps = repsAsync.value ?? const [];
    final knownRep = reps.any((rep) => rep.id == _employeeId);

    return SelloFormDialog(
      title: 'Export collections',
      subtitle: 'Money collected by your team, with a summary per sales rep.',
      maxWidth: kSelloFormDialogWidth,
      fullscreenOnMobile: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          const Text(
            'Includes collected payments and payments awaiting approval '
            '(listed separately, not counted as collected). '
            'Unpaid orders are not included.',
            style: TextStyle(
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
        primaryLabel: 'Export Excel',
        primaryLoading: _exporting,
        primaryEnabled: !_exporting,
        onPrimary: _export,
      ),
    );
  }
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
