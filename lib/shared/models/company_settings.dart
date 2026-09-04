import 'package:equatable/equatable.dart';
import 'package:sello/shared/models/financial_visibility.dart';
import 'package:sello/shared/models/inventory_movement_policy.dart';
import 'package:sello/shared/models/outbound_notification_policies.dart';

enum CollectionApprovalMode {
  autoApprove,
  approvalRequired;

  String get label => switch (this) {
    CollectionApprovalMode.autoApprove => 'Auto-approve collections',
    CollectionApprovalMode.approvalRequired => 'Approval required',
  };

  String get description => switch (this) {
    CollectionApprovalMode.autoApprove =>
      'Collections update customer balances immediately.',
    CollectionApprovalMode.approvalRequired =>
      'Sales Rep collections stay Pending Review until an Owner or Manager approves.',
  };

  static CollectionApprovalMode fromRequired(bool required) => required
      ? CollectionApprovalMode.approvalRequired
      : CollectionApprovalMode.autoApprove;

  bool get requiresApproval => this == CollectionApprovalMode.approvalRequired;
}

enum CurrencyPosition {
  before,
  after;

  static CurrencyPosition fromDb(String? value) {
    return value == 'after' ? CurrencyPosition.after : CurrencyPosition.before;
  }

  String get dbValue => name;
}

enum TaxMode {
  exclusive,
  inclusive,
  none;

  static TaxMode fromDb(String? value) {
    return switch (value) {
      'inclusive' => TaxMode.inclusive,
      'none' => TaxMode.none,
      _ => TaxMode.exclusive,
    };
  }

  String get dbValue => name;

  String get label => switch (this) {
    TaxMode.exclusive => 'Exclusive',
    TaxMode.inclusive => 'Inclusive',
    TaxMode.none => 'None',
  };
}

enum DefaultProductStatus {
  active,
  inactive;

  static DefaultProductStatus fromDb(String? value) {
    return value == 'inactive'
        ? DefaultProductStatus.inactive
        : DefaultProductStatus.active;
  }

  String get dbValue => name;

  String get label => switch (this) {
    DefaultProductStatus.active => 'Active',
    DefaultProductStatus.inactive => 'Inactive',
  };

  bool get isActive => this == DefaultProductStatus.active;
}

/// Tenant preferences from `public.company_settings`.
class CompanySettings extends Equatable {
  const CompanySettings({
    required this.id,
    required this.companyId,
    required this.currency,
    required this.currencyPosition,
    required this.financialYearStartMonth,
    required this.defaultTaxMode,
    required this.defaultReorderLevel,
    required this.defaultProductStatus,
    required this.allowNegativeStock,
    required this.enableLowStockAlert,
    this.allowOrdersAboveAvailableStock = false,
    required this.salesRepsCanViewOutstandingBalances,
    required this.financialVisibility,
    this.collectionApprovalRequired = false,
    this.outboundNotificationPolicies = OutboundNotificationPolicies.defaults,
    this.smsSenderId,
    this.smsSenderIdEditable = false,
    this.inventoryMovementPolicy = InventoryMovementPolicy.deductOnInvoice,
    this.logoUrl,
    this.logoLightUrl,
    this.primaryColor,
    this.navBackgroundColor,
    this.customBrandingEnabled = false,
    this.documentShowBusinessNameWithLogo = false,
    this.ownerSetupCompleted = true,
  });

  final String id;
  final String companyId;
  final String currency;
  final CurrencyPosition currencyPosition;
  final int financialYearStartMonth;
  final TaxMode defaultTaxMode;
  final int defaultReorderLevel;
  final DefaultProductStatus defaultProductStatus;
  final bool allowNegativeStock;
  final bool enableLowStockAlert;

  /// When false, Sales Rep quantity controls cap at branch available stock.
  final bool allowOrdersAboveAvailableStock;

  /// Sales permission gate when outstanding policy is [FinancialVisibilityPolicy.internalOnly].
  final bool salesRepsCanViewOutstandingBalances;

  /// Order & invoice customer-financial visibility (outstanding, wallet, …).
  final FinancialVisibilityPolicies financialVisibility;

  /// When true, Sales Rep collections stay Pending Review until Owner/Manager approve.
  final bool collectionApprovalRequired;

  /// Tenant outbound messaging (SMS / WhatsApp + document links).
  final OutboundNotificationPolicies outboundNotificationPolicies;

  /// Approved SMS Sender ID (public name). API token is never stored here.
  final String? smsSenderId;

  /// Sello-controlled entitlement. Clients cannot toggle this from the app.
  final bool smsSenderIdEditable;

  /// When stock moves for a sale — enforced by inventory RPCs when wired.
  final InventoryMovementPolicy inventoryMovementPolicy;

  /// Optional reverse wordmark (HTTPS). Null uses the Sello mark on dark chrome.
  final String? logoUrl;

  /// Optional dark-ink wordmark (HTTPS). Null uses the Sello mark on light canvases.
  final String? logoLightUrl;

  /// Optional tenant accent as `#RRGGBB`. Null uses Sello purple.
  final String? primaryColor;

