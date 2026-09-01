enum PaymentStatus {
  unpaid,
  partial,
  paid,
  refunded;

  String get label => switch (this) {
        PaymentStatus.unpaid => 'Unpaid',
        PaymentStatus.partial => 'Partial',
        PaymentStatus.paid => 'Paid',
        PaymentStatus.refunded => 'Refunded',
      };

  String get dbValue => name;

  static PaymentStatus fromDb(String? value) {
    return switch (value) {
      'partial' => PaymentStatus.partial,
      'paid' => PaymentStatus.paid,
      'refunded' => PaymentStatus.refunded,
      _ => PaymentStatus.unpaid,
    };
  }
}
