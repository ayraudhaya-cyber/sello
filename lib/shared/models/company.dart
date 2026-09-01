import 'package:equatable/equatable.dart';

/// Domain company (tenant) from `public.companies`.
///
/// Commercial limits/prices resolve through [PlanCapacityService] — do not
/// hardcode seats or amounts from [plan] alone.
class Company extends Equatable {
  const Company({
    required this.id,
    required this.name,
    required this.companyCode,
    required this.slug,
    this.legalName,
    this.isActive = true,
    this.plan = 'professional',
    this.subscriptionStatus = 'active',
    this.activatedAt,
    this.expiresAt,
    this.currentSubscriptionId,
  });

  final String id;
  final String name;
  final String companyCode;
  final String slug;
  final String? legalName;
  final bool isActive;

  /// Plan catalog code — resolve limits/prices via [PlanCapacityService].
  final String plan;
  final String subscriptionStatus;
  final String? activatedAt;
  final String? expiresAt;

  /// Current [company_subscriptions] row when migration 031 is applied.
  final String? currentSubscriptionId;

  Company copyWith({
    String? name,
    String? legalName,
  }) {
    return Company(
      id: id,
      name: name ?? this.name,
      companyCode: companyCode,
      slug: slug,
      legalName: legalName ?? this.legalName,
      isActive: isActive,
      plan: plan,
      subscriptionStatus: subscriptionStatus,
      activatedAt: activatedAt,
      expiresAt: expiresAt,
      currentSubscriptionId: currentSubscriptionId,
    );
  }

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] as String,
      name: json['name'] as String,
      companyCode: json['company_code'] as String,
      slug: json['slug'] as String,
      legalName: json['legal_name'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      plan: json['plan'] as String? ?? 'professional',
      subscriptionStatus: json['subscription_status'] as String? ?? 'active',
      activatedAt: json['activated_at'] as String?,
      expiresAt: json['expires_at'] as String?,
      currentSubscriptionId: json['current_subscription_id'] as String?,
    );
  }

  @override
  List<Object?> get props =>
      [
        id,
        name,
        companyCode,
        slug,
        legalName,
        isActive,
        plan,
        subscriptionStatus,
        activatedAt,
        expiresAt,
        currentSubscriptionId,
      ];
}
