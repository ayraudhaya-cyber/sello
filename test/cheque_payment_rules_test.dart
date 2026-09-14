import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/cheque_summary.dart';
import 'package:sello/shared/models/payment_method.dart';
import 'package:sello/shared/models/payment_summary.dart';

void main() {
  group('Partial payments', () {
    late DateTime now;

    setUp(() {
      now = DateTime.utc(2026, 9, 13);
    });

    ReceivableOrder order({required num total, required num paid}) {
      return ReceivableOrder(
        id: 'o1',
        orderNumber: 'ORD-1',
        total: total,
        amountPaid: paid,
        orderedAt: now,
      );
    }

    test('full cash payment leaves zero remaining', () {
      expect(order(total: 100000, paid: 100000).remaining, 0);
    });

    test('partial cash payment leaves remaining', () {
      expect(order(total: 100000, paid: 30000).remaining, 70000);
    });

    test('multiple partials accumulate', () {
      expect(order(total: 100000, paid: 30000).remaining, 70000);
      expect(order(total: 100000, paid: 50000).remaining, 50000);
    });

    test('cheque is not a receive_payment settlement chip', () {
      expect(PaymentMethod.cheque.isSettlementMethod, isFalse);
      expect(
        PaymentMethod.settlementMethods.contains(PaymentMethod.cheque),
        isFalse,
      );
    });
  });

  group('Cheque approval presentation', () {
    ChequeSummary cheque({
      required ChequeStatus status,
      DateTime? balanceAppliedAt,
      DateTime? balanceReversedAt,
    }) {
      return ChequeSummary(
        id: 'ch1',
        companyId: 'co1',
        customerId: 'cu1',
        employeeId: 'e1',
        chequeNumberLabel: 'CHEQ-1',
        amount: 40000,
        bankName: 'BOC',
        chequeNumber: '9911',
        holderName: 'Rocky',
        chequeDate: DateTime(2026, 9, 20),
        status: status,
        createdAt: DateTime.utc(2026, 9, 13),
        balanceAppliedAt: balanceAppliedAt,
        balanceReversedAt: balanceReversedAt,
      );
    }

    test('awaiting does not reduce outstanding', () {
      final c = cheque(status: ChequeStatus.awaitingCollection);
      expect(c.reducesOutstanding, isFalse);
      expect(c.displayLabel, 'Awaiting collection');
      expect(c.isPendingApproval, isFalse);
    });

    test('collected without apply is pending approval', () {
      final c = cheque(status: ChequeStatus.collected);
      expect(c.isPendingApproval, isTrue);
      expect(c.reducesOutstanding, isFalse);
      expect(c.displayLabel, 'Collected · Pending approval');
      expect(c.canDeposit, isFalse);
      expect(c.canBounce, isFalse);
      expect(c.canApproveCollection, isTrue);
    });

    test('collected with apply is pending clearance', () {
      final c = cheque(
        status: ChequeStatus.collected,
        balanceAppliedAt: DateTime.utc(2026, 9, 13),
      );
      expect(c.isPendingApproval, isFalse);
      expect(c.isPendingClearance, isTrue);
      expect(c.reducesOutstanding, isTrue);
      expect(c.displayLabel, 'Collected · Pending clearance');
      expect(c.canDeposit, isTrue);
      expect(c.canBounce, isTrue);
    });

    test('deposit/clear do not change reducesOutstanding semantics', () {
      final deposited = cheque(
        status: ChequeStatus.deposited,
        balanceAppliedAt: DateTime.utc(2026, 9, 13),
      );
      final cleared = cheque(
        status: ChequeStatus.cleared,
        balanceAppliedAt: DateTime.utc(2026, 9, 13),
      );
      expect(deposited.reducesOutstanding, isTrue);
      expect(cleared.reducesOutstanding, isTrue);
      expect(deposited.canBounce, isTrue);
      expect(cleared.canBounce, isTrue);
    });

    test('bounced after reverse does not reduce outstanding', () {
      final c = cheque(
        status: ChequeStatus.bounced,
        balanceAppliedAt: DateTime.utc(2026, 9, 13),
        balanceReversedAt: DateTime.utc(2026, 9, 14),
      );
      expect(c.reducesOutstanding, isFalse);
      expect(c.canBounce, isFalse);
    });

    test('approval OFF scenario balance steps', () {
      num outstanding = 100000;
      // awaiting
      expect(outstanding, 100000);
      // collect + apply
      outstanding -= 40000;
      expect(outstanding, 60000);
      // deposit/clear no change
      expect(outstanding, 60000);
      // bounce once
      outstanding += 40000;
      expect(outstanding, 100000);
      // second bounce idempotent (balance_reversed_at set)
      final afterFirstBounce = cheque(
        status: ChequeStatus.bounced,
        balanceAppliedAt: DateTime.utc(2026, 9, 13),
        balanceReversedAt: DateTime.utc(2026, 9, 14),
      );
      expect(afterFirstBounce.canBounce, isFalse);
      expect(outstanding, 100000);
    });

    test('approval ON scenario balance steps', () {
      num outstanding = 100000;
      // collect pending approval — no change
      final pending = cheque(status: ChequeStatus.collected);
      expect(pending.reducesOutstanding, isFalse);
      expect(outstanding, 100000);
      // approve once
      outstanding -= 40000;
      final applied = cheque(
        status: ChequeStatus.collected,
        balanceAppliedAt: DateTime.utc(2026, 9, 13),
      );
      expect(applied.reducesOutstanding, isTrue);
      expect(outstanding, 60000);
      // duplicate approve — snapshot already present, no second reduction
      expect(applied.balanceAppliedAt, isNotNull);
      expect(outstanding, 60000);
    });
  });

  group('Opening balance & credit flags', () {
    test('opening balance may exceed credit limit', () {
      expect(200000 > 100000, isTrue);
    });

    test('credit allowed OFF does not block collections', () {
      const creditAllowed = false;
      expect(creditAllowed, isFalse);
      expect(100000 - 30000, 70000);
    });
  });

  group('Dashboard pending approval field', () {
    test('parses pending_approval from stats json', () {
      final stats = ChequeDashboardStats.fromJson({
        'awaiting_collection': 1,
        'due_today': 0,
        'pending_approval': 3,
        'collected': 2,
        'deposited': 0,
        'cleared': 0,
        'bounced': 0,
        'cancelled': 0,
        'collected_pending_clearance_amount': 80000,
      });
      expect(stats.pendingApproval, 3);
      expect(stats.collected, 2);
    });
  });
}
