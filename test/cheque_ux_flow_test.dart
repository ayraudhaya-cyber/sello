import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/payments/application/cheque_lifecycle.dart';
import 'package:sello/shared/data/sri_lanka_banks.dart';
import 'package:sello/shared/models/cheque_source.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/customer_summary.dart';
import 'package:sello/shared/models/customer_type.dart';
import 'package:sello/shared/models/payment_summary.dart';

void main() {
  CustomerSummary customer({
    String name = 'Rocky Traders',
    String? phone = '0771234567',
    String? code = 'C-41',
  }) {
    return CustomerSummary(
      id: 'cu1',
      companyId: 'co1',
      name: name,
      customerType: CustomerType.retail,
      creditAllowed: true,
      creditLimit: 0,
      openingBalance: 0,
      outstandingBalance: 100000,
      walletBalance: 0,
      isActive: true,
      phone: phone,
      code: code,
    );
  }

  ChequeSummary cheque({
    required ChequeStatus status,
    ChequeSource source = ChequeSource.sello,
    String? paymentId,
    DateTime? balanceAppliedAt,
    num appliedArAmount = 0,
  }) {
    return ChequeSummary(
      id: 'ch1',
      companyId: 'co1',
      customerId: 'cu1',
      employeeId: 'e1',
      chequeNumberLabel: 'CHEQ-1',
      amount: 40000,
      bankName: 'Hatton National Bank',
      chequeNumber: '9911',
      holderName: 'Rocky Traders',
      chequeDate: DateTime(2026, 9, 20),
      status: status,
      source: source,
      paymentId: paymentId,
      appliedArAmount: appliedArAmount,
      createdAt: DateTime.utc(2026, 9, 13),
      balanceAppliedAt: balanceAppliedAt,
    );
  }

  ReceivableOrder order({
    required String id,
    required num remaining,
  }) {
    return ReceivableOrder(
      id: id,
      orderNumber: 'ORD-$id',
      total: remaining,
      amountPaid: 0,
      orderedAt: DateTime.utc(2026, 9, 1),
    );
  }

  group('inline customer search', () {
    test('matches customer name', () {
      expect(matchesCustomerSearch(customer(), 'rocky'), isTrue);
      expect(matchesCustomerSearch(customer(), 'nope'), isFalse);
    });

    test('matches phone', () {
      expect(matchesCustomerSearch(customer(), '07712'), isTrue);
      expect(matchesCustomerSearch(customer(), '011'), isFalse);
    });
  });

  group('default holder from customer', () {
    test('empty holder uses the selected customer name', () {
      expect(
        defaultChequeHolderName(
          currentHolder: '',
          selectedCustomerName: 'Rocky Traders',
        ),
        'Rocky Traders',
      );
    });

    test('changing customer updates a still-defaulted holder', () {
      expect(
        defaultChequeHolderName(
          currentHolder: 'Rocky Traders',
          selectedCustomerName: 'Nimal Stores',
          previousCustomerName: 'Rocky Traders',
        ),
        'Nimal Stores',
      );
    });

    test('an edited holder is preserved', () {
      expect(
        defaultChequeHolderName(
          currentHolder: 'Director / Rocky',
          selectedCustomerName: 'Nimal Stores',
          previousCustomerName: 'Rocky Traders',
        ),
        'Director / Rocky',
      );
    });
  });

  group('record cheque in-hand vs awaiting', () {
    test('awaiting collection does not mark collected or allocate', () {
      final input = CreateChequeInput(
        customerId: 'cu1',
        amount: 40000,
        bankName: 'Hatton National Bank',
        chequeNumber: '9911',
        holderName: 'Rocky Traders',
        chequeDate: DateTime(2026, 9, 20),
        markCollected: false,
      );
      expect(input.markCollected, isFalse);
      expect(input.collectionDate, isNull);
      expect(input.allocations, isEmpty);
    });

    test('in-hand cheque is recorded as collected with allocations', () {
      final input = CreateChequeInput(
        customerId: 'cu1',
        amount: 40000,
        bankName: 'Hatton National Bank',
        chequeNumber: '9911',
        holderName: 'Rocky Traders',
        chequeDate: DateTime(2026, 9, 20),
        collectionDate: DateTime(2026, 9, 30),
        markCollected: true,
        allocations: const [
          PaymentAllocationInput(orderId: 'o1', amount: 40000),
        ],
      );
      expect(input.markCollected, isTrue);
      expect(input.collectionDate, isNotNull);
      expect(input.allocations, isNotEmpty);
    });
  });

  group('collect allocation', () {
    test('already-allocated cheque does not prompt or rebuild allocations', () {
      final allocated = cheque(
        status: ChequeStatus.awaitingCollection,
        paymentId: 'pay-1',
        appliedArAmount: 40000,
      );
      expect(chequeCollectPreservesExistingAllocation(allocated), isTrue);
      expect(chequeCollectShouldPromptAllocation(allocated), isFalse);
      expect(
        allocationsForCollect(
          cheque: allocated,
          receivables: [order(id: 'o1', remaining: 40000)],
        ),
        isEmpty,
      );
    });

    test('unallocated cheque still FIFO-allocates outstanding orders', () {
      final awaiting = cheque(status: ChequeStatus.awaitingCollection);
      expect(chequeCollectPreservesExistingAllocation(awaiting), isFalse);
      expect(chequeCollectShouldPromptAllocation(awaiting), isFalse);
      final allocations = allocationsForCollect(
        cheque: awaiting,
        receivables: [
          order(id: 'o1', remaining: 25000),
          order(id: 'o2', remaining: 30000),
        ],
      );
      expect(allocations, hasLength(2));
      expect(allocations.first.orderId, 'o1');
      expect(allocations.first.amount, 25000);
      expect(allocations.last.orderId, 'o2');
      expect(allocations.last.amount, 15000);
    });

    test('unallocated cheque with no receivables uses empty allocations', () {
      final awaiting = cheque(status: ChequeStatus.awaitingCollection);
      expect(
        allocationsForCollect(cheque: awaiting, receivables: const []),
        isEmpty,
      );
    });
  });

  group('next lifecycle action', () {
    const can = (collect: true, manage: true);

    test('status words stay simple', () {
      expect(ChequeStatus.awaitingCollection.shortLabel, 'Waiting to receive');
      expect(ChequeStatus.collected.shortLabel, 'In hand');
      expect(ChequeStatus.deposited.shortLabel, 'At the bank');
      expect(ChequeStatus.cleared.shortLabel, 'Bank paid');
      expect(ChequeStatus.bounced.shortLabel, 'Bank returned');
    });

    test('status hover hints say when each status applies', () {
      expect(
        ChequeStatus.awaitingCollection.helpText,
        'The customer has not given you this cheque yet.',
      );
      expect(
        ChequeStatus.collected.helpText,
        'You have the cheque. It is not at the bank yet.',
      );
      expect(
        ChequeStatus.deposited.helpText,
        'The cheque is at your bank. Waiting for the bank to pay it.',
      );
      expect(
        ChequeStatus.cleared.helpText,
        'The bank paid this cheque. The money is in.',
      );
      expect(
        ChequeStatus.bounced.helpText,
        'The bank sent this cheque back unpaid.',
      );
    });

    test('status action hover hints say when to tap', () {
      expect(
        chequeForwardActionHint(ChequeForwardAction.collect),
        'Use this when the customer has given you the cheque.',
      );
      expect(
        chequeForwardActionHint(ChequeForwardAction.deposit),
        'Use this after you take the cheque to your bank.',
      );
      expect(
        chequeForwardActionHint(ChequeForwardAction.clear),
        'Use this when the bank has paid the cheque into your account.',
      );
      expect(
        chequeBounceActionHint,
        'Use this if the bank sent the cheque back unpaid.',
      );
      expect(
        chequeCancelActionHint,
        'Use this if this cheque will not be used.',
      );
    });

    test('waiting to receive shows Mark received only', () {
      final next = chequeNextForwardAction(
        cheque: cheque(status: ChequeStatus.awaitingCollection),
        canCollect: can.collect,
        canManageClearance: can.manage,
      );
      expect(next, ChequeForwardAction.collect);
      expect(chequeForwardActionLabel(next!), 'Mark received');
    });

    test('collected pending approval shows Approve, not Send to bank', () {
      final pending = cheque(status: ChequeStatus.collected);
      final next = chequeNextForwardAction(
        cheque: pending,
        canCollect: can.collect,
        canManageClearance: can.manage,
      );
      expect(pending.canDeposit, isFalse);
      expect(next, ChequeForwardAction.approve);
    });

    test('collected and applied shows Send to bank', () {
      final next = chequeNextForwardAction(
        cheque: cheque(
          status: ChequeStatus.collected,
          balanceAppliedAt: DateTime.utc(2026, 9, 13),
        ),
        canCollect: can.collect,
        canManageClearance: can.manage,
      );
      expect(next, ChequeForwardAction.deposit);
      expect(chequeForwardActionLabel(next!), 'Take to bank');
    });

    test('deposited shows Clear', () {
      final next = chequeNextForwardAction(
        cheque: cheque(
          status: ChequeStatus.deposited,
          balanceAppliedAt: DateTime.utc(2026, 9, 13),
        ),
        canCollect: can.collect,
        canManageClearance: can.manage,
      );
      expect(next, ChequeForwardAction.clear);
      expect(chequeForwardActionLabel(next!), 'Bank paid it');
    });

    test('invalid lifecycle actions are not shown', () {
      final bounced = cheque(status: ChequeStatus.bounced);
      expect(
        chequeNextForwardAction(
          cheque: bounced,
          canCollect: true,
          canManageClearance: true,
        ),
        isNull,
      );
      expect(bounced.canCollect, isFalse);
      expect(bounced.canDeposit, isFalse);
      expect(bounced.status.canClear, isFalse);

      final awaiting = cheque(status: ChequeStatus.awaitingCollection);
      expect(
        chequeNextForwardAction(
          cheque: awaiting,
          canCollect: false,
          canManageClearance: true,
        ),
        isNull,
      );
    });
  });

  group('confirmations', () {
    test('Collect Deposit Clear skip confirmation', () {
      expect(
        chequeForwardActionNeedsConfirmation(ChequeForwardAction.collect),
        isFalse,
      );
      expect(
        chequeForwardActionNeedsConfirmation(ChequeForwardAction.deposit),
        isFalse,
      );
      expect(
        chequeForwardActionNeedsConfirmation(ChequeForwardAction.clear),
        isFalse,
      );
    });

    test('Approve still requires confirmation', () {
      expect(
        chequeForwardActionNeedsConfirmation(ChequeForwardAction.approve),
        isTrue,
      );
    });

    test('Bounce and Cancel remain confirmed', () {
      expect(chequeDestructiveActionRequiresConfirmation('bounce'), isTrue);
      expect(chequeDestructiveActionRequiresConfirmation('cancel'), isTrue);
      expect(chequeDestructiveActionRequiresConfirmation('collect'), isFalse);
      expect(chequeConfirmedDestructiveActions, {'bounce', 'cancel'});
    });
  });

  group('existing historical cheque', () {
    test('does not affect balances', () {
      final existing = cheque(
        status: ChequeStatus.collected,
        source: ChequeSource.existing,
      );
      expect(existing.isTrackingOnly, isTrue);
      expect(existing.reducesOutstanding, isFalse);
      expect(existing.canDeposit, isFalse);
    });
  });

  group('batch deposit', () {
    test('only collected cheques with applied balances are eligible', () {
      final awaiting = cheque(status: ChequeStatus.awaitingCollection);
      final pending = cheque(status: ChequeStatus.collected);
      final collected = cheque(
        status: ChequeStatus.collected,
        balanceAppliedAt: DateTime.utc(2026, 9, 13),
      );
      expect(chequeEligibleForBatchDeposit(awaiting), isFalse);
      expect(chequeEligibleForBatchDeposit(pending), isFalse);
      expect(chequeEligibleForBatchDeposit(collected), isTrue);
    });
  });

  group('Sri Lankan bank autocomplete', () {
    test('aliases and names continue to match', () {
      expect(filterSriLankaBanks('hnb'), ['Hatton National Bank']);
      expect(filterSriLankaBanks('boc'), contains('Bank of Ceylon'));
      expect(filterSriLankaBanks('ntb'), ['Nations Trust Bank']);
      expect(filterSriLankaBanks('Hatton'), contains('Hatton National Bank'));
    });

    test('custom bank names remain allowed', () {
      expect(filterSriLankaBanks('Village Co-op Bank'), isEmpty);
    });
  });

  group('cheque details related documents', () {
    PaymentAllocation alloc({
      required String orderId,
      String? orderNumber,
      num amount = 40000,
    }) {
      return PaymentAllocation(
        id: 'a-$orderId',
        orderId: orderId,
        amount: amount,
        orderNumber: orderNumber,
      );
    }

    test('shows related order number when allocation exists', () {
      final related = chequeRelatedDocuments(
        paymentNumber: 'PAY-20260930-0004',
        allocations: [
          alloc(orderId: 'o1', orderNumber: 'INV-20260930-0012'),
        ],
      );
      expect(related.orderNumbers, ['INV-20260930-0012']);
      expect(related.paymentNumber, 'PAY-20260930-0004');
      expect(related.isEmpty, isFalse);
    });

    test('shows related payment identifier when payment exists', () {
      final related = chequeRelatedDocuments(
        paymentNumber: 'PAY-9',
        allocations: const [],
      );
      expect(related.paymentNumber, 'PAY-9');
      expect(related.orderNumbers, isEmpty);
    });

    test('lists multiple allocated order numbers without duplicates', () {
      final related = chequeRelatedDocuments(
        paymentNumber: 'PAY-1',
        allocations: [
          alloc(orderId: 'o1', orderNumber: 'INV-1', amount: 10000),
          alloc(orderId: 'o2', orderNumber: 'INV-2', amount: 15000),
          alloc(orderId: 'o1', orderNumber: 'INV-1', amount: 5000),
        ],
      );
      expect(related.orderNumbers, ['INV-1', 'INV-2']);
    });

    test('does not display empty or raw UUID values', () {
      const uuid = '11111111-2222-3333-4444-555555555555';
      expect(chequeUserFacingLabel(uuid), isNull);
      expect(chequeUserFacingLabel('  '), isNull);
      expect(chequeUserFacingLabel(null), isNull);
      final related = chequeRelatedDocuments(
        paymentNumber: uuid,
        allocations: [
          alloc(orderId: uuid, orderNumber: uuid),
          alloc(orderId: 'o2', orderNumber: ''),
        ],
      );
      expect(related.paymentNumber, isNull);
      expect(related.orderNumbers, isEmpty);
      expect(related.isEmpty, isTrue);
    });

    test('pending approval still shows payment and order relationship', () {
      final pending = cheque(
        status: ChequeStatus.collected,
        paymentId: 'pay-pending',
      );
      expect(pending.isPendingApproval, isTrue);
      expect(pending.appliedArAmount, 0);
      final related = chequeRelatedDocuments(
        paymentNumber: 'PAY-20260930-0008',
        allocations: [
          alloc(orderId: 'o1', orderNumber: 'INV-20260930-0012'),
        ],
      );
      expect(related.paymentNumber, 'PAY-20260930-0008');
      expect(related.orderNumbers, ['INV-20260930-0012']);
    });
  });

  group('visit cheque prefers the newly created order', () {
    test('today’s order is allocated before older receivables', () {
      final older = order(id: 'older', remaining: 50000);
      final today = order(id: 'today', remaining: 40000);
      final allocations = fifoChequeAllocations(
        amount: 40000,
        orders: [older, today],
        preferredOrderId: 'today',
      );
      expect(allocations, hasLength(1));
      expect(allocations.single.orderId, 'today');
      expect(allocations.single.amount, 40000);
    });

    test('older outstanding orders do not consume the cheque first', () {
      final older = order(id: 'older', remaining: 80000);
      final today = order(id: 'today', remaining: 25000);
      final allocations = fifoChequeAllocations(
        amount: 25000,
        orders: [older, today],
        preferredOrderId: today.id,
      );
      expect(allocations.single.orderId, 'today');
      expect(allocations.any((a) => a.orderId == 'older'), isFalse);
    });

    test('excess amount follows FIFO on remaining receivables', () {
      final older = order(id: 'older', remaining: 30000);
      final today = order(id: 'today', remaining: 40000);
      final later = order(id: 'later', remaining: 20000);
      final allocations = fifoChequeAllocations(
        amount: 55000,
        orders: [older, today, later],
        preferredOrderId: 'today',
      );
      expect(allocations.map((a) => a.orderId), ['today', 'older']);
      expect(allocations.first.amount, 40000);
      expect(allocations.last.amount, 15000);
    });

    test('without a preferred order, FIFO still starts at the oldest', () {
      final older = order(id: 'older', remaining: 40000);
      final today = order(id: 'today', remaining: 40000);
      final allocations = fifoChequeAllocations(
        amount: 40000,
        orders: [older, today],
      );
      expect(allocations.single.orderId, 'older');
    });

    test('default amount is the preferred order remaining', () {
      expect(
        preferredChequeDefaultAmount(
          orders: [
            order(id: 'older', remaining: 80000),
            order(id: 'today', remaining: 40000),
          ],
          preferredOrderId: 'today',
        ),
        40000,
      );
    });
  });

  group('manual outstanding order selection', () {
    test('checking an order covers its remaining balance', () {
      final today = order(id: 'today', remaining: 31640);
      expect(chequeOrderSelectionAmount(today), 31640);
    });

    test('multiple selected orders keep their remaining amounts', () {
      final first = order(id: 'a', remaining: 31640);
      final second = order(id: 'b', remaining: 53200);
      expect(chequeOrderSelectionAmount(first), 31640);
      expect(chequeOrderSelectionAmount(second), 53200);
    });

    test('typed amount cannot exceed the order remaining', () {
      expect(
        clampChequeOrderAllocation(amount: 50000, remaining: 31640),
        31640,
      );
      expect(
        clampChequeOrderAllocation(amount: 10000, remaining: 31640),
        10000,
      );
      expect(
        clampChequeOrderAllocation(amount: 0, remaining: 31640),
        0,
      );
    });

    test('rejects allocations that exceed the cheque amount', () {
      final orders = [
        order(id: 'a', remaining: 31640),
        order(id: 'b', remaining: 53200),
      ];
      expect(
        chequeManualAllocationError(
          chequeAmount: 31640,
          allocations: {'a': 31640, 'b': 53200},
          orders: orders,
        ),
        'Allocated orders exceed the cheque amount.',
      );
    });

    test('rejects an amount larger than the order remaining', () {
      final orders = [order(id: 'a', remaining: 31640)];
      expect(
        chequeManualAllocationError(
          chequeAmount: 50000,
          allocations: {'a': 40000},
          orders: orders,
        ),
        'Allocation exceeds remaining on ORD-a.',
      );
    });

    test('allows a partial amount on a selected order', () {
      final orders = [order(id: 'a', remaining: 31640)];
      expect(
        chequeManualAllocationError(
          chequeAmount: 31640,
          allocations: {'a': 10000},
          orders: orders,
        ),
        isNull,
      );
    });
  });

  group('existing order-collection cheque flow', () {
    test('still allocates only to the selected order', () {
      const selected = PaymentAllocationInput(orderId: 'ord-existing', amount: 18000);
      final input = CreateChequeInput(
        customerId: 'cu1',
        amount: 18000,
        bankName: 'Hatton National Bank',
        chequeNumber: '4411',
        holderName: 'Rocky Traders',
        chequeDate: DateTime(2026, 9, 20),
        collectionDate: DateTime(2026, 9, 30),
        markCollected: true,
        allocations: const [selected],
        notes: 'Collected against INV-9',
      );
      expect(input.allocations, hasLength(1));
      expect(input.allocations.single.orderId, 'ord-existing');
      expect(input.markCollected, isTrue);
      expect(input.visitId, isNull);
    });
  });
}
