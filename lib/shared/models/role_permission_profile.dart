import 'package:equatable/equatable.dart';

/// App modules for role → access mapping (Settings ACL / custom roles later).
enum AppModule {
  products,
  customers,
  suppliers,
  orders,
  inventory,
  payments,
  reports,
  settings,
  employees,
  sales,
  schedule,
  visits,
  notifications,
  intelligence,
}

extension AppModuleX on AppModule {
  String get key => name;

  String get label => switch (this) {
        AppModule.products => 'Products',
        AppModule.customers => 'Customers',
        AppModule.suppliers => 'Suppliers',
        AppModule.orders => 'Orders',
        AppModule.inventory => 'Inventory',
        AppModule.payments => 'Payments',
        AppModule.reports => 'Reports',
        AppModule.settings => 'Settings',
        AppModule.employees => 'Team',
        AppModule.sales => 'Sales app',
        AppModule.schedule => 'Schedules',
        AppModule.visits => 'Customer Visits',
        AppModule.notifications => 'Notifications',
        AppModule.intelligence => 'Sello Intelligence',
      };

  static AppModule? tryParse(String? value) {
    final key = value?.trim().toLowerCase();
    if (key == null || key.isEmpty) return null;
    for (final module in AppModule.values) {
      if (module.key == key) return module;
    }
    return null;
  }
}

/// Module verbs — consumed by UI, repos, and (later) SQL helpers.
enum PermissionAction {
  view,
  create,
  edit,
  delete,
  approve,
}

extension PermissionActionX on PermissionAction {
  String get key => name;

  String get label => switch (this) {
        PermissionAction.view => 'View',
        PermissionAction.create => 'Create',
        PermissionAction.edit => 'Edit',
        PermissionAction.delete => 'Delete',
        PermissionAction.approve => 'Approve',
      };
}

/// Per-module ACL entry.
class ModuleAccess extends Equatable {
  const ModuleAccess({
    required this.module,
    this.canView = false,
    this.canCreate = false,
    this.canEdit = false,
    this.canDelete = false,
    this.canApprove = false,
  });

  /// View-only access.
  const ModuleAccess.view(this.module)
      : canView = true,
        canCreate = false,
        canEdit = false,
        canDelete = false,
        canApprove = false;

  /// Operational manage (no approve).
  const ModuleAccess.manage(this.module, {bool approve = false})
      : canView = true,
        canCreate = true,
        canEdit = true,
        canDelete = true,
        canApprove = approve;

  /// Full control including approve where relevant.
  const ModuleAccess.full(this.module)
      : canView = true,
        canCreate = true,
        canEdit = true,
        canDelete = true,
        canApprove = true;

  final AppModule module;
  final bool canView;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;
  final bool canApprove;

  /// Back-compat aggregate — any write verb.
  bool get canManage => canCreate || canEdit || canDelete || canApprove;

  bool allows(PermissionAction action) => switch (action) {
        PermissionAction.view => canView,
        PermissionAction.create => canCreate,
        PermissionAction.edit => canEdit,
        PermissionAction.delete => canDelete,
        PermissionAction.approve => canApprove,
      };

  ModuleAccess copyWith({
    bool? canView,
    bool? canCreate,
    bool? canEdit,
    bool? canDelete,
    bool? canApprove,
  }) {
    return ModuleAccess(
      module: module,
      canView: canView ?? this.canView,
      canCreate: canCreate ?? this.canCreate,
      canEdit: canEdit ?? this.canEdit,
      canDelete: canDelete ?? this.canDelete,
      canApprove: canApprove ?? this.canApprove,
    );
  }

  /// Merge DB override onto a baseline profile entry.
  ModuleAccess mergeOverride({
    bool? canView,
    bool? canCreate,
    bool? canEdit,
    bool? canDelete,
    bool? canApprove,
    bool? canManage,
  }) {
    // Legacy rows may only set can_manage — expand to write verbs.
    final manage = canManage;
    return ModuleAccess(
      module: module,
      canView: canView ?? this.canView,
      canCreate: canCreate ?? (manage == true ? true : this.canCreate),
      canEdit: canEdit ?? (manage == true ? true : this.canEdit),
      canDelete: canDelete ?? (manage == true ? true : this.canDelete),
      canApprove: canApprove ?? this.canApprove,
    );
  }

