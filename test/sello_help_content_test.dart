import 'package:flutter_test/flutter_test.dart';
import 'package:sello/features/help/sello_help_content.dart';
import 'package:sello/features/visits/application/visit_checkout_payment_rules.dart';
import 'package:sello/shared/models/visit_payment_arrangement.dart';

void main() {
  test('Help covers the questions customers already ask', () {
    final ids = SelloHelpContent.topics.map((topic) => topic.id).toSet();
    expect(
      ids,
      containsAll([
        'collect-money',
        'outstanding-after-order',
        'wrong-sales-rep',
        'sales-cheque-in-hub',
        'existing-cheque',
      ]),
    );
    expect(SelloHelpContent.topics, isNotEmpty);
    for (final topic in SelloHelpContent.topics) {
      expect(topic.title, isNotEmpty);
      expect(topic.steps, isNotEmpty);
    }
  });

  test('Credit and cheque-later copy say outstanding waits for delivery', () {
    expect(
      VisitPaymentArrangement.creditSale.helpText.toLowerCase(),
      contains('delivered'),
    );
    expect(
      VisitPaymentArrangement.chequeReceived.helpText.toLowerCase(),
      contains('optional'),
    );
  });

  test('Visit saved message for credit does not imply outstanding already moved', () {
    expect(
      VisitCheckoutPaymentRules.visitSavedMessage(
        arrangement: VisitPaymentArrangement.creditSale,
        hasLines: true,
        skippedOptionalCheque: false,
      ),
      'Order saved. Outstanding updates when goods are delivered.',
    );
    expect(
      VisitCheckoutPaymentRules.visitSavedMessage(
        arrangement: VisitPaymentArrangement.chequeReceived,
        hasLines: true,
        skippedOptionalCheque: true,
      ),
      'Visit saved. Record the cheque later from the order.',
    );
    expect(
      VisitCheckoutPaymentRules.visitSavedMessage(
        arrangement: VisitPaymentArrangement.paidToday,
        hasLines: true,
        skippedOptionalCheque: false,
      ),
      'Visit saved.',
    );
  });
}
