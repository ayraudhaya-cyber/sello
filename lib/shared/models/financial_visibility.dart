import 'package:equatable/equatable.dart';

/// Who may see a piece of customer financial information.
///
/// Reused for outstanding balance, wallet, credit limit, and future fields.
enum FinancialVisibilityPolicy {
  /// Hide on every surface (internal and customer-facing).
  never,

  /// Owner/Manager (and permitted Sales Reps) may see it internally.
  /// Never include on invoices, SMS, WhatsApp, PDFs, or invoice web pages.
  internalOnly,

  /// Include on customer-facing confirmations and invoice documents.
  /// Internal workspaces may also show it.
  customerCopy;

  static FinancialVisibilityPolicy fromDb(String? value) {
    return switch (value) {
      'never' => FinancialVisibilityPolicy.never,
      'customer_copy' => FinancialVisibilityPolicy.customerCopy,
      'internal_only' => FinancialVisibilityPolicy.internalOnly,
      _ => FinancialVisibilityPolicy.internalOnly,
    };
  }

  String get dbValue => switch (this) {
        FinancialVisibilityPolicy.never => 'never',
        FinancialVisibilityPolicy.internalOnly => 'internal_only',
        FinancialVisibilityPolicy.customerCopy => 'customer_copy',
      };

  String get label => switch (this) {
        FinancialVisibilityPolicy.never => 'Never',
        FinancialVisibilityPolicy.internalOnly => 'Internal only',
        FinancialVisibilityPolicy.customerCopy => 'Customer copy',
      };

  String get description => switch (this) {
        FinancialVisibilityPolicy.never =>
          'Do not show this value anywhere in Sello or on customer documents.',
        FinancialVisibilityPolicy.internalOnly =>
          'Show to authorized staff only. Never include on invoices, SMS, '
              'WhatsApp, PDFs, or invoice web pages.',
        FinancialVisibilityPolicy.customerCopy =>
          'Include on customer-facing invoices and confirmations so customers '
              'are reminded of the amount.',
      };

  /// Safe to print on invoices, SMS, WhatsApp, PDFs, invoice web pages.
  bool get includeOnCustomerDocuments =>
      this == FinancialVisibilityPolicy.customerCopy;

  /// Visible in Owner/Manager Hub workspaces.
  bool get showInHub => this != FinancialVisibilityPolicy.never;

  /// Visible in the Sales Rep workspace given the company Sales permission.
  bool showForSalesRep({required bool salesRepPermitted}) => switch (this) {
        FinancialVisibilityPolicy.never => false,
        FinancialVisibilityPolicy.internalOnly => salesRepPermitted,
        // Customer-facing docs include it — reps need the same figure on hand.
        FinancialVisibilityPolicy.customerCopy => true,
      };
}

/// Kinds of customer financial info that share [FinancialVisibilityPolicy].
enum FinancialInfoKind {
  outstandingBalance,
  walletBalance,
  creditLimit,
  availableCredit;

  String get dbKey => switch (this) {
        FinancialInfoKind.outstandingBalance => 'outstanding_balance',
        FinancialInfoKind.walletBalance => 'wallet_balance',
        FinancialInfoKind.creditLimit => 'credit_limit',
        FinancialInfoKind.availableCredit => 'available_credit',
      };

  String get label => switch (this) {
        FinancialInfoKind.outstandingBalance => 'Outstanding balance',
        FinancialInfoKind.walletBalance => 'Wallet balance',
        FinancialInfoKind.creditLimit => 'Credit limit',
        FinancialInfoKind.availableCredit => 'Available credit',
      };

  static FinancialInfoKind? fromDbKey(String key) {
    return switch (key) {
      'outstanding_balance' => FinancialInfoKind.outstandingBalance,
      'wallet_balance' => FinancialInfoKind.walletBalance,
      'credit_limit' => FinancialInfoKind.creditLimit,
      'available_credit' => FinancialInfoKind.availableCredit,
      _ => null,
    };
  }
}

