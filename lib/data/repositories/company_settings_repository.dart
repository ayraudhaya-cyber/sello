import 'package:sello/core/constants/media_constants.dart';
import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/storage/media_storage_service.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/company_settings.dart';
import 'package:sello/shared/models/processed_media.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CompanySettingsRepository {
  CompanySettingsRepository({
    SupabaseClient? client,
    MediaStorageService? storage,
  })  : _client = client ?? SupabaseService.client,
        _storage = storage ?? MediaStorageService();

  final SupabaseClient _client;
  final MediaStorageService _storage;

  static const _select = '''
    id,
    company_id,
    currency,
    currency_position,
    financial_year_start_month,
    default_tax_mode,
    default_reorder_level,
    default_product_status,
    allow_negative_stock,
    enable_low_stock_alert,
    allow_orders_above_available_stock,
    sales_reps_can_view_outstanding_balances,
    financial_visibility_policies,
    collection_approval_required,
    outbound_notification_policies,
    sms_sender_id,
    sms_sender_id_editable,
    inventory_movement_policy,
    logo_url,
    logo_light_url,
    primary_color,
    nav_background_color,
    custom_branding_enabled,
    document_show_business_name_with_logo
  ''';

  // inventory_movement_policy is added in migration 030. Include it in
  // [_select] once applied in all environments; until then Dart defaults
  // to [InventoryMovementPolicy.deductOnInvoice].

  Future<CompanySettings> fetchForCompany(
    String companyId, {
    String? employeeId,
  }) async {
    try {
      final row = await _client
          .from('company_settings')
          .select(_select)
          .eq('company_id', companyId)
          .maybeSingle();

      if (row != null) {
        return CompanySettings.fromJson(Map<String, dynamic>.from(row));
      }

      return ensureDefaults(
        companyId: companyId,
        employeeId: employeeId,
      );
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load settings.'
            : error.message,
      );
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Creates a settings row when missing (e.g. legacy tenants).
  Future<CompanySettings> ensureDefaults({
    required String companyId,
    required String? employeeId,
  }) async {
    try {
      final existing = await _client
          .from('company_settings')
          .select(_select)
          .eq('company_id', companyId)
          .maybeSingle();
      if (existing != null) {
        return CompanySettings.fromJson(Map<String, dynamic>.from(existing));
      }

      final inserted = await _client
          .from('company_settings')
          .insert({
            'company_id': companyId,
            'currency': CompanySettings.defaults.currency,
            'timezone': 'UTC',
            'locale': 'en-US',
            'currency_position':
                CompanySettings.defaults.currencyPosition.dbValue,
            'financial_year_start_month':
                CompanySettings.defaults.financialYearStartMonth,
            'default_tax_mode': CompanySettings.defaults.defaultTaxMode.dbValue,
            'default_reorder_level':
                CompanySettings.defaults.defaultReorderLevel,
            'default_product_status':
                CompanySettings.defaults.defaultProductStatus.dbValue,
            'allow_negative_stock':
                CompanySettings.defaults.allowNegativeStock,
            'enable_low_stock_alert':
                CompanySettings.defaults.enableLowStockAlert,
            'allow_orders_above_available_stock':
                CompanySettings.defaults.allowOrdersAboveAvailableStock,
            'sales_reps_can_view_outstanding_balances':
                CompanySettings.defaults.salesRepsCanViewOutstandingBalances,
            'financial_visibility_policies':
                CompanySettings.defaults.financialVisibility.toJson(),
            'owner_setup_completed': true,
            'created_by': ?employeeId,
            'updated_by': ?employeeId,
          })
          .select(_select)
          .single();

      return CompanySettings.fromJson(Map<String, dynamic>.from(inserted));
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to create default settings.'
            : error.message,
      );
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<CompanySettings> updateSettings({
    required CompanySettings settings,
    required String employeeId,
  }) async {
    try {
      final updated = await _client
          .from('company_settings')
          .update(settings.toUpdatePayload(employeeId: employeeId))
          .eq('company_id', settings.companyId)
          .select(_select)
          .single();

      return CompanySettings.fromJson(Map<String, dynamic>.from(updated));
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        error.message.trim().isEmpty
            ? 'Unable to save settings.'
            : error.message,
      );
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Logo + colours only. Never sends [CompanySettings.customBrandingEnabled].
  Future<CompanySettings> updateBranding({
    required String companyId,
    required String employeeId,
    required String? logoUrl,
    required String? logoLightUrl,
    required String? primaryColor,
    required String? navBackgroundColor,
    bool? documentShowBusinessNameWithLogo,
  }) async {
    try {
      final updated = await _client
          .from('company_settings')
          .update({
            'logo_url': logoUrl,
            'logo_light_url': logoLightUrl,
            'primary_color': primaryColor,
            'nav_background_color': navBackgroundColor,
            'document_show_business_name_with_logo':
                ?documentShowBusinessNameWithLogo,
            'updated_by': employeeId,
          })
          .eq('company_id', companyId)
          .select(_select)
          .single();

      return CompanySettings.fromJson(Map<String, dynamic>.from(updated));
    } on PostgrestException catch (error) {
      throw _brandingFailure(error);
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  /// Business logo + document name toggle — available without Custom Branding.
  Future<CompanySettings> updateDocumentIdentity({
    required String companyId,
    required String employeeId,
    required String? logoUrl,
    required String? logoLightUrl,
    required bool showBusinessNameWithLogo,
  }) async {
    try {
      final updated = await _client
          .from('company_settings')
          .update({
            'logo_url': logoUrl,
            'logo_light_url': logoLightUrl,
            'document_show_business_name_with_logo': showBusinessNameWithLogo,
            'updated_by': employeeId,
          })
          .eq('company_id', companyId)
          .select(_select)
          .single();

      return CompanySettings.fromJson(Map<String, dynamic>.from(updated));
    } on PostgrestException catch (error) {
      throw _brandingFailure(error);
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<String> uploadLogo({
    required String companyId,
    required ProcessedMedia media,
    bool light = false,
  }) async {
    final stem = light ? 'logo-light' : 'logo';
    final path = '$companyId/$stem.${media.extension}';
    await _deleteLogoFiles(companyId, light: light);
    await _storage.uploadCompanyLogo(
      path: path,
      bytes: media.bytes,
      contentType: media.contentType,
    );
    final url = _storage.publicUrl(
      bucket: MediaConstants.companyBrandingBucket,
      path: path,
    );
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> removeLogo({
    required String companyId,
    bool light = false,
  }) {
    return _deleteLogoFiles(companyId, light: light);
  }

  Future<void> _deleteLogoFiles(
    String companyId, {
    bool light = false,
  }) async {
    const extensions = ['jpg', 'jpeg', 'png', 'webp'];
    final stem = light ? 'logo-light' : 'logo';
    try {
      await _storage.deleteMany(
        bucket: MediaConstants.companyBrandingBucket,
        paths: [
          for (final ext in extensions) '$companyId/$stem.$ext',
        ],
      );
    } catch (_) {
      // Missing objects or older files — settings row is the source of truth.
    }
  }

  AppFailure _brandingFailure(PostgrestException error) {
    final message = error.message.trim();
    final denied = error.code == '42501' ||
        message.toLowerCase().contains('permission') ||
        message.toLowerCase().contains('custom_branding_enabled');
    if (denied) {
      return AuthorizationFailure(
        message.isEmpty
            ? 'You do not have permission to update branding.'
            : message,
      );
    }
    return ValidationFailure(
      message.isEmpty ? 'Unable to save branding.' : message,
    );
  }

  /// Missing or unreadable rows fail open (complete) so existing tenants
  /// are never trapped in first-time setup.
  Future<bool> fetchOwnerSetupCompleted(String companyId) async {
    try {
      final row = await _client
          .from('company_settings')
          .select('owner_setup_completed')
          .eq('company_id', companyId)
          .maybeSingle();
      return row?['owner_setup_completed'] as bool? ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> markOwnerSetupCompleted({
    required String companyId,
    required String employeeId,
  }) async {
    try {
      await _client
          .from('company_settings')
          .update({
            'owner_setup_completed': true,
            'updated_by': employeeId,
          })
          .eq('company_id', companyId);
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to finish setup.'
            : error.message,
      );
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }
}