  @override
  List<Object?> get props =>
      [module, canView, canCreate, canEdit, canDelete, canApprove];
}

/// Central permission profile derived from role code (+ future DB overrides).
///
/// Business owners think in people and responsibilities — this map is the
/// technical spine. Custom roles / templates / branch scopes plug in later
/// without changing module consumers.
class RolePermissionProfile extends Equatable {
  const RolePermissionProfile({
    required this.roleCode,
    required this.title,
    required this.workspace,
    required this.capabilities,
    required this.modules,
  });

  final String roleCode;
  final String title;

  /// Hub | Sales | Future
  final String workspace;
  final List<String> capabilities;
  final List<ModuleAccess> modules;

  ModuleAccess? accessFor(AppModule module) {
    for (final entry in modules) {
      if (entry.module == module) return entry;
    }
    return null;
  }

  bool allows(AppModule module, PermissionAction action) =>
      accessFor(module)?.allows(action) ?? false;

  bool canView(AppModule module) => allows(module, PermissionAction.view);

  bool canManage(AppModule module) =>
      accessFor(module)?.canManage ?? false;

  /// Eligible to be assigned as the field agent on a customer visit / route.
  ///
  /// Derived from [AppModule.sales] write access — Hub owners/managers can
  /// administer Schedule without being field-assignable unless a custom role
  /// grants Sales app capability. Do not hardcode role-code exclusions.
  bool get canPerformFieldVisits => canManage(AppModule.sales);

  /// Resolve whether [roleCode] may perform field visits (assignee lists).
  static bool roleCanPerformFieldVisits(String? roleCode) {
    if (roleCode == null || roleCode.trim().isEmpty) return false;
    return RolePermissionProfile.forRoleCode(roleCode).canPerformFieldVisits;
  }

  /// Short owner-friendly line shown under the role picker.
  String get guidance => switch (roleCode) {
        'owner' => 'Full access to the business.',
        'manager' => 'Can access the Hub and manage daily operations.',
        'sales_representative' => 'Uses the Sello Sales Rep mobile app.',
        'warehouse_staff' => 'Manages stock and fulfilment in the warehouse.',
        'supervisor' => 'Oversees field teams and day-to-day operations.',
        'cashier' => 'Handles point-of-sale collections.',
        'accountant' => 'Works with payments, ledgers, and financial reports.',
        _ => 'Access and interface follow this role.',
      };

