/// How the buyer intends to settle during a customer visit.
///
/// [paidToday] opens the receive-payment dialog.
/// [chequeReceived] opens [RecordChequeDialog] for an actual cheque in hand.
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
        VisitPaymentArrangement.chequeReceived => 'Cheque in hand',
        VisitPaymentArrangement.chequeCollectionScheduled =>
          'Customer will give the cheque later',
        VisitPaymentArrangement.noneYet => 'Settle later',
      };

  /// Opens Record cheque and creates a cheque ledger row.
  bool get opensRecordCheque => this == VisitPaymentArrangement.chequeReceived;

  /// Optional expected-around date for cheque-later (informational only).
  bool get allowsOptionalExpectedDate =>
      this == VisitPaymentArrangement.chequeCollectionScheduled;
}
