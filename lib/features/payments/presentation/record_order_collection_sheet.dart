import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/features/hub/settings/application/hub_settings_provider.dart';
import 'package:sello/features/mobile/dashboard/application/sello_company_settings_provider.dart';
import 'package:sello/features/orders/presentation/order_confirmation_share_sheet.dart';
import 'package:sello/features/payments/application/order_collection_rules.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/feedback/sello_activity.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_summary.dart';
import 'package:sello/shared/models/user_role.dart';
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
  final _discountAmount = TextEditingController();
  final _discountPercent = TextEditingController();
  final _wallet = TextEditingController();
  final _bank = TextEditingController();
  final _chequeNumber = TextEditingController();
  final _holder = TextEditingController();
  late PaymentMethod _method;
  DateTime _chequeDate = DateTime.now();
  bool _saving = false;
  bool _loading = true;
  num _walletAvailable = 0;
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
    _discountAmount.dispose();
    _discountPercent.dispose();
    _wallet.dispose();
    _bank.dispose();
    _chequeNumber.dispose();
    _holder.dispose();
    super.dispose();
  }

  num? get _parsedAmount => num.tryParse(_amount.text.trim());

  num get _discountAmountValue {
    final value = num.tryParse(_discountAmount.text.trim()) ?? 0;
    return value < 0 ? 0 : value;
  }

  num get _discountPercentValue {
    final value = num.tryParse(_discountPercent.text.trim()) ?? 0;
    return value < 0 ? 0 : value;
  }

  /// Resolved money discount against what this collection can still cover.
  num get _resolvedDiscount {
    if (!_discountAllowed()) return 0;
    return OrderCollectionRules.resolvedDiscount(
      outstanding: _collectableNow,
      amount: _discountAmountValue,
      percent: _discountPercentValue,
    );
  }

  void _clearDiscount() {
    _discountAmount.clear();
    _discountPercent.clear();
  }

  CompanySettings _readSettings() {
    final role = ref.read(currentRoleProvider);
    if (role == UserRole.salesRepresentative) {
      return ref.read(selloCompanySettingsProvider).valueOrNull ??
          CompanySettings.defaults;
    }
    return ref.read(companySettingsProvider);
  }

  bool _discountAllowed() {
    if (_usingExisting || _method == PaymentMethod.cheque) return false;
    final role = ref.read(currentRoleProvider);
    if (role != UserRole.salesRepresentative) return true;
    return _readSettings().salesRepsCanDiscountCollections;
  }

  num get _walletApplied {
    if (_usingExisting || _walletAvailable <= 0.001) return 0;
    final parsed = num.tryParse(_wallet.text.trim()) ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  /// Room left after an associated cheque that this save is not collecting.
  num get _collectableNow {
    final reserved =
        _match != null && _match!.usesExisting && !_usingExisting
        ? _match!.applicableAmount
        : 0;
    final room = widget.outstanding - reserved;
    return room < 0 ? 0 : room;
  }

  bool get _showWallet =>
      !_usingExisting &&
      _walletAvailable > 0.001 &&
      OrderCollectionRules.walletCap(
            available: _walletAvailable,
            outstanding: _collectableNow,
          ) >
          0.001;

  String _money(num value) =>
      SelloFormatters.currency(value, symbol: widget.currencySymbol);

  void _writeAmount(num value) {
    _amount.text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  void _writeWallet(num value) {
    _wallet.text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  /// Keeps wallet + cash + discount within outstanding.
  /// Discount wins first; wallet is trimmed next; cash fills the rest.
  void _syncSettlementToCeiling({bool trimWallet = true}) {
    final discount = _resolvedDiscount;
    final moneyRoom = _collectableNow - discount;
    final room = moneyRoom < 0 ? 0 : moneyRoom;

    if (_showWallet && trimWallet) {
      final walletCap = OrderCollectionRules.walletCap(
        available: _walletAvailable,
        outstanding: room,
      );
      if (_walletApplied > walletCap + 0.001) {
        _writeWallet(walletCap);
      }
    }

    final wallet = _showWallet ? _walletApplied : 0;
    final cashRoom = room - wallet;
    _writeAmount(cashRoom < 0 ? 0 : cashRoom);
  }

  void _syncAmountToCeiling() => _syncSettlementToCeiling();

  void _applyDefaultWallet() {
    final discount = _resolvedDiscount;
    final moneyRoom = _collectableNow - discount;
    final room = moneyRoom < 0 ? 0 : moneyRoom;
    final cap = OrderCollectionRules.walletCap(
      available: _walletAvailable,
      outstanding: room,
    );
    _writeWallet(cap);
  }

  Future<void> _loadAssociatedCheques() async {
    try {
      final customer = await ref
          .read(customerRepositoryProvider)
          .fetchById(widget.customerId);
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
        _walletAvailable = customer?.walletBalance ?? 0;
        _loading = false;
        if (match != null &&
            match.applicableAmount >= widget.outstanding - 0.001) {
          _method = PaymentMethod.cheque;
        }
        if (!_usingExisting && _walletAvailable > 0.001) {
          _applyDefaultWallet();
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

    final walletApplied = _walletApplied;
    final discount = _resolvedDiscount;
    final amountError = _showWallet
        ? OrderCollectionRules.validateWithWallet(
            walletApplied: walletApplied,
            walletAvailable: _walletAvailable,
            received: _parsedAmount,
            outstanding: _collectableNow,
            discount: discount,
          )
        : OrderCollectionRules.validateNewCollection(
            method: _method,
            amount: _parsedAmount,
            remaining: widget.outstanding,
            match: _match,
            discount: discount,
          );
    if (amountError != null) {
      setState(() => _error = amountError);
      return;
    }
    final amount = _parsedAmount ?? 0;
    if (_method != PaymentMethod.cheque) {
      final discountError = OrderCollectionRules.validateDiscount(
        discount: discount,
        moneyReceived: walletApplied + amount,
        outstanding: _collectableNow,
        allowed: _discountAllowed(),
      );
      if (discountError != null) {
        setState(() => _error = discountError);
        return;
      }
    }
    if (_method == PaymentMethod.cheque && amount > 0.001) {
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

    setState(() {
      _saving = true;
      _error = null;
    });
    var walletSaved = false;
    SelloActivity.begin();
    try {
      // Put the discount on the cash/card/bank row when present; otherwise on
      // the wallet row so a wallet-only settlement can still write off.
      // Discount-only (no cash/wallet) records amount 0 + discount.
      final discountOnCash = amount > 0.001 || walletApplied <= 0.001
          ? discount
          : 0;
      final discountOnWallet =
          amount <= 0.001 && walletApplied > 0.001 ? discount : 0;

      if (walletApplied > 0.001) {
        final walletSettle = walletApplied + discountOnWallet;
        final walletResult = await ref
            .read(paymentRepositoryProvider)
            .receivePayment(
              ReceivePaymentInput(
                customerId: widget.customerId,
                amount: walletApplied,
                discountAmount: discountOnWallet,
                method: PaymentMethod.wallet,
                allocations: [
                  PaymentAllocationInput(
                    orderId: widget.orderId,
                    amount: walletSettle,
                  ),
                ],
                notes: 'Wallet applied to ${widget.orderNumber}',
                visitId: widget.orderVisitId,
              ),
            );
        walletSaved = true;
        if (!mounted) return;
        if (walletResult.isPendingReview && amount <= 0.001) {
          await presentCollectionAcknowledgement(
            context,
            walletResult.acknowledgement,
          );
        }
      }
      if (amount > 0.001 ||
          (discountOnCash > 0.001 && walletApplied <= 0.001)) {
        final settleAmount = amount + discountOnCash;
        final allocation = PaymentAllocationInput(
          orderId: widget.orderId,
          amount: settleAmount,
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
                  allocations: [
                    PaymentAllocationInput(
                      orderId: widget.orderId,
                      amount: amount,
                    ),
                  ],
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
                  discountAmount: discountOnCash,
                  method: _method,
                  allocations: [allocation],
                  notes: discountOnCash > 0.001 && amount <= 0.001
                      ? 'Discount on ${widget.orderNumber}'
                      : 'Collected against ${widget.orderNumber}',
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
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = walletSaved
            ? 'Wallet was applied. The rest could not be saved. ${error.message}'
            : error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = walletSaved
            ? 'Wallet was applied. The rest could not be saved.'
            : 'Unable to record this collection.';
      });
    } finally {
      SelloActivity.end();
    }
  }

  Future<void> _saveExistingCheque() async {
    final match = _match;
    if (match == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    SelloActivity.begin();
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
    } finally {
      SelloActivity.end();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final outstandingMoney = _money(widget.outstanding);
    final match = _match;
    final canDiscount = _discountAllowed();
    // Keep Sales settings subscribed so the discount field appears when loaded.
    ref.watch(currentRoleProvider);
    ref.watch(selloCompanySettingsProvider);
    ref.watch(companySettingsProvider);
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
              if (_showWallet) ...[
                const SizedBox(height: 16),
                SelloTextField(
                  controller: _wallet,
                  label: 'Apply from wallet',
                  helperText: '${_money(_walletAvailable)} available',
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => setState(() {
                    _error = null;
                    _syncSettlementToCeiling(trimWallet: true);
                  }),
                ),
              ],
              const SizedBox(height: 16),
              SelloTextField(
                controller: _amount,
                label: _showWallet ? 'Amount still to receive' : 'Amount received',
                required: !_showWallet ||
                    _walletApplied + _resolvedDiscount + 0.001 <
                        _collectableNow,
                enabled: !_usingExisting && !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
              ),
              if (canDiscount) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelloTextField(
                        controller: _discountAmount,
                        label: 'Discount amount',
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        onChanged: (_) => setState(() {
                          _error = null;
                          _syncSettlementToCeiling();
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SelloTextField(
                        controller: _discountPercent,
                        label: 'Discount %',
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        onChanged: (_) => setState(() {
                          _error = null;
                          _syncSettlementToCeiling();
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use amount, percent, or both. Percent applies first to the '
                  'outstanding, then the amount. Reduces outstanding without '
                  'collecting that money.',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textTertiary,
                  ),
                ),
                if (_resolvedDiscount > 0.001) ...[
                  const SizedBox(height: 12),
                  _SettlementSummary(
                    currencySymbol: widget.currencySymbol,
                    outstanding: _collectableNow,
                    discount: _resolvedDiscount,
                    discountPercent: _discountPercentValue,
                    discountAmount: _discountAmountValue,
                    walletApplied: _showWallet ? _walletApplied : 0,
                    cashReceived: _parsedAmount ?? 0,
                  ),
                ],
              ],
              const SizedBox(height: 18),
              Text(
                _showWallet && _walletApplied > 0.001
                    ? 'How is the rest being received?'
                    : 'How is this amount being received?',
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
                              if (method == PaymentMethod.cheque) {
                                _clearDiscount();
                              }
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

/// Clear money math once a collection discount is entered.
class _SettlementSummary extends StatelessWidget {
  const _SettlementSummary({
    required this.currencySymbol,
    required this.outstanding,
    required this.discount,
    required this.discountPercent,
    required this.discountAmount,
    required this.walletApplied,
    required this.cashReceived,
  });

  final String currencySymbol;
  final num outstanding;
  final num discount;
  final num discountPercent;
  final num discountAmount;
  final num walletApplied;
  final num cashReceived;

  String _money(num value) =>
      SelloFormatters.currency(value, symbol: currencySymbol);

  String? get _discountDetail {
    final capped = discountAmount > discount + 0.001;
    final parts = <String>[];
    if (discountPercent > 0.001) {
      final pct = discountPercent == discountPercent.roundToDouble()
          ? discountPercent.toStringAsFixed(0)
          : discountPercent.toString();
      parts.add('$pct% of outstanding');
    }
    if (discountAmount > 0.001 &&
        (discountPercent > 0.001 || capped)) {
      parts.add(_money(discountAmount));
    }
    if (capped) {
      parts.add('capped to outstanding');
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final moneyReceived = walletApplied + cashReceived;
    final settles = moneyReceived + discount;
    final remaining = outstanding - settles;
    final remainingClamped = remaining < 0 ? 0 : remaining;
    final rows = <Widget>[
      _SummaryRow(
        label: 'Discount',
        value: '− ${_money(discount)}',
        detail: _discountDetail,
      ),
    ];
    if (walletApplied > 0.001) {
      rows.addAll([
        const SizedBox(height: 8),
        _SummaryRow(
          label: 'From wallet',
          value: _money(walletApplied),
        ),
      ]);
    }
    if (cashReceived > 0.001 || walletApplied <= 0.001) {
      rows.addAll([
        const SizedBox(height: 8),
        _SummaryRow(
          label: walletApplied > 0.001
              ? 'Cash still received'
              : 'Amount received',
          value: _money(cashReceived),
        ),
      ]);
    }
    rows.addAll([
      const SizedBox(height: 8),
      const Divider(height: 1),
      const SizedBox(height: 8),
      _SummaryRow(
        label: 'Total applied',
        value: _money(settles),
        emphasize: true,
      ),
      const SizedBox(height: 8),
      _SummaryRow(
        label: 'Outstanding left',
        value: _money(remainingClamped),
      ),
    ]);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.outlinePanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.detail,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final String? detail;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: emphasize ? 13 : 12.5,
                  fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
                  color: emphasize
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(
                  detail!,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11.5,
                    height: 1.3,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: emphasize ? 15 : 13.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
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
