import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/payment_record_status.dart';
import 'package:sello/shared/models/role_permission_profile.dart';
import 'package:sello/services/iam/permission_service.dart';

void main() {
  group('collection approval setting', () {
    test('defaults to auto-approve so existing tenants are unchanged', () {
      expect(CompanySettings.defaults.collectionApprovalRequired, isFalse);
      expect(
        CollectionApprovalMode.fromRequired(false),
        CollectionApprovalMode.autoApprove,
      );
    });

    test('fromJson treats a missing flag as false', () {
      final settings = CompanySettings.fromJson(_row());
      expect(settings.collectionApprovalRequired, isFalse);
    });

    test('fromJson reads an enabled approval requirement', () {
      final settings = CompanySettings.fromJson(
        _row({'collection_approval_required': true}),
      );
      expect(settings.collectionApprovalRequired, isTrue);
      expect(
        CollectionApprovalMode.fromRequired(true).requiresApproval,
        isTrue,
      );
    });

    test('settings payload persists the approval flag', () {
      final settings = CompanySettings.fromJson(
        _row({'collection_approval_required': true}),
      );
      final payload = settings.toUpdatePayload(employeeId: 'emp-1');
      expect(payload['collection_approval_required'], isTrue);
    });
  });

  group('payment review statuses', () {
    test('pending maps to Pending Review label', () {
      expect(PaymentRecordStatus.pending.label, 'Pending Review');
      expect(PaymentRecordStatus.pending.isPendingReview, isTrue);
    });

    test('rejected is distinct from cancelled', () {
      expect(
        PaymentRecordStatus.fromDb('rejected'),
        PaymentRecordStatus.rejected,
      );
      expect(PaymentRecordStatus.rejected.label, 'Rejected');
      expect(PaymentRecordStatus.cancelled.label, 'Cancelled');
    });
  });

  group('collection review permissions', () {
    test('Owner and Manager can approve payments', () {
      expect(
        PermissionService(
          profile: RolePermissionProfile.forRoleCode('owner'),
        ).canApprove(AppModule.payments),
        isTrue,
      );
      expect(
        PermissionService(
          profile: RolePermissionProfile.forRoleCode('manager'),
        ).canApprove(AppModule.payments),
        isTrue,
      );
    });

    test('Sales Rep cannot approve payments', () {
      expect(
        PermissionService(
          profile: RolePermissionProfile.forRoleCode('sales_representative'),
        ).canApprove(AppModule.payments),
        isFalse,
      );
    });
  });
}

Map<String, dynamic> _row([Map<String, dynamic>? overrides]) {
  return {
    'id': 'settings-1',
    'company_id': 'company-1',
    'currency': 'USD',
    'currency_position': 'before',
    'financial_year_start_month': 1,
    'default_tax_mode': 'exclusive',
    'default_reorder_level': 10,
    'default_product_status': 'active',
    'allow_negative_stock': false,
    'enable_low_stock_alert': true,
    'sales_reps_can_view_outstanding_balances': true,
    ...?overrides,
  };
}
