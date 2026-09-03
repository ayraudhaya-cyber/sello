import 'package:shared_preferences/shared_preferences.dart';

/// Product catalog layout modes for Sales Rep ordering.
enum ProductCatalogLayoutMode {
  gridTwo,
  gridOne,
  list,
}

extension ProductCatalogLayoutModeX on ProductCatalogLayoutMode {
  String get storageKey => name;

  static ProductCatalogLayoutMode fromStorage(String? raw) {
    return switch (raw) {
      'gridOne' => ProductCatalogLayoutMode.gridOne,
      'list' => ProductCatalogLayoutMode.list,
      _ => ProductCatalogLayoutMode.gridTwo,
    };
  }
}

/// Persists the Sales Rep catalog layout preference locally (not Supabase).
class SalesCatalogLayoutPreferencesStore {
  SalesCatalogLayoutPreferencesStore();

  static const _key = 'sales.catalog_layout_mode';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<ProductCatalogLayoutMode> load() async {
    final prefs = await _preferences;
    return ProductCatalogLayoutModeX.fromStorage(prefs.getString(_key));
  }

  Future<void> save(ProductCatalogLayoutMode mode) async {
    final prefs = await _preferences;
    await prefs.setString(_key, mode.storageKey);
  }
}
