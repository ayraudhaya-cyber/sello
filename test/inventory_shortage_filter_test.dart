import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/models/inventory_item.dart';
import 'package:sello/shared/models/stock_movement_type.dart';

void main() {
  InventoryItem row({
    required num quantity,
    required num reserved,
    String branchId = 'head-office',
    bool isActive = true,
    num? reorderLevel,
    String name = 'Product',
    String sku = 'sku',
    String? variantSku,
    String inventoryId = 'inv',
  }) {
    return InventoryItem(
      inventoryId: inventoryId,
      companyId: 'c',
      branchId: branchId,
      productId: 'p',
      sku: sku,
      variantSku: variantSku,
      name: name,
      quantity: quantity,
      reservedQuantity: reserved,
      reorderLevel: reorderLevel,
      isActive: isActive,
    );
  }

  test('shortage is reserved quantity above physical stock', () {
    expect(row(quantity: 11, reserved: 16).isOverReserved, isTrue);
    expect(row(quantity: 10, reserved: 14).isOverReserved, isTrue);
    expect(row(quantity: 10, reserved: 10).isOverReserved, isFalse);
    expect(row(quantity: 10, reserved: 0).isOverReserved, isFalse);
    expect(row(quantity: 0, reserved: 0).isOverReserved, isFalse);
  });

  test('a shortage stays low stock when on-hand is still above zero', () {
    final holder = row(quantity: 11, reserved: 16, reorderLevel: 20);
    expect(holder.isOverReserved, isTrue);
    expect(holder.isLowStock, isTrue);
  });

  test('another branch is a separate stock row', () {
    final headOffice = row(
      quantity: 11,
      reserved: 16,
      branchId: 'head-office',
    );
    final other = row(quantity: 20, reserved: 4, branchId: 'showroom');
    expect(headOffice.isOverReserved, isTrue);
    expect(other.isOverReserved, isFalse);
    expect(headOffice.branchId, isNot(other.branchId));
  });

  test('negative stock is physical on-hand below zero', () {
    final negative = row(quantity: -2, reserved: 0);
    final shortage = row(quantity: 11, reserved: 16);
    final covered = row(quantity: 10, reserved: 10);

    expect(negative.matchesStatus(StockStatusFilter.negativeStock), isTrue);
    expect(shortage.matchesStatus(StockStatusFilter.negativeStock), isFalse);
    expect(covered.matchesStatus(StockStatusFilter.negativeStock), isFalse);
  });

  test('each filter applies only its own condition', () {
    final shortageOnly = row(quantity: 10, reserved: 14);
    final both = row(quantity: -3, reserved: 2);
    final rows = [shortageOnly, both, row(quantity: 8, reserved: 1)];

    final negative = rows
        .where((item) => item.matchesStatus(StockStatusFilter.negativeStock))
        .toList();
    final short = rows
        .where((item) => item.matchesStatus(StockStatusFilter.shortage))
        .toList();

    expect(negative, [both]);
    expect(short, [shortageOnly, both]);
    expect(both.matchesStatus(StockStatusFilter.negativeStock), isTrue);
    expect(both.matchesStatus(StockStatusFilter.shortage), isTrue);
    expect(both.quantity < 0, isTrue);
  });

  test('glass holder and smart lock shortages stay on their own variants', () {
    final glass = row(
      quantity: 11,
      reserved: 16,
      name: 'HALF ROUND GLASS HOLDER',
      sku: 'RJ_0072',
      inventoryId: 'glass',
    );
    final smart = row(
      quantity: 10,
      reserved: 14,
      name: 'Smart Lock',
      sku: 'L130',
      variantSku: 'L130',
      inventoryId: 'smart',
    );
    final otherBranch = row(
      quantity: 10,
      reserved: 14,
      name: 'Smart Lock',
      sku: 'L130',
      variantSku: 'L130',
      branchId: 'showroom',
      inventoryId: 'smart-showroom',
    );
    final coveredOption = row(
      quantity: 4,
      reserved: 1,
      name: 'Smart Lock',
      sku: 'L130',
      variantSku: 'L130-BODY',
      inventoryId: 'smart-body',
    );

    expect(glass.shortageQuantity, 5);
    expect(smart.shortageQuantity, 4);
    expect(glass.matchesStatus(StockStatusFilter.negativeStock), isFalse);
    expect(smart.matchesStatus(StockStatusFilter.negativeStock), isFalse);
    expect(glass.matchesStatus(StockStatusFilter.shortage), isTrue);
    expect(smart.matchesStatus(StockStatusFilter.shortage), isTrue);
    expect(coveredOption.matchesStatus(StockStatusFilter.shortage), isFalse);

    final headOffice = [glass, smart, otherBranch, coveredOption].where(
      (item) =>
          item.branchId == 'head-office' &&
          item.matchesStatus(StockStatusFilter.shortage),
    );
    expect(headOffice.map((item) => item.variantSku ?? item.sku), [
      'RJ_0072',
      'L130',
    ]);
  });

  test('search matches product name, parent SKU, and variant SKU', () {
    final smart = row(
      quantity: 10,
      reserved: 14,
      name: 'Smart Lock',
      sku: 'LOCK',
      variantSku: 'L130',
    );

    expect(inventoryRowMatchesSearch(smart, 'Smart Lock L130'), isTrue);
    expect(inventoryRowMatchesSearch(smart, 'Smart Lock'), isTrue);
    expect(inventoryRowMatchesSearch(smart, 'LOCK'), isTrue);
    expect(inventoryRowMatchesSearch(smart, 'L130'), isTrue);
    expect(inventoryRowMatchesSearch(smart, 'RJ_0072'), isFalse);
  });
}
