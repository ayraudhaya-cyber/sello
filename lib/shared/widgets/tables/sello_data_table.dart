import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';

/// Lightweight data table wrapper for Hub surfaces.
///
/// Flat white panel, soft panel border, veil row hover, optional footer
/// (pagination). Emphasis inside a row comes from [SelloTableText].
class SelloDataTable extends StatelessWidget {
  const SelloDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.headingRowHeight = 48,
    this.dataRowMinHeight = 68,
    this.dataRowMaxHeight = 72,
    this.minWidth,
    this.footer,
    this.horizontalMargin = 24,
    this.columnSpacing = 28,
  });

  final List<DataColumn> columns;
  final List<DataRow> rows;
  final double headingRowHeight;
  final double dataRowMinHeight;
  final double dataRowMaxHeight;
  final double? minWidth;
  final Widget? footer;
  final double horizontalMargin;
  final double columnSpacing;

  @override
  Widget build(BuildContext context) {
    final colors = context.selloColors;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.panelAll,
        border: Border.all(color: AppColors.outlinePanel),
        boxShadow: AppShadows.panel,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final tableWidth = constraints.maxWidth;
              final resolvedMinWidth = minWidth ?? tableWidth;
              final expandedColumns = _columnsFillingWidth(
                columns: columns,
                tableWidth: resolvedMinWidth,
              );

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: resolvedMinWidth),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dataTableTheme: Theme.of(context).dataTableTheme.copyWith(
                            headingRowColor: WidgetStateProperty.all(
                              AppColors.surface,
                            ),
                            headingTextStyle:
                                context.texts.labelMedium?.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.15,
                            ),
                            dataRowColor:
                                WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return colors.surfaceSelected;
                              }
                              if (states.contains(WidgetState.hovered)) {
                                return colors.veil;
                              }
                              return AppColors.surface;
                            }),
                            horizontalMargin: horizontalMargin,
                            columnSpacing: columnSpacing,
                            dividerThickness: 1,
                          ),
                      dividerColor: AppColors.outlineSubtle,
                    ),
                    child: DataTable(
                      headingRowHeight: headingRowHeight,
                      dataRowMinHeight: dataRowMinHeight,
                      dataRowMaxHeight: dataRowMaxHeight,
                      showCheckboxColumn: false,
                      columns: expandedColumns,
                      rows: rows,
                    ),
                  ),
                ),
              );
            },
          ),
          if (footer != null) ...[
            const Divider(
              height: 1,
              thickness: 1,
              color: AppColors.outlineSubtle,
            ),
            footer!,
          ],
        ],
      ),
    );
  }

  /// Stretch the leading identity column so the table uses the full card width
  /// instead of leaving a dead zone after the last column.
  List<DataColumn> _columnsFillingWidth({
    required List<DataColumn> columns,
    required double tableWidth,
  }) {
    if (columns.isEmpty || !tableWidth.isFinite || tableWidth <= 0) {
      return columns;
    }

    final otherCount = columns.length - 1;
    // Keep this slightly lean so leftover width prefers the identity column.
    const estimatedOtherColumn = 96.0;
    final reserved = (horizontalMargin * 2) +
        (columnSpacing * otherCount) +
        (estimatedOtherColumn * otherCount);
    final leadWidth = (tableWidth - reserved).clamp(220.0, 640.0);

    final first = columns.first;
    return [
      DataColumn(
        label: SizedBox(
          width: leadWidth,
          child: Align(
            alignment:
                first.numeric ? Alignment.centerRight : Alignment.centerLeft,
            child: first.label,
          ),
        ),
        numeric: first.numeric,
        tooltip: first.tooltip,
        onSort: first.onSort,
      ),
      ...columns.skip(1),
    ];
  }
}

/// Emphasis levels for table cell text.
enum SelloTableTone {
  /// Row identity — the value a user scans for.
  strong,

  /// Standard cell value.
  normal,

  /// Supporting metadata (SKU, timestamps, units).
  muted,
}

/// Cell text with consistent hierarchy across every Sello table.
class SelloTableText extends StatelessWidget {
  const SelloTableText(
    this.value, {
    super.key,
    this.tone = SelloTableTone.normal,
    this.numeric = false,
    this.maxLines = 1,
  });

  final String value;
  final SelloTableTone tone;

  /// Uses tabular figures so numeric columns align vertically.
  final bool numeric;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.selloColors;
    final base = switch (tone) {
      SelloTableTone.strong => context.texts.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      SelloTableTone.normal => context.texts.bodyMedium,
      SelloTableTone.muted => context.texts.bodySmall?.copyWith(
          color: colors.textSecondary,
        ),
    };

    return Text(
      value,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: numeric ? TextAlign.right : TextAlign.start,
      style: numeric ? AppTypography.numeric(base) : base,
    );
  }
}

/// Table column helper so headings stay consistent across screens.
DataColumn selloDataColumn(String label, {bool numeric = false}) {
  return DataColumn(
    label: Text(label),
    numeric: numeric,
  );
}