  static RolePermissionProfile forRoleCode(String code) {
    switch (code.trim().toLowerCase()) {
      case 'owner':
        return RolePermissionProfile(
          roleCode: 'owner',
          title: 'Owner',
          workspace: 'Hub',
          capabilities: const [
            'Full platform access',
            'Manage company settings & billing',
            'Manage team members and roles',
            'Products, inventory, orders, payments, customers',
            'Reports and Sello Intelligence',
          ],
          modules: _hubFull(manageSettings: true, manageEmployees: true),
        );
      case 'manager':
        return RolePermissionProfile(
          roleCode: 'manager',
          title: 'Manager',
          workspace: 'Hub',
          capabilities: const [
            'Same Hub interface as Owner',
            'Operational management of catalog and sales',
            'Manage team members (ownership / billing limited)',
            'Products, inventory, orders, payments, customers',
            'Reports and Sello Intelligence',
          ],
          modules: _hubFull(manageSettings: false, manageEmployees: true),
        );
      case 'sales_representative':
        return RolePermissionProfile(
          roleCode: 'sales_representative',
          title: 'Sales Representative',
          workspace: 'Sales',
          capabilities: const [
            'Field sales application only',
            'Orders and customers (operational)',
            'Catalog browsing',
            'Attendance and today\'s scheduled visits',
            'No Hub administration',
          ],
          modules: [
            const ModuleAccess.manage(AppModule.sales),
            const ModuleAccess.manage(AppModule.orders),
            const ModuleAccess.manage(AppModule.customers),
            const ModuleAccess.view(AppModule.schedule),
            const ModuleAccess.manage(AppModule.visits),
            const ModuleAccess.view(AppModule.products),
            const ModuleAccess.view(AppModule.inventory),
            const ModuleAccess.view(AppModule.payments),
            const ModuleAccess.view(AppModule.notifications),
            const ModuleAccess.view(AppModule.intelligence),
            const ModuleAccess(module: AppModule.reports),
            const ModuleAccess(module: AppModule.settings),
            const ModuleAccess(module: AppModule.employees),
            const ModuleAccess(module: AppModule.suppliers),
          ],
        );
      case 'cashier':
        return const RolePermissionProfile(
          roleCode: 'cashier',
          title: 'Cashier',
          workspace: 'Future',
          capabilities: [
            'Point-of-sale collections',
            'Limited order and payment access',
          ],
          modules: [
            ModuleAccess.manage(AppModule.orders),
            ModuleAccess.manage(AppModule.payments),
            ModuleAccess.view(AppModule.customers),
            ModuleAccess.view(AppModule.products),
            ModuleAccess.view(AppModule.notifications),
          ],
        );
      case 'warehouse_staff':
        return const RolePermissionProfile(
          roleCode: 'warehouse_staff',
          title: 'Warehouse Staff',
          workspace: 'Future',
          capabilities: [
            'Inventory adjustments and fulfilment',
          ],
          modules: [
            ModuleAccess.manage(AppModule.inventory),
            ModuleAccess.view(AppModule.products),
            ModuleAccess.view(AppModule.orders),
            ModuleAccess.view(AppModule.notifications),
          ],
        );
      case 'accountant':
        return const RolePermissionProfile(
          roleCode: 'accountant',
          title: 'Accountant',
          workspace: 'Future',
          capabilities: [
            'Financial reporting and ledgers',
          ],
          modules: [
            ModuleAccess.manage(AppModule.payments),
            ModuleAccess.manage(AppModule.reports),
            ModuleAccess.view(AppModule.orders),
            ModuleAccess.view(AppModule.intelligence),
            ModuleAccess.view(AppModule.notifications),
          ],
        );
      case 'administrator':
        return RolePermissionProfile(
          roleCode: 'administrator',
          title: 'Administrator',
          workspace: 'Future',
          capabilities: const [
            'Technical administration',
          ],
          modules: _hubFull(manageSettings: true, manageEmployees: true),
        );
      default:
        return RolePermissionProfile(
          roleCode: code,
          title: code,
          workspace: 'Unknown',
          capabilities: const ['Permissions not yet defined for this role'],
          modules: const [],
        );
    }
  }

  /// Apply optional DB overrides (global then company-scoped).
  RolePermissionProfile withOverrides(Iterable<ModuleAccess> overrides) {
    if (overrides.isEmpty) return this;
    final byModule = {
      for (final entry in modules) entry.module: entry,
    };
    for (final override in overrides) {
      final baseline = byModule[override.module] ??
          ModuleAccess(module: override.module);
      byModule[override.module] = baseline.copyWith(
        canView: override.canView,
        canCreate: override.canCreate,
        canEdit: override.canEdit,
        canDelete: override.canDelete,
        canApprove: override.canApprove,
      );
    }
    return RolePermissionProfile(
      roleCode: roleCode,
      title: title,
      workspace: workspace,
      capabilities: capabilities,
      modules: [
        for (final module in AppModule.values)
          if (byModule.containsKey(module)) byModule[module]!,
      ],
    );
  }

  static List<ModuleAccess> _hubFull({
    required bool manageSettings,
    required bool manageEmployees,
  }) {
    return [
      for (final module in AppModule.values)
        if (module == AppModule.sales)
          const ModuleAccess(module: AppModule.sales)
        else if (module == AppModule.settings)
          manageSettings
              ? const ModuleAccess.full(AppModule.settings)
              : const ModuleAccess.view(AppModule.settings)
        else if (module == AppModule.employees)
          manageEmployees
              ? const ModuleAccess.full(AppModule.employees)
              : const ModuleAccess.view(AppModule.employees)
        else if (module == AppModule.orders ||
            module == AppModule.payments ||
            module == AppModule.inventory)
          ModuleAccess.full(module)
        else
          ModuleAccess.manage(module),
    ];
  }

  @override
  List<Object?> get props =>
      [roleCode, title, workspace, capabilities, modules];
}
