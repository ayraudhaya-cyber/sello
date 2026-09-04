import 'package:sello/core/error/app_failure.dart';
import 'package:sello/core/router/route_paths.dart';
import 'package:sello/shared/models/app_session.dart';
import 'package:sello/shared/models/role_permission_profile.dart';

/// Shared IAM service — modules must not invent their own authorization.
///
/// V1 resolves from [RolePermissionProfile.forRoleCode]. Later: load
/// `role_module_access` overrides, branch scopes, temporary grants, SSO claims.
class PermissionService {
  PermissionService({RolePermissionProfile? profile, AppSession? session})
      : _profile = profile ??
            (session == null
                ? const RolePermissionProfile(
                    roleCode: '',
                    title: '',
                    workspace: 'Unknown',
                    capabilities: [],
                    modules: [],
                  )
                : RolePermissionProfile.forRoleCode(session.role.code));

  final RolePermissionProfile _profile;

  RolePermissionProfile get profile => _profile;

  bool allows(AppModule module, PermissionAction action) =>
      _profile.allows(module, action);

  bool canView(AppModule module) => allows(module, PermissionAction.view);

  bool canCreate(AppModule module) => allows(module, PermissionAction.create);

  bool canEdit(AppModule module) => allows(module, PermissionAction.edit);

  bool canDelete(AppModule module) => allows(module, PermissionAction.delete);

  bool canApprove(AppModule module) => allows(module, PermissionAction.approve);

  bool canManage(AppModule module) => _profile.canManage(module);

  /// Field-visit assignee eligibility — shared IAM, not schedule-specific.
  bool get canPerformFieldVisits => _profile.canPerformFieldVisits;

  /// Owner / administrator can edit company settings. Managers are view-only.
  bool get canEditCompanySettings => canEdit(AppModule.settings);

  /// Owner and Manager (Hub) may send a configuration test SMS.
  bool get canSendTestSms {
    final code = _profile.roleCode.trim().toLowerCase();
    return code == 'owner' ||
        code == 'manager' ||
        code == 'administrator';
  }

  /// Sender ID is read-only unless Sello enabled `sms_sender_id_editable`.
  bool canEditSmsSenderId(bool smsSenderIdEditable) =>
      smsSenderIdEditable && canSendTestSms;

  /// Owner / administrator (settings edit). Managers are view-only.
  bool get canManageCompanyBranding => canEditCompanySettings;

  /// Business logo for invoices/receipts — not gated by Custom Branding.
  bool get canManageCompanyLogo => canEditCompanySettings;

  /// Branding settings (colours / dual chrome logos) require entitlement.
  bool canAccessBrandingSettings(bool customBrandingEnabled) =>
      customBrandingEnabled && canManageCompanyBranding;

  /// Hard gate for repositories / notifiers — prefer this over ad-hoc ifs.
  void require(AppModule module, PermissionAction action) {
    if (!allows(module, action)) {
      throw AuthorizationFailure(
        'Missing ${action.label.toLowerCase()} access for ${module.label}.',
      );
    }
  }

  /// Map a route path to the module that governs it (null = always allowed).
  static AppModule? moduleForRoute(String location) {
    final path = location.split('?').first;
    if (path.startsWith(RoutePaths.hubReports) ||
        path.startsWith(RoutePaths.hubAnalytics)) {
      return AppModule.reports;
    }
    if (path.startsWith(RoutePaths.hubOrders) ||
        path.startsWith(RoutePaths.selloOrders)) {
      return AppModule.orders;
    }
    if (path.startsWith(RoutePaths.hubInventory) ||
        path.startsWith(RoutePaths.selloInventory)) {
      return AppModule.inventory;
    }
    if (path.startsWith(RoutePaths.hubProducts) ||
        path.startsWith(RoutePaths.selloProducts)) {
      return AppModule.products;
    }
    if (path.startsWith(RoutePaths.hubSuppliers)) {
      return AppModule.suppliers;
    }
    if (path.startsWith(RoutePaths.hubCustomers) ||
        path.startsWith(RoutePaths.selloCustomers)) {
      return AppModule.customers;
    }
    if (path.startsWith(RoutePaths.hubPayments)) {
      return AppModule.payments;
    }
    if (path.startsWith(RoutePaths.hubSchedule)) {
      return AppModule.schedule;
    }
    if (path.startsWith(RoutePaths.hubVisits)) {
      return AppModule.visits;
    }
    // Sales visit workspace is part of the field day — always allowed in Sello.
    if (path.startsWith(RoutePaths.selloVisit)) {
      return null;
    }
    if (path.startsWith(RoutePaths.hubEmployees) ||
        path.startsWith(RoutePaths.hubAttendance)) {
      return AppModule.employees;
    }
    if (path.startsWith(RoutePaths.hubSettings)) {
      return AppModule.settings;
    }
    if (path.startsWith(RoutePaths.hubDashboard) ||
        path.startsWith(RoutePaths.selloDashboard) ||
        path.startsWith(RoutePaths.selloProfile)) {
      return null; // always reachable inside the correct workspace
    }
    return null;
  }

  bool canAccessRoute(String location) {
    final module = moduleForRoute(location);
    if (module == null) return true;
    return canView(module);
  }
}
