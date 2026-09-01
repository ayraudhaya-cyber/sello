import 'package:equatable/equatable.dart';

num _numValue(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}

DateTime? _dateValue(dynamic value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

String? _stringValue(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// List / workspace summary for a supplier.
class SupplierSummary extends Equatable {
  const SupplierSummary({
    required this.id,
    required this.companyId,
    required this.name,
    required this.creditLimit,
    required this.openingBalance,
    required this.outstandingBalance,
    required this.isActive,
    this.branchId,
    this.code,
    this.contactName,
    this.phone,
    this.whatsapp,
    this.email,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.postalCode,
    this.country,
    this.taxNumber,
    this.category,
    this.paymentTerms,
    this.bankName,
    this.bankAccount,
    this.notes,
    this.leadTimeDays,
    this.lastPurchaseAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String companyId;
  final String? branchId;
  final String name;
  final String? code;
  final String? contactName;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;
  final String? taxNumber;
  final String? category;
  final String? paymentTerms;
  final String? bankName;
  final String? bankAccount;
  final String? notes;
  final num creditLimit;
  final num openingBalance;

  /// Stored as `current_balance` — outstanding payable (ledger later).
  final num outstandingBalance;
  final int? leadTimeDays;
  final bool isActive;
  final DateTime? lastPurchaseAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory SupplierSummary.fromJson(Map<String, dynamic> json) {
    return SupplierSummary(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      branchId: json['branch_id'] as String?,
      name: json['name'] as String? ?? '',
      code: _stringValue(json['code']),
      contactName: _stringValue(json['contact_name']),
      phone: _stringValue(json['phone']),
      whatsapp: _stringValue(json['whatsapp']),
      email: _stringValue(json['email']),
      addressLine1: _stringValue(json['address_line1']),
      addressLine2: _stringValue(json['address_line2']),
      city: _stringValue(json['city']),
      state: _stringValue(json['state']),
      postalCode: _stringValue(json['postal_code']),
      country: _stringValue(json['country']),
      taxNumber: _stringValue(json['tax_number']),
      category: _stringValue(json['category']),
      paymentTerms: _stringValue(json['payment_terms']),
      bankName: _stringValue(json['bank_name']),
      bankAccount: _stringValue(json['bank_account']),
      notes: _stringValue(json['notes']),
      creditLimit: _numValue(json['credit_limit']),
      openingBalance: _numValue(json['opening_balance']),
      outstandingBalance: _numValue(json['current_balance']),
      leadTimeDays: (json['lead_time_days'] as num?)?.toInt(),
      isActive: json['is_active'] as bool? ?? true,
      lastPurchaseAt: _dateValue(json['last_purchase_at']),
      createdAt: _dateValue(json['created_at']),
      updatedAt: _dateValue(json['updated_at']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        companyId,
        branchId,
        name,
        code,
        contactName,
        phone,
        whatsapp,
        email,
        addressLine1,
        addressLine2,
        city,
        state,
        postalCode,
        country,
        taxNumber,
        category,
        paymentTerms,
        bankName,
        bankAccount,
        notes,
        creditLimit,
        openingBalance,
        outstandingBalance,
        leadTimeDays,
        isActive,
        lastPurchaseAt,
        createdAt,
        updatedAt,
      ];
}

/// Hub dashboard metrics for the suppliers directory.
class SupplierDashboardStats extends Equatable {
  const SupplierDashboardStats({
    this.total = 0,
    this.active = 0,
    this.recentlyAdded = 0,
  });

  final int total;
  final int active;
  final int recentlyAdded;

  @override
  List<Object?> get props => [total, active, recentlyAdded];
}

enum SupplierTimelineKind {
  created,
  updated,
  archived,
  restored,
  productLinked,
  stockMovement,
  purchase,
  note,
}

/// Lightweight product row linked as preferred sourcing for a supplier.
class SupplierProductLink extends Equatable {
  const SupplierProductLink({
    required this.id,
    required this.name,
    required this.sku,
    required this.isActive,
    required this.currentStockQuantity,
    required this.costPrice,
    required this.sellingPrice,
    this.categoryName,
    this.unitLabel,
  });

  final String id;
  final String name;
  final String sku;
  final bool isActive;
  final num currentStockQuantity;
  final num costPrice;
  final num sellingPrice;
  final String? categoryName;
  final String? unitLabel;

  factory SupplierProductLink.fromQueryRow(Map<String, dynamic> json) {
    final category = json['categories'];
    final inventory = (json['inventory'] as List?) ?? const [];
    num totalStock = 0;
    for (final item in inventory) {
      if (item is! Map) continue;
      totalStock += _numValue(item['quantity']);
    }

    return SupplierProductLink(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Product',
      sku: json['sku'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      currentStockQuantity: totalStock,
      costPrice: _numValue(json['cost_price']),
      sellingPrice: _numValue(json['selling_price']),
      categoryName:
          category is Map ? _stringValue(category['name']) : null,
      unitLabel: _stringValue(json['unit_label']),
    );
  }

  @override
  List<Object?> get props => [id, name, sku, isActive, currentStockQuantity];
}

class SupplierTimelineEvent extends Equatable {
  const SupplierTimelineEvent({
    required this.kind,
    required this.title,
    required this.at,
    this.subtitle,
  });

  final SupplierTimelineKind kind;
  final String title;
  final String? subtitle;
  final DateTime at;

  @override
  List<Object?> get props => [kind, title, subtitle, at];
}

/// Full supplier workspace payload for Hub details.
class SupplierDetail extends Equatable {
  const SupplierDetail({
    required this.supplier,
    this.products = const [],
    this.recentMovements = const [],
    this.timeline = const [],
  });

  final SupplierSummary supplier;
  final List<SupplierProductLink> products;
  final List<StockMovementRef> recentMovements;
  final List<SupplierTimelineEvent> timeline;

  int get productCount => products.length;

  @override
  List<Object?> get props =>
      [supplier, products, recentMovements, timeline];
}

/// Stock movement slice for supplier inventory activity (avoids full inventory import cycles).
class StockMovementRef extends Equatable {
  const StockMovementRef({
    required this.id,
    required this.productId,
    required this.movementType,
    required this.quantityDelta,
    required this.quantityAfter,
    required this.createdAt,
    this.productName,
    this.productSku,
    this.reason,
    this.notes,
    this.createdByName,
    this.referenceType,
  });

  final String id;
  final String productId;
  final String movementType;
  final num quantityDelta;
  final num quantityAfter;
  final DateTime createdAt;
  final String? productName;
  final String? productSku;
  final String? reason;
  final String? notes;
  final String? createdByName;
  final String? referenceType;

  factory StockMovementRef.fromJson(Map<String, dynamic> json) {
    final product = json['products'];
    final employee = json['employees'];
    return StockMovementRef(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      movementType: json['movement_type'] as String? ?? 'adjustment',
      quantityDelta: _numValue(json['quantity_delta']),
      quantityAfter: _numValue(json['quantity_after']),
      createdAt: _dateValue(json['created_at']) ?? DateTime.now().toUtc(),
      productName: product is Map ? _stringValue(product['name']) : null,
      productSku: product is Map ? _stringValue(product['sku']) : null,
      reason: _stringValue(json['reason']),
      notes: _stringValue(json['notes']),
      createdByName:
          employee is Map ? _stringValue(employee['full_name']) : null,
      referenceType: _stringValue(json['reference_type']),
    );
  }

  String get displayTitle {
    final type = movementType.replaceAll('_', ' ');
    if (productName != null) return '$type · $productName';
    return type;
  }

  @override
  List<Object?> get props => [id, productId, movementType, createdAt];
}
