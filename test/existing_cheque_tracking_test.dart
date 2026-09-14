import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/models/cheque_source.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/cheque_summary.dart';

void main() {
  ChequeSummary cheque({
    required ChequeStatus status,
    ChequeSource source = ChequeSource.sello,
    String? paymentId,
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
      chequeDate: DateTime(2026, 9, 1),
      status: status,
      source: source,
      paymentId: paymentId,
      createdAt: DateTime.utc(2026, 9, 14),
      balanceAppliedAt: balanceAppliedAt,
      balanceReversedAt: balanceReversedAt,
    );
  }

  group('Existing cheque tracking-only presentation', () {
    test('existing awaiting is tracking-only and not pending approval', () {
      final c = cheque(
        status: ChequeStatus.awaitingCollection,
        source: ChequeSource.existing,
      );
      expect(c.isTrackingOnly, isTrue);
      expect(c.isPendingApproval, isFalse);
      expect(c.canApproveCollection, isFalse);
      expect(c.reducesOutstanding, isFalse);
      expect(c.displayLabel, 'Awaiting collection');
      expect(c.canCollect, isTrue);
    });

    test('existing collected is historical, not pending approval', () {
      final c = cheque(
        status: ChequeStatus.collected,
        source: ChequeSource.existing,
      );
      expect(c.isTrackingOnly, isTrue);
      expect(c.isPendingApproval, isFalse);
      expect(c.canApproveCollection, isFalse);
      expect(c.canDeposit, isFalse);
      expect(c.reducesOutstanding, isFalse);
      expect(c.displayLabel, 'Collected · Historical');
      expect(c.canBounce, isTrue);
    });

    test('existing deposited/cleared stay historical without payment', () {
      final deposited = cheque(
        status: ChequeStatus.deposited,
        source: ChequeSource.existing,
      );
      final cleared = cheque(
        status: ChequeStatus.cleared,
        source: ChequeSource.existing,
      );
      expect(deposited.displayLabel, 'Deposited · Historical');
      expect(cleared.displayLabel, 'Cleared · Historical');
      expect(deposited.reducesOutstanding, isFalse);
      expect(cleared.reducesOutstanding, isFalse);
      expect(deposited.canBounce, isTrue);
      expect(cleared.canBounce, isTrue);
    });

    test('existing awaiting collected in Sello becomes pending approval', () {
      final c = cheque(
        status: ChequeStatus.collected,
        source: ChequeSource.existing,
        paymentId: 'pay-1',
      );
      expect(c.isTrackingOnly, isFalse);
      expect(c.isPendingApproval, isTrue);
      expect(c.displayLabel, 'Collected · Pending approval');
      expect(c.canApproveCollection, isTrue);
      expect(c.canBounce, isFalse);
    });

    test('normal collected without apply remains pending approval', () {
      final c = cheque(status: ChequeStatus.collected);
      expect(c.source, ChequeSource.sello);
      expect(c.isPendingApproval, isTrue);
      expect(c.displayLabel, 'Collected · Pending approval');
    });

    test('CreateExistingChequeInput carries optional blank dates', () {
      final input = CreateExistingChequeInput(
        customerId: 'cu1',
        amount: 40000,
        bankName: 'BOC',
        chequeNumber: '9911',
        holderName: 'Rocky',
        chequeDate: DateTime(2026, 8, 1),
        status: ChequeStatus.deposited,
      );
      expect(input.collectionDate, isNull);
      expect(input.depositDate, isNull);
      expect(input.clearanceDate, isNull);
    });
  });
}
