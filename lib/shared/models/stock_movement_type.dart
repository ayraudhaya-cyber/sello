enum StockMovementType {
  purchase,
  sale,
  damage,
  returned,
  correction,
  transfer,
  adjustment;

  String get label => switch (this) {
        StockMovementType.purchase => 'Purchase / GRN',
        StockMovementType.sale => 'Order completed',
        StockMovementType.damage => 'Damage',
        StockMovementType.returned => 'Return',
        StockMovementType.correction => 'Stock correction',
        StockMovementType.transfer => 'Transfer',
        StockMovementType.adjustment => 'Manual adjustment',
      };

  /// DB value — `return` is reserved in SQL, stored as `return`.
  String get dbValue => switch (this) {
        StockMovementType.returned => 'return',
        _ => name,
      };

  bool get increasesStock =>
      this == StockMovementType.purchase ||
      this == StockMovementType.returned ||
      this == StockMovementType.correction ||
      this == StockMovementType.adjustment ||
      this == StockMovementType.transfer;

  /// Reasons offered in the Hub adjust dialog.
  static const adjustReasons = <StockMovementType>[
    StockMovementType.purchase,
    StockMovementType.damage,
    StockMovementType.returned,
    StockMovementType.correction,
    StockMovementType.transfer,
    StockMovementType.adjustment,
  ];

  static StockMovementType fromDb(String? value) {
    return switch (value) {
      'purchase' => StockMovementType.purchase,
      'sale' => StockMovementType.sale,
      'damage' => StockMovementType.damage,
      'return' => StockMovementType.returned,
      'correction' => StockMovementType.correction,
      'transfer' => StockMovementType.transfer,
      'adjustment' => StockMovementType.adjustment,
      _ => StockMovementType.adjustment,
    };
  }
}

enum StockStatusFilter {
  all,
  inStock,
  lowStock,
  outOfStock,
  negativeStock,
  recentlyUpdated,
  archived,
}

enum StockStatus {
  healthy,
  low,
  out,
  archived;

  String get label => switch (this) {
        StockStatus.healthy => 'In stock',
        StockStatus.low => 'Low stock',
        StockStatus.out => 'Out of stock',
        StockStatus.archived => 'Archived',
      };
}
