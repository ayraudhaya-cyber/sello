import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/data/providers/repository_providers.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/shared/models/product_field.dart';

/// Tenant product field configuration — Hub + Sales consumers.
final productFieldConfigProvider =
    AsyncNotifierProvider<ProductFieldConfigNotifier, ProductFieldConfig>(
  ProductFieldConfigNotifier.new,
);

class ProductFieldConfigNotifier extends AsyncNotifier<ProductFieldConfig> {
  @override
  Future<ProductFieldConfig> build() async {
    final session = ref.watch(currentSessionProvider);
    if (session == null) {
      return ProductFieldConfig(fields: []);
    }
    return ref
        .read(productFieldsRepositoryProvider)
        .fetchForCompany(session.company.id);
  }

  Future<String?> save(List<CompanyProductField> draft) async {
    final session = ref.read(currentSessionProvider);
    if (session == null) return 'Not signed in.';
    try {
      await ref.read(productFieldsRepositoryProvider).updateFields(
            companyId: session.company.id,
            fields: draft,
          );
      state = AsyncData(ProductFieldConfig(fields: List.of(draft)));
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = AsyncData(await build());
  }
}
