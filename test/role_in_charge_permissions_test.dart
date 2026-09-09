import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/iam/permission_service.dart';
import 'package:sello/shared/models/role_permission_profile.dart';
import 'package:sello/shared/models/user_role.dart';

void main() {
  group('UserRole', () {
    test('maps store and sales in-charge codes', () {
      expect(UserRole.fromCode('store_in_charge'), UserRole.storeInCharge);
      expect(UserRole.fromCode('sales_in_charge'), UserRole.salesInCharge);
    });

    test('Hub vs Sales workspace split', () {
      expect(UserRole.owner.usesHub, isTrue);
      expect(UserRole.manager.usesHub, isTrue);
      expect(UserRole.storeInCharge.usesHub, isTrue);
      expect(UserRole.salesInCharge.usesHub, isTrue);
      expect(UserRole.salesRepresentative.usesHub, isFalse);
      expect(UserRole.salesRepresentative.usesSello, isTrue);
      expect(UserRole.storeInCharge.usesSello, isFalse);
    });

    test('existing Owner/Manager/Sales Rep codes unchanged', () {
      expect(UserRole.fromCode('owner'), UserRole.owner);
      expect(UserRole.fromCode('manager'), UserRole.manager);
      expect(
        UserRole.fromCode('sales_representative'),
        UserRole.salesRepresentative,
      );
    });
  });

  group('RolePermissionProfile — Owner unchanged', () {
    final profile = RolePermissionProfile.forRoleCode('owner');
    final perms = PermissionService(profile: profile);

    test('full Hub settings and team', () {
      expect(perms.canEditCompanySettings, isTrue);
      expect(perms.canManage(AppModule.employees), isTrue);
      expect(perms.canManage(AppModule.inventory), isTrue);
      expect(perms.canManage(AppModule.orders), isTrue);
    });
  });

  group('RolePermissionProfile — Manager unchanged', () {
    final profile = RolePermissionProfile.forRoleCode('manager');
    final perms = PermissionService(profile: profile);

    test('ops access without settings edit', () {
      expect(perms.canEditCompanySettings, isFalse);
      expect(perms.canView(AppModule.settings), isTrue);
      expect(perms.canManage(AppModule.employees), isTrue);
      expect(perms.canManage(AppModule.inventory), isTrue);
    });
  });

  group('RolePermissionProfile — Sales Rep unchanged', () {
    final profile = RolePermissionProfile.forRoleCode('sales_representative');
    final perms = PermissionService(profile: profile);

    test('Sales workspace only', () {
      expect(profile.workspace, 'Sales');
      expect(perms.canManage(AppModule.sales), isTrue);
      expect(perms.canManage(AppModule.employees), isFalse);
      expect(perms.canView(AppModule.settings), isFalse);
    });
  });

  group('RolePermissionProfile — Store In-charge', () {
    final profile = RolePermissionProfile.forRoleCode('store_in_charge');
    final perms = PermissionService(profile: profile);

    test('guidance and Hub workspace', () {
      expect(profile.workspace, 'Hub');
      expect(profile.title, 'Store In-charge');
      expect(
        profile.guidance,
        'Manages stock, inventory and store deliveries.',
      );
    });

    test('inventory and delivery capabilities', () {
      expect(perms.canView(AppModule.products), isTrue);
      expect(perms.canCreate(AppModule.products), isTrue);
      expect(perms.canEdit(AppModule.products), isTrue);
      expect(perms.canDelete(AppModule.products), isFalse);
      expect(perms.canManage(AppModule.inventory), isTrue);
      expect(perms.canView(AppModule.orders), isTrue);
      expect(perms.canCreate(AppModule.orders), isFalse);
      expect(perms.canEdit(AppModule.orders), isTrue);
      expect(perms.canApprove(AppModule.orders), isTrue);
      expect(perms.canView(AppModule.customers), isTrue);
      expect(perms.canManage(AppModule.customers), isFalse);
    });

    test('cannot administer team, settings, billing modules', () {
      expect(perms.canView(AppModule.employees), isFalse);
      expect(perms.canView(AppModule.settings), isFalse);
      expect(perms.canEditCompanySettings, isFalse);
      expect(perms.canManage(AppModule.payments), isFalse);
      expect(perms.canView(AppModule.suppliers), isFalse);
      expect(perms.canView(AppModule.reports), isFalse);
    });
  });

  group('RolePermissionProfile — Sales In-charge', () {
    final profile = RolePermissionProfile.forRoleCode('sales_in_charge');
    final perms = PermissionService(profile: profile);

    test('guidance and Hub workspace', () {
      expect(profile.workspace, 'Hub');
      expect(profile.title, 'Sales In-charge');
      expect(
        profile.guidance,
        'Manages sales, customers and the sales team.',
      );
    });

    test('sales ops capabilities', () {
      expect(perms.canManage(AppModule.orders), isTrue);
      expect(perms.canManage(AppModule.customers), isTrue);
      expect(perms.canView(AppModule.employees), isTrue);
      expect(perms.canManage(AppModule.employees), isFalse);
      expect(perms.canView(AppModule.reports), isTrue);
      expect(perms.canView(AppModule.products), isTrue);
      expect(perms.canView(AppModule.inventory), isTrue);
    });

    test('cannot adjust inventory or administer settings/team', () {
      expect(perms.canCreate(AppModule.inventory), isFalse);
      expect(perms.canEdit(AppModule.inventory), isFalse);
      expect(perms.canManage(AppModule.inventory), isFalse);
      expect(perms.canView(AppModule.settings), isFalse);
      expect(perms.canEditCompanySettings, isFalse);
      expect(perms.canManage(AppModule.employees), isFalse);
      expect(perms.canView(AppModule.suppliers), isFalse);
    });
  });

  group('PermissionService route access', () {
    test('Store In-charge can open inventory and orders, not settings', () {
      final perms = PermissionService(
        profile: RolePermissionProfile.forRoleCode('store_in_charge'),
      );
      expect(perms.canAccessRoute('/hub/inventory'), isTrue);
      expect(perms.canAccessRoute('/hub/orders'), isTrue);
      expect(perms.canAccessRoute('/hub/products'), isTrue);
      expect(perms.canAccessRoute('/hub/settings'), isFalse);
      expect(perms.canAccessRoute('/hub/employees'), isFalse);
      expect(perms.canAccessRoute('/hub/dashboard'), isTrue);
    });

    test('Sales In-charge can open orders and team view, not inventory write routes only by view', () {
      final perms = PermissionService(
        profile: RolePermissionProfile.forRoleCode('sales_in_charge'),
      );
      expect(perms.canAccessRoute('/hub/orders'), isTrue);
      expect(perms.canAccessRoute('/hub/customers'), isTrue);
      expect(perms.canAccessRoute('/hub/employees'), isTrue);
      expect(perms.canAccessRoute('/hub/reports'), isTrue);
      expect(perms.canAccessRoute('/hub/inventory'), isTrue);
      expect(perms.canAccessRoute('/hub/settings'), isFalse);
      expect(perms.canAccessRoute('/hub/suppliers'), isFalse);
    });
  });
}
