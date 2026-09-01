enum PaymentMethod {
  cash,
  card,
  bankTransfer,
  wallet,
  credit,
  creditSettlement;

  String get label => switch (this) {
        PaymentMethod.cash => 'Cash',
        PaymentMethod.card => 'Card',
        PaymentMethod.bankTransfer => 'Bank transfer',
        PaymentMethod.wallet => 'Wallet',
        PaymentMethod.credit => 'Credit',
        PaymentMethod.creditSettlement => 'Credit settlement',
      };

  String get dbValue => switch (this) {
        PaymentMethod.bankTransfer => 'bank_transfer',
        PaymentMethod.creditSettlement => 'credit_settlement',
        _ => name,
      };

  /// Methods used when recording a collection (not sale intent on an order).
  bool get isSettlementMethod =>
      this == PaymentMethod.cash ||
      this == PaymentMethod.card ||
      this == PaymentMethod.bankTransfer ||
      this == PaymentMethod.wallet ||
      this == PaymentMethod.creditSettlement;

  static const settlementMethods = <PaymentMethod>[
    PaymentMethod.cash,
    PaymentMethod.card,
    PaymentMethod.bankTransfer,
    PaymentMethod.wallet,
    PaymentMethod.creditSettlement,
  ];

  static PaymentMethod? fromDb(String? value) {
    return switch (value) {
      'cash' => PaymentMethod.cash,
      'card' => PaymentMethod.card,
      'bank_transfer' => PaymentMethod.bankTransfer,
      'wallet' => PaymentMethod.wallet,
      'credit' => PaymentMethod.credit,
      'credit_settlement' => PaymentMethod.creditSettlement,
      _ => null,
    };
  }
}
