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
        VisitPaymentArrangement.paidToday => 'Collect payment now',
        VisitPaymentArrangement.creditSale => 'On account',
        VisitPaymentArrangement.chequeReceived =>
          'Customer intends to pay by cheque',
        VisitPaymentArrangement.chequeCollectionScheduled =>
          'Customer will give the cheque later',
        VisitPaymentArrangement.noneYet => 'Settle later',
      };

  /// Offers Record cheque after checkout. Saving the form creates the ledger
  /// row; skipping does not.
  bool get opensRecordCheque => this == VisitPaymentArrangement.chequeReceived;

  /// Optional expected-around date for cheque-later (informational only).
  bool get allowsOptionalExpectedDate =>
      this == VisitPaymentArrangement.chequeCollectionScheduled;
}
