import 'package:sello/core/error/app_failure.dart';
import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/shared/models/product_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductFieldsRepository {
  ProductFieldsRepository({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  Future<ProductFieldConfig> fetchForCompany(String companyId) async {
    try {
      await _client.rpc(
        'ensure_company_product_fields',
        params: {'p_company_id': companyId},
      );

      final rows = await _client
          .from('company_product_fields')
          .select('''
            id,
            company_id,
            field_key,
            enabled,
            required,
            show_in_list,
            show_in_catalog,
            label_override,
            sort_order,
            options_override,
            product_field_definitions (
              key,
              label,
              field_type,
              storage,
              column_name,
              options,
              help_text,
              sort_order,
              group_key,
              settings_visible
            )
          ''')
          .eq('company_id', companyId)
          .order('sort_order');

      final fields = (rows as List)
          .whereType<Map>()
          .map((row) => CompanyProductField.fromJoinedRow(
                Map<String, dynamic>.from(row),
              ))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      return ProductFieldConfig(fields: fields);
    } on PostgrestException catch (error) {
      throw UnexpectedFailure(
        error.message.trim().isEmpty
            ? 'Unable to load product details.'
            : error.message,
      );
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> updateField({
    required String companyId,
    required CompanyProductField field,
  }) async {
    try {
      await _client
          .from('company_product_fields')
          .update(field.toUpdatePayload())
          .eq('company_id', companyId)
          .eq('field_key', field.fieldKey);
    } on PostgrestException catch (error) {
      throw ValidationFailure(
        error.message.trim().isEmpty
            ? 'Unable to save product detail.'
            : error.message,
      );
    } catch (error) {
      throw UnexpectedFailure(error.toString());
    }
  }

  Future<void> updateFields({
    required String companyId,
    required List<CompanyProductField> fields,
  }) async {
    for (final field in fields) {
      await updateField(companyId: companyId, field: field);
    }
  }
}
