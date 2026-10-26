import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/branch.dart';
import 'package:sello/shared/models/company.dart';
import 'package:sello/shared/models/employee.dart';
import 'package:sello/shared/models/role.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Last workspace identity for one auth user.
///
/// SharedPreferences only. No access token, refresh token, or password.
/// A snapshot lets the shell open during an outage. It does not prove the
/// account is still allowed.
class SessionSnapshotStore {
  SessionSnapshotStore();

  static const prefsKey = 'session.workspace_snapshot';

  Future<void> save(AppSession session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonEncode(_encode(session)));
    } catch (_) {
      // A storage failure must not block a successful online sign-in.
    }
  }

  /// Returns a session only when [user] is the same person who was cached.
  Future<AppSession?> loadFor(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      if (json['user_id'] != user.id) return null;

      final employeeJson = json['employee'];
      final companyJson = json['company'];
      final roleJson = json['role'];
      if (employeeJson is! Map || companyJson is! Map || roleJson is! Map) {
        return null;
      }

      final employee = Employee.fromJson(
        Map<String, dynamic>.from(employeeJson),
      );
      final company = Company.fromJson(Map<String, dynamic>.from(companyJson));
      if (!employee.isActive || !employee.employmentStatus.canAuthenticate) {
        return null;
      }
      if (!company.isActive) return null;

      final branchJson = json['branch'];
      final branch = branchJson is Map
          ? Branch.fromJson(Map<String, dynamic>.from(branchJson))
          : null;

      return AppSession(
        authUser: user,
        employee: employee,
        company: company,
        role: Role.fromJson(Map<String, dynamic>.from(roleJson)),
        branch: branch,
        ownerSetupCompleted: json['owner_setup_completed'] as bool? ?? true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
    } catch (_) {}
  }

  Map<String, dynamic> _encode(AppSession session) {
    final employee = session.employee;
    final company = session.company;
    final role = session.role;
    final branch = session.branch;
    return {
      'user_id': session.userId,
      'owner_setup_completed': session.ownerSetupCompleted,
      'employee': {
        'id': employee.id,
        'company_id': employee.companyId,
        'role_id': employee.roleId,
        'email': employee.email,
        'full_name': employee.fullName,
        'branch_id': employee.branchId,
        'user_id': employee.userId,
        'phone': employee.phone,
        'avatar_url': employee.avatarUrl,
        'employee_code': employee.employeeCode,
        'employment_status': employee.employmentStatus.code,
        'is_active': employee.isActive,
      },
      'company': {
        'id': company.id,
        'name': company.name,
        'company_code': company.companyCode,
        'slug': company.slug,
        'legal_name': company.legalName,
        'is_active': company.isActive,
        'plan': company.plan,
        'subscription_status': company.subscriptionStatus,
        'activated_at': company.activatedAt,
        'expires_at': company.expiresAt,
        'current_subscription_id': company.currentSubscriptionId,
      },
      'role': {
        'id': role.id,
        'code': role.code,
        'name': role.name,
        'description': role.description,
        'display_order': role.displayOrder,
      },
      if (branch != null)
        'branch': {
          'id': branch.id,
          'company_id': branch.companyId,
          'name': branch.name,
          'code': branch.code,
          'phone': branch.phone,
          'email': branch.email,
          'manager_name': branch.managerName,
          'address_line1': branch.addressLine1,
          'is_active': branch.isActive,
        },
    };
  }
}