  /// Optional dark chrome for sidebar / splash as `#RRGGBB`. Null uses Sello rail.
  final String? navBackgroundColor;

  /// Sello-controlled entitlement. Clients cannot toggle this from the app.
  final bool customBrandingEnabled;

  /// When a business logo exists on invoices/receipts, also show `companies.name`.
  /// Ignored when no logo is set (name is always the fallback). Default: logo only.
  final bool documentShowBusinessNameWithLogo;

  /// When false, a newly provisioned Owner is guided through first-time setup.
  /// Missing / legacy rows are treated as complete so existing tenants are
  /// never forced through the flow.
  final bool ownerSetupCompleted;

  static const defaults = CompanySettings(
    id: '',
    companyId: '',
    currency: 'USD',
    currencyPosition: CurrencyPosition.before,
    financialYearStartMonth: 1,
    defaultTaxMode: TaxMode.exclusive,
    defaultReorderLevel: 10,
    defaultProductStatus: DefaultProductStatus.active,
    allowNegativeStock: false,
    enableLowStockAlert: true,
    allowOrdersAboveAvailableStock: false,
    salesRepsCanViewOutstandingBalances: true,
    financialVisibility: FinancialVisibilityPolicies.defaults,
    collectionApprovalRequired: false,
    outboundNotificationPolicies: OutboundNotificationPolicies.defaults,
    smsSenderId: null,
    smsSenderIdEditable: false,
    inventoryMovementPolicy: InventoryMovementPolicy.deductOnInvoice,
    logoUrl: null,
    logoLightUrl: null,
    primaryColor: null,
    navBackgroundColor: null,
    customBrandingEnabled: false,
    documentShowBusinessNameWithLogo: false,
    ownerSetupCompleted: true,
  );

  /// Whether Sales Home / field UI may show outstanding balances.
  bool get salesCanViewOutstandingBalances =>
      FinancialVisibility.showForSalesRep(
        policies: financialVisibility,
        kind: FinancialInfoKind.outstandingBalance,
        salesRepPermitted: salesRepsCanViewOutstandingBalances,
      );

  /// Whether invoices / SMS / WhatsApp / PDFs may include outstanding balance.
  bool get includeOutstandingOnCustomerDocuments =>
      FinancialVisibility.showOnCustomerDocuments(
        policies: financialVisibility,
        kind: FinancialInfoKind.outstandingBalance,
      );

  CompanySettings copyWith({
    String? currency,
    CurrencyPosition? currencyPosition,
    int? financialYearStartMonth,
    TaxMode? defaultTaxMode,
    int? defaultReorderLevel,
    DefaultProductStatus? defaultProductStatus,
    bool? allowNegativeStock,
    bool? enableLowStockAlert,
    bool? allowOrdersAboveAvailableStock,
    bool? salesRepsCanViewOutstandingBalances,
    FinancialVisibilityPolicies? financialVisibility,
    bool? collectionApprovalRequired,
    OutboundNotificationPolicies? outboundNotificationPolicies,
    String? smsSenderId,
    bool clearSmsSenderId = false,
    InventoryMovementPolicy? inventoryMovementPolicy,
    String? logoUrl,
    String? logoLightUrl,
    String? primaryColor,
    String? navBackgroundColor,
    bool clearLogoUrl = false,
    bool clearLogoLightUrl = false,
    bool clearPrimaryColor = false,
    bool clearNavBackgroundColor = false,
    bool? documentShowBusinessNameWithLogo,
    bool? ownerSetupCompleted,
  }) {
    return CompanySettings(
      id: id,
      companyId: companyId,
      currency: currency ?? this.currency,
      currencyPosition: currencyPosition ?? this.currencyPosition,
      financialYearStartMonth:
          financialYearStartMonth ?? this.financialYearStartMonth,
      defaultTaxMode: defaultTaxMode ?? this.defaultTaxMode,
      defaultReorderLevel: defaultReorderLevel ?? this.defaultReorderLevel,
      defaultProductStatus: defaultProductStatus ?? this.defaultProductStatus,
      allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
      enableLowStockAlert: enableLowStockAlert ?? this.enableLowStockAlert,
      allowOrdersAboveAvailableStock:
          allowOrdersAboveAvailableStock ??
          this.allowOrdersAboveAvailableStock,
      salesRepsCanViewOutstandingBalances:
          salesRepsCanViewOutstandingBalances ??
          this.salesRepsCanViewOutstandingBalances,
      financialVisibility: financialVisibility ?? this.financialVisibility,
      collectionApprovalRequired:
          collectionApprovalRequired ?? this.collectionApprovalRequired,
      outboundNotificationPolicies: outboundNotificationPolicies ??
          this.outboundNotificationPolicies,
      smsSenderId: smsSenderIdEditable
          ? (clearSmsSenderId ? null : (smsSenderId ?? this.smsSenderId))
          : this.smsSenderId,
      smsSenderIdEditable: smsSenderIdEditable,
      inventoryMovementPolicy:
          inventoryMovementPolicy ?? this.inventoryMovementPolicy,
      logoUrl: clearLogoUrl ? null : (logoUrl ?? this.logoUrl),
      logoLightUrl: clearLogoLightUrl
          ? null
          : (logoLightUrl ?? this.logoLightUrl),
      primaryColor: clearPrimaryColor
          ? null
          : (primaryColor ?? this.primaryColor),
      navBackgroundColor: clearNavBackgroundColor
          ? null
          : (navBackgroundColor ?? this.navBackgroundColor),
      customBrandingEnabled: customBrandingEnabled,
      documentShowBusinessNameWithLogo: documentShowBusinessNameWithLogo ??
          this.documentShowBusinessNameWithLogo,
      ownerSetupCompleted: ownerSetupCompleted ?? this.ownerSetupCompleted,
    );
  }

