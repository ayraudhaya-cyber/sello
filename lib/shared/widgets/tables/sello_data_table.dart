import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';

/// Lightweight data table wrapper for Hub surfaces.
class SelloDataTable extends StatelessWidget {
  const SelloDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.headingRowHeight = 48,
    // Must stay <= dataRowMaxHeight (Material default max is 48).
    this.dataRowMinHeight = 48,
    this.dataRowMaxHeight = 56,
  });

  final List<DataColumn> columns;
  final List<DataRow> rows;
  final double headingRowHeight;
  final double dataRowMinHeight;
  final double dataRowMaxHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.sizeOf(context).width > 720
                ? MediaQuery.sizeOf(context).width - 320
                : 640,
          ),
          child: DataTable(
            headingRowHeight: headingRowHeight,
            dataRowMinHeight: dataRowMinHeight,
            dataRowMaxHeight: dataRowMaxHeight,
            columns: columns,
            rows: rows,
          ),
        ),
      ),
    );
  }
}