/// Map of financial fields → visibility policies for a company.
///
/// Stored as JSON on `company_settings.financial_visibility_policies` so new
/// fields can be added without changing the Settings section structure.
class FinancialVisibilityPolicies extends Equatable {
  const FinancialVisibilityPolicies({
    this.outstandingBalance = FinancialVisibilityPolicy.internalOnly,
    this.walletBalance = FinancialVisibilityPolicy.never,
    this.creditLimit = FinancialVisibilityPolicy.never,
    this.availableCredit = FinancialVisibilityPolicy.never,
  });

  final FinancialVisibilityPolicy outstandingBalance;
  final FinancialVisibilityPolicy walletBalance;
  final FinancialVisibilityPolicy creditLimit;
  final FinancialVisibilityPolicy availableCredit;

  static const defaults = FinancialVisibilityPolicies();

  /// Fields currently editable in Order & Invoice Policies (others reserved).
  static const configuredKinds = <FinancialInfoKind>[
    FinancialInfoKind.outstandingBalance,
  ];

  FinancialVisibilityPolicy policyFor(FinancialInfoKind kind) => switch (kind) {
        FinancialInfoKind.outstandingBalance => outstandingBalance,
        FinancialInfoKind.walletBalance => walletBalance,
        FinancialInfoKind.creditLimit => creditLimit,
        FinancialInfoKind.availableCredit => availableCredit,
      };

  FinancialVisibilityPolicies copyWithPolicy({
    required FinancialInfoKind kind,
    required FinancialVisibilityPolicy policy,
  }) {
    return switch (kind) {
      FinancialInfoKind.outstandingBalance =>
        copyWith(outstandingBalance: policy),
      FinancialInfoKind.walletBalance => copyWith(walletBalance: policy),
      FinancialInfoKind.creditLimit => copyWith(creditLimit: policy),
      FinancialInfoKind.availableCredit => copyWith(availableCredit: policy),
    };
  }

  FinancialVisibilityPolicies copyWith({
    FinancialVisibilityPolicy? outstandingBalance,
    FinancialVisibilityPolicy? walletBalance,
    FinancialVisibilityPolicy? creditLimit,
    FinancialVisibilityPolicy? availableCredit,
  }) {
    return FinancialVisibilityPolicies(
      outstandingBalance: outstandingBalance ?? this.outstandingBalance,
      walletBalance: walletBalance ?? this.walletBalance,
      creditLimit: creditLimit ?? this.creditLimit,
      availableCredit: availableCredit ?? this.availableCredit,
    );
  }

  factory FinancialVisibilityPolicies.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return defaults;
    FinancialVisibilityPolicy read(FinancialInfoKind kind) {
      final raw = json[kind.dbKey];
      return FinancialVisibilityPolicy.fromDb(raw is String ? raw : null);
    }

    return FinancialVisibilityPolicies(
      outstandingBalance: read(FinancialInfoKind.outstandingBalance),
      walletBalance: read(FinancialInfoKind.walletBalance),
      creditLimit: read(FinancialInfoKind.creditLimit),
      availableCredit: read(FinancialInfoKind.availableCredit),
    );
  }

  Map<String, dynamic> toJson() => {
        for (final kind in FinancialInfoKind.values)
          kind.dbKey: policyFor(kind).dbValue,
      };

  @override
  List<Object?> get props => [
        outstandingBalance,
        walletBalance,
        creditLimit,
        availableCredit,
      ];
}

/// Resolves whether a financial figure may be shown for a given audience.
abstract final class FinancialVisibility {
  static bool showOnCustomerDocuments({
    required FinancialVisibilityPolicies policies,
    required FinancialInfoKind kind,
  }) =>
      policies.policyFor(kind).includeOnCustomerDocuments;

  static bool showInHub({
    required FinancialVisibilityPolicies policies,
    required FinancialInfoKind kind,
  }) =>
      policies.policyFor(kind).showInHub;

  static bool showForSalesRep({
    required FinancialVisibilityPolicies policies,
    required FinancialInfoKind kind,
    required bool salesRepPermitted,
  }) =>
      policies.policyFor(kind).showForSalesRep(
            salesRepPermitted: salesRepPermitted,
          );
}
