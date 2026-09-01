/// When inventory quantity is reduced for a sale.
///
/// Stock deduction today still runs inside `complete_sales_order`. This policy
/// is the product seam so businesses can choose timing without hardcoding it in
/// field UX. Wire RPC branches when the setting is persisted and enforced.
enum InventoryMovementPolicy {
  /// Hold stock when the order is saved (draft or confirmed).
  reserveOnOrder,

  /// Reduce stock when an owner/manager approves the order.
  deductOnApproval,

  /// Reduce stock when the order is completed / invoiced (current default).
  deductOnInvoice,

  /// Reduce stock when goods leave the warehouse.
  deductOnDispatch;

  String get dbValue => switch (this) {
        InventoryMovementPolicy.reserveOnOrder => 'reserve_on_order',
        InventoryMovementPolicy.deductOnApproval => 'deduct_on_approval',
        InventoryMovementPolicy.deductOnInvoice => 'deduct_on_invoice',
        InventoryMovementPolicy.deductOnDispatch => 'deduct_on_dispatch',
      };

  String get label => switch (this) {
        InventoryMovementPolicy.reserveOnOrder => 'Reserve on order',
        InventoryMovementPolicy.deductOnApproval => 'Deduct on approval',
        InventoryMovementPolicy.deductOnInvoice => 'Deduct on invoice',
        InventoryMovementPolicy.deductOnDispatch => 'Deduct on dispatch',
      };

  String get description => switch (this) {
        InventoryMovementPolicy.reserveOnOrder =>
          'Hold stock as soon as the sales rep saves the order.',
        InventoryMovementPolicy.deductOnApproval =>
          'Reduce stock when someone approves the order.',
        InventoryMovementPolicy.deductOnInvoice =>
          'Reduce stock when the sale is completed (current Sello behaviour).',
        InventoryMovementPolicy.deductOnDispatch =>
          'Reduce stock when goods are dispatched from the warehouse.',
      };

  static InventoryMovementPolicy fromDb(String? value) {
    return switch (value) {
      'reserve_on_order' => InventoryMovementPolicy.reserveOnOrder,
      'deduct_on_approval' => InventoryMovementPolicy.deductOnApproval,
      'deduct_on_dispatch' => InventoryMovementPolicy.deductOnDispatch,
      _ => InventoryMovementPolicy.deductOnInvoice,
    };
  }
}
