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
  String? orderVisitId,
  num orderTotal = 0,
  num amountPaid = 0,
  num amountPending = 0,
  List<OrderCollectionEntry> priorEntries = const [],
  PaymentMethod? orderPaymentMethod,
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
      orderVisitId: orderVisitId,
      orderTotal: orderTotal,
      amountPaid: amountPaid,
      amountPending: amountPending,
      priorEntries: priorEntries,
      orderPaymentMethod: orderPaymentMethod,
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
    this.orderVisitId,
    this.orderTotal = 0,
    this.amountPaid = 0,
    this.amountPending = 0,
    this.priorEntries = const [],
    this.orderPaymentMethod,
  });

  final String customerId;
  final String customerName;
  final String orderId;
  final String orderNumber;
  final num outstanding;
  final String currencySymbol;
  final String? orderVisitId;
  final num orderTotal;
  final num amountPaid;
  final num amountPending;
  final List<OrderCollectionEntry> priorEntries;

  /// How the order was placed. Only used to pre-select the method chip.
  final PaymentMethod? orderPaymentMethod;

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
  late PaymentMethod _method;
  DateTime _chequeDate = DateTime.now();
  bool _saving = false;
  bool _loading = true;
  String? _error;
  AssociatedChequeMatch? _match;

  OrderCollectionSnapshot get _snapshot => OrderCollectionSnapshot(
    orderTotal: widget.orderTotal > 0
        ? widget.orderTotal
        : widget.outstanding + widget.amountPaid + widget.amountPending,
    amountPaid: widget.amountPaid,
    amountPending: widget.amountPending,
    entries: widget.priorEntries,
  );

  bool get _usingExisting => OrderCollectionAssociation.shouldUseExistingCheque(
    method: _method,
    match: _match,
  );

  @override
  void initState() {
    super.initState();
    _method = OrderCollectionAssociation.suggestedMethodFromOrder(
      widget.orderPaymentMethod,
    );
    _holder.text = widget.customerName;
    _writeAmount(widget.outstanding);
    Future.microtask(_loadAssociatedCheques);
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

  String _money(num value) =>
      SelloFormatters.currency(value, symbol: widget.currencySymbol);

  void _writeAmount(num value) {
    _amount.text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  void _syncAmountToCeiling() {
    final ceiling = OrderCollectionAssociation.newCollectionCeiling(
      remaining: widget.outstanding,
      method: _method,
      match: _match,
    );
    _writeAmount(ceiling > 0 ? ceiling : widget.outstanding);
  }

  Future<void> _loadAssociatedCheques() async {
    try {
      final cheques = await ref
          .read(chequeRepositoryProvider)
          .fetchCheques(customerId: widget.customerId, pageSize: 100);
      final paymentIds = [
        for (final cheque in cheques.items)
          if (cheque.paymentId != null) cheque.paymentId!,
      ];
      final allocations = await ref
          .read(paymentRepositoryProvider)
          .fetchAllocationsForPayments(paymentIds);
      final match = OrderCollectionAssociation.findAssociatedCheque(
        cheques: cheques.items,
        orderId: widget.orderId,
        orderNumber: widget.orderNumber,
        orderVisitId: widget.orderVisitId,
        orderRemaining: widget.outstanding,
        allocationsByPaymentId: allocations,
      );
      if (!mounted) return;
      setState(() {
        _match = match;
        _loading = false;
        if (match != null &&
            match.applicableAmount >= widget.outstanding - 0.001) {
          _method = PaymentMethod.cheque;
        }
        _syncAmountToCeiling();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_usingExisting) {
      await _saveExistingCheque();
      return;
    }

    final amountError = OrderCollectionRules.validateNewCollection(
      method: _method,
      amount: _parsedAmount,
      remaining: widget.outstanding,
      match: _match,
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
      if (OrderCollectionAssociation.shouldCreateNewCheque(
        method: _method,
        match: _match,
      )) {
        await ref
            .read(chequeRepositoryProvider)
            .createCheque(
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
                visitId: widget.orderVisitId,
                notes: 'Collected against ${widget.orderNumber}',
              ),
            );
      } else {
        final result = await ref
            .read(paymentRepositoryProvider)
            .receivePayment(
              ReceivePaymentInput(
                customerId: widget.customerId,
                amount: amount,
                method: _method,
                allocations: [allocation],
                notes: 'Collected against ${widget.orderNumber}',
                visitId: widget.orderVisitId,
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

  Future<void> _saveExistingCheque() async {
    final match = _match;
    if (match == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(chequeRepositoryProvider);
      if (match.action == AssociatedChequeAction.collectExisting) {
        await repo.collectCheque(
          CollectChequeInput(
            chequeId: match.cheque.id,
            collectionDate: DateTime.now(),
            allocations: [
              PaymentAllocationInput(
                orderId: widget.orderId,
                amount: match.applicableAmount,
              ),
            ],
            notes: 'Collected against ${widget.orderNumber}',
          ),
        );
      } else {
        await repo.allocateChequePaymentToOrder(
          chequeId: match.cheque.id,
          orderId: widget.orderId,
        );
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
        _error = match.action == AssociatedChequeAction.collectExisting
            ? 'Unable to collect this cheque.'
            : 'Unable to apply this cheque.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final outstandingMoney = _money(widget.outstanding);
    final match = _match;
    final primaryLabel = _saving
        ? 'Saving…'
        : _usingExisting
        ? OrderCollectionAssociation.existingChequeActionLabel(match!.action)
        : 'Record collection';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              widget.customerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Collect money for this order. This does not create a new sale.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 13,
                height: 1.35,
                color: AppColors.textTertiary,
              ),
            ),
            if (_loading) ...[
              const SizedBox(height: 24),
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
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
                outstandingMoney,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              if (_snapshot.hasPriorCollections) ...[
                const SizedBox(height: 12),
                _LabeledValue(
                  label: 'Already collected',
                  value: _alreadyCollectedLine(),
                ),
                const SizedBox(height: 8),
                _LabeledValue(label: 'Remaining', value: outstandingMoney),
              ],
              if (widget.amountPending > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'A collection is waiting for Owner or Manager approval. Outstanding changes after they approve it.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (match != null) ...[
                const SizedBox(height: 12),
                _ExistingChequeCard(
                  match: match,
                  amountLabel: _money(match.applicableAmount),
                ),
              ],
              const SizedBox(height: 16),
              SelloTextField(
                controller: _amount,
                label: 'Amount received',
                required: true,
                enabled: !_usingExisting && !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'How is this amount being received?',
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
                      label: OrderCollectionAssociation.methodChipLabel(method),
                      selected: _method == method,
                      onTap: _saving
                          ? null
                          : () => setState(() {
                              _method = method;
                              _error = null;
                              _syncAmountToCeiling();
                            }),
                    ),
                ],
              ),
              if (widget.orderPaymentMethod != null &&
                  _method == widget.orderPaymentMethod) ...[
                const SizedBox(height: 8),
                const Text(
                  'Pre-selected from the order. Change it if the customer '
                  'paid another way.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
              if (_method == PaymentMethod.cheque && !_usingExisting) ...[
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
                    label:
                        'Cheque date ${DateFormat('d MMM yyyy').format(_chequeDate)}',
                    variant: SelloButtonVariant.outline,
                    onPressed: _saving ? null : _pickChequeDate,
                  ),
                ),
              ],
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
                label: primaryLabel,
                expanded: true,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _alreadyCollectedLine() {
    final collected = widget.amountPaid + widget.amountPending;
    final methods = widget.priorEntries
        .map(
          (entry) => OrderCollectionAssociation.methodChipLabel(entry.method),
        )
        .toSet();
    final money = _money(collected);
    if (methods.length == 1) return '$money · ${methods.first}';
    return money;
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

class _LabeledValue extends StatelessWidget {
  const _LabeledValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _ExistingChequeCard extends StatelessWidget {
  const _ExistingChequeCard({required this.match, required this.amountLabel});

  final AssociatedChequeMatch match;
  final String amountLabel;

  @override
  Widget build(BuildContext context) {
    final cheque = match.cheque;
    final waiting = match.action == AssociatedChequeAction.collectExisting;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: context.brandAccentContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            waiting
                ? 'Cheque waiting to be collected'
                : 'Existing cheque not applied to this order',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              cheque.chequeNumberLabel,
              cheque.bankName,
              amountLabel,
            ].where((part) => part.trim().isNotEmpty).join(' · '),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            waiting
                ? 'Mark this cheque as received instead of recording another one.'
                : 'Apply this cheque instead of creating another collection.',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
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
