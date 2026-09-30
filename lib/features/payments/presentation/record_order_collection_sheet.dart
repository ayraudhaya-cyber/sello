import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/orders/presentation/order_confirmation_share_sheet.dart';
import 'package:sello/features/payments/application/order_collection_rules.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/utils/formatters.dart';
import 'package:sello/shared/widgets/widgets.dart';

/// Collect money against one existing order. Does not create another sale.
Future<bool> showRecordOrderCollectionSheet({
  required BuildContext context,
  required String customerId,
  required String customerName,
  required String orderId,
  required String orderNumber,
  required num outstanding,
  required String currencySymbol,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => RecordOrderCollectionSheet(
      customerId: customerId,
      customerName: customerName,
      orderId: orderId,
      orderNumber: orderNumber,
      outstanding: outstanding,
      currencySymbol: currencySymbol,
    ),
  ).then((value) => value ?? false);
}

class RecordOrderCollectionSheet extends ConsumerStatefulWidget {
  const RecordOrderCollectionSheet({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.orderId,
    required this.orderNumber,
    required this.outstanding,
    required this.currencySymbol,
  });

  final String customerId;
  final String customerName;
  final String orderId;
  final String orderNumber;
  final num outstanding;
  final String currencySymbol;

  @override
  ConsumerState<RecordOrderCollectionSheet> createState() =>
      _RecordOrderCollectionSheetState();
}

class _RecordOrderCollectionSheetState
    extends ConsumerState<RecordOrderCollectionSheet> {
  final _amount = TextEditingController();
  final _bank = TextEditingController();
  final _chequeNumber = TextEditingController();
  final _holder = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _chequeDate = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _holder.text = widget.customerName;
    _amount.text = widget.outstanding == widget.outstanding.roundToDouble()
        ? widget.outstanding.toStringAsFixed(0)
        : widget.outstanding.toString();
  }

  @override
  void dispose() {
    _amount.dispose();
    _bank.dispose();
    _chequeNumber.dispose();
    _holder.dispose();
    super.dispose();
  }

  num? get _parsedAmount => num.tryParse(_amount.text.trim());

  Future<void> _save() async {
    final amountError = OrderCollectionRules.validateAmount(
      amount: _parsedAmount,
      outstanding: widget.outstanding,
    );
    if (amountError != null) {
      setState(() => _error = amountError);
      return;
    }
    if (_method == PaymentMethod.cheque) {
      final chequeError = OrderCollectionRules.validateCheque(
        bankName: _bank.text,
        chequeNumber: _chequeNumber.text,
        holderName: _holder.text,
      );
      if (chequeError != null) {
        setState(() => _error = chequeError);
        return;
      }
    }

    final amount = _parsedAmount!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final allocation = PaymentAllocationInput(
        orderId: widget.orderId,
        amount: amount,
      );
      if (_method == PaymentMethod.cheque) {
        await ref.read(chequeRepositoryProvider).createCheque(
              CreateChequeInput(
                customerId: widget.customerId,
                amount: amount,
                bankName: _bank.text.trim(),
                chequeNumber: _chequeNumber.text.trim(),
                holderName: _holder.text.trim(),
                chequeDate: _chequeDate,
                collectionDate: DateTime.now(),
                allocations: [allocation],
                markCollected: true,
                notes: 'Collected against ${widget.orderNumber}',
              ),
            );
      } else {
        final result = await ref.read(paymentRepositoryProvider).receivePayment(
              ReceivePaymentInput(
                customerId: widget.customerId,
                amount: amount,
                method: _method,
                allocations: [allocation],
                notes: 'Collected against ${widget.orderNumber}',
              ),
            );
        if (!mounted) return;
        if (result.isPendingReview) {
          await presentCollectionAcknowledgement(
            context,
            result.acknowledgement,
          );
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Unable to record this collection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final money = SelloFormatters.currency(
      widget.outstanding,
      symbol: widget.currencySymbol,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineSubtle,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Record collection',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.orderNumber,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            widget.customerName,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Outstanding',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            money,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Payment method',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final method in OrderCollectionRules.methods)
                _MethodChip(
                  label: method == PaymentMethod.bankTransfer
                      ? 'Bank'
                      : method.label,
                  selected: _method == method,
                  onTap: _saving
                      ? null
                      : () => setState(() {
                            _method = method;
                            _error = null;
                          }),
                ),
            ],
          ),
          if (_method == PaymentMethod.cheque) ...[
            const SizedBox(height: 14),
            SelloSriLankaBankField(
              controller: _bank,
              optionsViewOpenDirection: OptionsViewOpenDirection.up,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            SelloTextField(
              controller: _chequeNumber,
              label: 'Cheque number',
              required: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            SelloTextField(
              controller: _holder,
              label: 'Name on cheque',
              required: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: SelloButton(
                label: 'Cheque date ${DateFormat('d MMM yyyy').format(_chequeDate)}',
                variant: SelloButtonVariant.outline,
                onPressed: _saving ? null : _pickChequeDate,
              ),
            ),
          ],
          const SizedBox(height: 14),
          SelloTextField(
            controller: _amount,
            label: 'Amount received',
            required: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                color: AppColors.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SelloButton(
            label: _saving ? 'Saving…' : 'Record collection',
            expanded: true,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  Future<void> _pickChequeDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _chequeDate,
    );
    if (picked == null) return;
    setState(() => _chequeDate = picked);
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? context.brandAccentContainer.withValues(alpha: 0.7)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              fontSize: 14,
              color: selected ? context.brandAccent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
