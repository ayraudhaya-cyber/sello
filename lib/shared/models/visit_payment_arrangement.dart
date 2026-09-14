/// How the buyer intends to settle during a customer visit.
///
/// Cash/card collections use [ReceivePaymentDialog]. Cheque arrangements use
/// [RecordChequeDialog] (awaiting or collected) against the cheques domain.
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
          'Come back for the cheque',
        VisitPaymentArrangement.noneYet => 'Settle later',
      };

  bool get schedulesFollowUp =>
      this == VisitPaymentArrangement.chequeCollectionScheduled;
}
