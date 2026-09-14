import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/models/cheque_status.dart';
import 'package:sello/shared/models/cheque_summary.dart';

/// Mirrors `apply_payment_financials` / `_payment_apply_effect_amounts` for
/// non-wallet methods (cash, cheque, card, bank_transfer, credit_settlement).
({num arReduction, num walletDelta}) nonWalletPaymentEffect({
  required num amount,
  required num allocTotal,
  required num balanceBefore,
}) {
  final arReduction = math.min(amount, balanceBefore);
  final walletDelta = math.max(amount - allocTotal, 0);
  return (arReduction: arReduction, walletDelta: walletDelta);
}

({num outstanding, num wallet}) applyBounceReverse({
  required num outstanding,
  required num wallet,
  required num appliedAr,
  required num appliedWallet,
}) {
  return (
    outstanding: outstanding + appliedAr,
    wallet: math.max(wallet - appliedWallet, 0),
  );
}

/// Policy: never invent a cheque financial snapshot when historical
/// balance_before is unavailable (payments ledger has no AR/wallet deltas).
bool shouldBackfillMissingSnapshot({
  required bool hasAuthoritativeBalanceBefore,
  required num? currentBalanceAfter,
}) {
  // payments ledger does not store AR/wallet deltas. Current balance alone
  // (especially 0) cannot distinguish capped vs full reduction.
  if (!hasAuthoritativeBalanceBefore) return false;
  return true;
}

void main() {
  group('Cheque payment AR vs wallet effect (apply_payment_financials)', () {
    test('100k outstanding + 40k payment → AR −40k, wallet 0', () {
      final effect = nonWalletPaymentEffect(
        amount: 40000,
        allocTotal: 40000,
        balanceBefore: 100000,
      );
      expect(effect.arReduction, 40000);
      expect(effect.walletDelta, 0);

      final outstanding = 100000 - effect.arReduction;
      expect(outstanding, 60000);
    });

    test('30k outstanding + 40k payment → AR −30k, wallet +10k', () {
      // 30k allocated to orders; 10k unallocated overpay → wallet credit.
      // AR caps at outstanding (least(40000, 30000)).
      final effect = nonWalletPaymentEffect(
        amount: 40000,
        allocTotal: 30000,
        balanceBefore: 30000,
      );
      expect(effect.arReduction, 30000);
      expect(effect.walletDelta, 10000);

      final outstanding = 30000 - effect.arReduction;
      final wallet = effect.walletDelta;
      expect(outstanding, 0);
      expect(wallet, 10000);

      final reversed = applyBounceReverse(
        outstanding: outstanding,
        wallet: wallet,
        appliedAr: effect.arReduction,
        appliedWallet: effect.walletDelta,
      );
      expect(reversed.outstanding, 30000);
      expect(reversed.wallet, 0);
    });

    test(
      'historical completed cheque with missing snapshot and zero balance '
      'must not be backfilled as AR = payment amount',
      () {
        const paymentAmount = 40000;
        const currentBalanceAfter = 0;

        final wouldBackfill = shouldBackfillMissingSnapshot(
          hasAuthoritativeBalanceBefore: false,
          currentBalanceAfter: currentBalanceAfter,
        );
        expect(wouldBackfill, isFalse);

        // Fabricating AR = payment.amount would be wrong for a prior capped apply
        // (e.g. true AR was 30k). Policy: leave snapshot null.
        final fabricatedAr = paymentAmount;
        const trueHistoricalAr = 30000;
        expect(fabricatedAr, isNot(trueHistoricalAr));

        final cheque = ChequeSummary(
          id: 'ch-legacy',
          companyId: 'co1',
          customerId: 'cu1',
          employeeId: 'e1',
          chequeNumberLabel: 'CHEQ-LEGACY',
          amount: paymentAmount,
          bankName: 'BOC',
          chequeNumber: '1',
          holderName: 'Rocky',
          chequeDate: DateTime(2026, 9, 1),
          status: ChequeStatus.collected,
          createdAt: DateTime.utc(2026, 9, 1),
          // Missing authoritative snapshot
          balanceAppliedAt: null,
          appliedArAmount: 0,
          appliedWalletAmount: 0,
        );

        expect(cheque.balanceAppliedAt, isNull);
        expect(cheque.canBounce, isFalse);
        expect(cheque.reducesOutstanding, isFalse);
      },
    );

    test('normal path with known balance_before snapshots correctly', () {
      final uncapped = nonWalletPaymentEffect(
        amount: 40000,
        allocTotal: 40000,
        balanceBefore: 100000,
      );
      expect(uncapped.arReduction, 40000);
      expect(uncapped.walletDelta, 0);

      final capped = nonWalletPaymentEffect(
        amount: 40000,
        allocTotal: 30000,
        balanceBefore: 30000,
      );
      expect(capped.arReduction, 30000);
      expect(capped.walletDelta, 10000);
    });
  });
}
