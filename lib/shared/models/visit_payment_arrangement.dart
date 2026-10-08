/// How the buyer intends to settle during a customer visit.
///
/// [paidToday] opens the receive-payment dialog.
/// [chequeReceived] is collection intent only. Record cheque is offered next
/// and may be skipped — no ledger row until the instrument is actually saved.
/// [chequeCollectionScheduled] records intent only — no cheque ledger row.
enum VisitPaymentArrangement {
  paidToday,
  creditSale,
  chequeReceived,
  chequeCollectionScheduled,
  noneYet;

  String get label => switch (this) {
        VisitPaymentArrangement.paidToday => 'Paid today',
        VisitPaymentArrangement.creditSale => 'Credit',
        VisitPaymentArrangement.chequeReceived => 'Cheque received',
        VisitPaymentArrangement.chequeCollectionScheduled => 'Cheque later',
        VisitPaymentArrangement.noneYet => 'Arrange later',
      };

  String get helpText => switch (this) {
        VisitPaymentArrangement.paidToday =>
          'Collect money after you submit. This new order is added to Outstanding when goods are delivered.',
        VisitPaymentArrangement.creditSale =>
          'Customer will pay later. Outstanding for this order updates when goods are delivered, not when you submit.',
        VisitPaymentArrangement.chequeReceived =>
          'The order is saved unpaid. Recording the cheque is optional — skip and enter it later from the order.',
        VisitPaymentArrangement.chequeCollectionScheduled =>
          'No cheque is created now. Record it later from the order when the customer gives it.',
        VisitPaymentArrangement.noneYet =>
          'The order is saved. Collect payment later from the order.',
      };

  /// Offers Record cheque after checkout. Saving the form creates the ledger
  /// row; skipping does not.
  bool get opensRecordCheque => this == VisitPaymentArrangement.chequeReceived;

  /// Optional expected-around date for cheque-later (informational only).
  bool get allowsOptionalExpectedDate =>
      this == VisitPaymentArrangement.chequeCollectionScheduled;
}
