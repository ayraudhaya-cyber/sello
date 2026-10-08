import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/shared/models/order_summary.dart';
import 'package:sello/shared/widgets/widgets.dart';

class ReassignOrderSalesRepDialog extends ConsumerStatefulWidget {
  const ReassignOrderSalesRepDialog({
    super.key,
    required this.order,
    required this.reps,
  });

  final OrderSummary order;
  final List<SalesRepOption> reps;

  @override
  ConsumerState<ReassignOrderSalesRepDialog> createState() =>
      _ReassignOrderSalesRepDialogState();
}

class _ReassignOrderSalesRepDialogState
    extends ConsumerState<ReassignOrderSalesRepDialog> {
  late String? _employeeId;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _employeeId = widget.order.employeeId;
  }

  Future<void> _submit() async {
    final selected = _employeeId;
    if (selected == null || selected == widget.order.employeeId) {
      Navigator.of(context).maybePop(false);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(orderRepositoryProvider).reassignSalesRep(
            orderId: widget.order.id,
            employeeId: selected,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = failure.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Unable to change the Sales Rep. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelloFormDialog(
      title: 'Change Sales Rep',
      subtitle:
          'This updates who owns ${widget.order.orderNumber} for reporting. '
          'It does not change payments or stock.',
      maxWidth: 480,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13.5,
                color: AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
          ],
          SelloDropdown<String>(
            value: widget.reps.any((rep) => rep.id == _employeeId)
                ? _employeeId
                : null,
            label: 'Sales Rep',
            required: true,
            items: [
              for (final rep in widget.reps)
                DropdownMenuItem(value: rep.id, child: Text(rep.name)),
            ],
            onChanged: (value) => setState(() => _employeeId = value),
          ),
        ],
      ),
      footer: SelloDialogFooter(
        cancelLabel: 'Cancel',
        cancelVariant: SelloButtonVariant.outline,
        onCancel: _submitting ? null : () => Navigator.of(context).maybePop(),
        primaryLabel: 'Save',
        primaryLoading: _submitting,
        onPrimary: _submitting ? null : _submit,
      ),
    );
  }
}