  factory CompanySettings.fromJson(Map<String, dynamic> json) {
    final rawPolicies = json['financial_visibility_policies'];
    Map<String, dynamic>? policyMap;
    if (rawPolicies is Map<String, dynamic>) {
      policyMap = rawPolicies;
    } else if (rawPolicies is Map) {
      policyMap = rawPolicies.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    return CompanySettings(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      currency: (json['currency'] as String?)?.trim().toUpperCase() ?? 'USD',
      currencyPosition: CurrencyPosition.fromDb(
        json['currency_position'] as String?,
      ),
      financialYearStartMonth:
          (json['financial_year_start_month'] as num?)?.toInt() ?? 1,
      defaultTaxMode: TaxMode.fromDb(json['default_tax_mode'] as String?),
      defaultReorderLevel:
          (json['default_reorder_level'] as num?)?.toInt() ?? 10,
      defaultProductStatus: DefaultProductStatus.fromDb(
        json['default_product_status'] as String?,
      ),
      allowNegativeStock: json['allow_negative_stock'] as bool? ?? false,
      enableLowStockAlert: json['enable_low_stock_alert'] as bool? ?? true,
      allowOrdersAboveAvailableStock:
          json['allow_orders_above_available_stock'] as bool? ?? false,
      salesRepsCanViewOutstandingBalances:
          json['sales_reps_can_view_outstanding_balances'] as bool? ?? true,
      financialVisibility: FinancialVisibilityPolicies.fromJson(policyMap),
      collectionApprovalRequired:
          json['collection_approval_required'] as bool? ?? false,
      outboundNotificationPolicies: OutboundNotificationPolicies.fromJson(
        json['outbound_notification_policies'],
      ),
      smsSenderId: _optionalText(json['sms_sender_id']),
      smsSenderIdEditable: json['sms_sender_id_editable'] as bool? ?? false,
      inventoryMovementPolicy: InventoryMovementPolicy.fromDb(
        json['inventory_movement_policy'] as String?,
      ),
      logoUrl: _optionalText(json['logo_url']),
      logoLightUrl: _optionalText(json['logo_light_url']),
      primaryColor: _optionalText(json['primary_color']),
      navBackgroundColor: _optionalText(json['nav_background_color']),
      customBrandingEnabled: json['custom_branding_enabled'] as bool? ?? false,
      documentShowBusinessNameWithLogo:
          json['document_show_business_name_with_logo'] as bool? ?? false,
      ownerSetupCompleted: json['owner_setup_completed'] as bool? ?? true,
    );
  }

  static String? _optionalText(dynamic value) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty ? null : text;
  }

  Map<String, dynamic> toUpdatePayload({required String employeeId}) {
    return {
      'currency': currency,
      'currency_position': currencyPosition.dbValue,
      'financial_year_start_month': financialYearStartMonth,
      'default_tax_mode': defaultTaxMode.dbValue,
      'default_reorder_level': defaultReorderLevel,
      'default_product_status': defaultProductStatus.dbValue,
      'allow_negative_stock': allowNegativeStock,
      'enable_low_stock_alert': enableLowStockAlert,
      'allow_orders_above_available_stock': allowOrdersAboveAvailableStock,
      'sales_reps_can_view_outstanding_balances':
          salesRepsCanViewOutstandingBalances,
      'financial_visibility_policies': financialVisibility.toJson(),
      'collection_approval_required': collectionApprovalRequired,
      'outbound_notification_policies': outboundNotificationPolicies.toJson(),
      if (smsSenderIdEditable) 'sms_sender_id': smsSenderId,
      'updated_by': employeeId,
    };
  }

  @override
  List<Object?> get props => [
    id,
    companyId,
    currency,
    currencyPosition,
    financialYearStartMonth,
    defaultTaxMode,
    defaultReorderLevel,
    defaultProductStatus,
    allowNegativeStock,
    enableLowStockAlert,
    allowOrdersAboveAvailableStock,
    salesRepsCanViewOutstandingBalances,
    financialVisibility,
        collectionApprovalRequired,
        outboundNotificationPolicies,
        smsSenderId,
        smsSenderIdEditable,
        inventoryMovementPolicy,
    logoUrl,
    logoLightUrl,
    primaryColor,
    navBackgroundColor,
    customBrandingEnabled,
    documentShowBusinessNameWithLogo,
    ownerSetupCompleted,
  ];
}
