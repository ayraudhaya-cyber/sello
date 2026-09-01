/// How the buyer intends to settle during a customer visit.
///
/// Maps onto existing payment / order methods where possible. Cheque collection
/// scheduling creates a follow-up planned visit via [VisitRepository.upsertVisit]
/// — it does not invent a parallel payment pipeline.
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
