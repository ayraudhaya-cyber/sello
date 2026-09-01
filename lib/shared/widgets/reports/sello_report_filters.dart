import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/report_models.dart';
import 'package:sello/shared/widgets/inputs/sello_dropdown.dart';

/// Shared report filter strip — reuse on Hub Reports and future dashboards.
class SelloReportFiltersBar extends StatelessWidget {
  const SelloReportFiltersBar({
    super.key,
    required this.query,
    required this.onQueryChanged,
    this.categoryFilter,
    this.onCategoryChanged,
    this.showCategory = true,
    this.showGranularity = true,
    this.showComparison = true,
  });

  final ReportQuery query;
  final ValueChanged<ReportQuery> onQueryChanged;
  final ReportCategory? categoryFilter;
  final ValueChanged<ReportCategory?>? onCategoryChanged;
  final bool showCategory;
  final bool showGranularity;
  final bool showComparison;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.mdPlus),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.panelAll,
        border: Border.all(color: AppColors.outlinePanel),
        boxShadow: AppShadows.panel,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 168,
            child: SelloDropdown<ReportDatePreset>(
              label: 'Date range',
              value: query.preset == ReportDatePreset.custom
                  ? ReportDatePreset.custom
                  : query.preset,
              items: [
                for (final preset in ReportDatePreset.values)
                  if (preset != ReportDatePreset.custom)
                    DropdownMenuItem(value: preset, child: Text(preset.label)),
              ],
              onChanged: (value) {
                if (value == null) return;
                onQueryChanged(
                  query.copyWith(preset: value, clearCustom: true),
                );
              },
            ),
          ),
          if (showGranularity)
            SizedBox(
              width: 140,
              child: SelloDropdown<ReportTrendGranularity>(
                label: 'Trend',
                value: query.granularity,
                items: [
                  for (final g in ReportTrendGranularity.values)
                    DropdownMenuItem(value: g, child: Text(g.label)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  onQueryChanged(query.copyWith(granularity: value));
                },
              ),
            ),
          if (showComparison)
            SizedBox(
              width: 168,
              child: SelloDropdown<ReportComparisonMode>(
                label: 'Compare',
                value: query.comparison,
                items: [
                  for (final mode in ReportComparisonMode.values)
                    DropdownMenuItem(
                      value: mode,
                      enabled: mode == ReportComparisonMode.none,
                      child: Text(
                        mode == ReportComparisonMode.none
                            ? mode.label
                            : '${mode.label} (soon)',
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  onQueryChanged(query.copyWith(comparison: value));
                },
              ),
            ),
          if (showCategory)
            SizedBox(
              width: 168,
              child: SelloDropdown<ReportCategory?>(
                label: 'Category',
                value: categoryFilter,
                items: [
                  const DropdownMenuItem<ReportCategory?>(
                    value: null,
                    child: Text('All areas'),
                  ),
                  for (final category in ReportCategory.values)
                    if (category.isAvailable)
                      DropdownMenuItem(
                        value: category,
                        child: Text(category.label),
                      ),
                ],
                onChanged: (value) => onCategoryChanged?.call(value),
              ),
            ),
          TextButton.icon(
            onPressed: () => _pickCustomRange(context),
            icon: const Icon(Icons.date_range_outlined, size: 18),
            label: Text(
              query.preset == ReportDatePreset.custom
                  ? 'Edit custom range'
                  : 'Custom range',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final initialStart = query.customFrom?.toLocal() ??
        now.subtract(const Duration(days: 29));
    final initialEnd = query.customTo?.toLocal() ?? now;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: DateTime(initialStart.year, initialStart.month, initialStart.day),
        end: DateTime(initialEnd.year, initialEnd.month, initialEnd.day),
      ),
    );
    if (range == null) return;
    onQueryChanged(
      query.copyWith(
        preset: ReportDatePreset.custom,
        customFrom: range.start,
        customTo: range.end,
      ),
    );
  }
}
