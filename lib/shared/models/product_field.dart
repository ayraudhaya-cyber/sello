import 'package:equatable/equatable.dart';

enum ProductFieldType {
  text,
  multiline,
  number,
  select,
  country,
  date,
  colour,
  currency,
  barcode,
  boolean;

  static ProductFieldType fromDb(String? value) {
    return switch (value) {
      'multiline' => ProductFieldType.multiline,
      'number' => ProductFieldType.number,
      'select' => ProductFieldType.select,
      'country' => ProductFieldType.country,
      'date' => ProductFieldType.date,
      'colour' || 'color' => ProductFieldType.colour,
      'currency' => ProductFieldType.currency,
      'barcode' => ProductFieldType.barcode,
      'boolean' => ProductFieldType.boolean,
      _ => ProductFieldType.text,
    };
  }

  String get dbValue => name;

  String get label => switch (this) {
        ProductFieldType.text => 'Text',
        ProductFieldType.multiline => 'Long text',
        ProductFieldType.number => 'Number',
        ProductFieldType.select => 'Dropdown',
        ProductFieldType.country => 'Country',
        ProductFieldType.date => 'Date',
        ProductFieldType.colour => 'Colour',
        ProductFieldType.currency => 'Currency',
        ProductFieldType.barcode => 'Barcode',
        ProductFieldType.boolean => 'Yes / No',
      };
}

enum ProductFieldStorage {
  column,
  attribute,
  inventory;

  static ProductFieldStorage fromDb(String? value) {
    return switch (value) {
      'attribute' => ProductFieldStorage.attribute,
      'inventory' => ProductFieldStorage.inventory,
      _ => ProductFieldStorage.column,
    };
  }

  String get dbValue => name;
}

/// Suggested Product Details grouping for Settings discoverability.
enum ProductDetailGroup {
  common,
  hardware,
  stationery,
  electrical,
  furniture,
  grocery,
  pharmacy,
  clothing,
  other;

  String get key => name;

  String get label => switch (this) {
        ProductDetailGroup.common => 'Common',
        ProductDetailGroup.hardware => 'Hardware',
        ProductDetailGroup.stationery => 'Stationery',
        ProductDetailGroup.electrical => 'Electrical',
        ProductDetailGroup.furniture => 'Furniture',
        ProductDetailGroup.grocery => 'Grocery',
        ProductDetailGroup.pharmacy => 'Pharmacy',
        ProductDetailGroup.clothing => 'Clothing',
        ProductDetailGroup.other => 'Other',
      };

  String get emoji => switch (this) {
        ProductDetailGroup.common => '★',
        ProductDetailGroup.hardware => '🔧',
        ProductDetailGroup.stationery => '📚',
        ProductDetailGroup.electrical => '⚡',
        ProductDetailGroup.furniture => '🛋',
        ProductDetailGroup.grocery => '🛒',
        ProductDetailGroup.pharmacy => '💊',
        ProductDetailGroup.clothing => '👕',
        ProductDetailGroup.other => '•',
      };

  static ProductDetailGroup fromDb(String? value) {
    return switch (value) {
      'hardware' => ProductDetailGroup.hardware,
      'stationery' => ProductDetailGroup.stationery,
      'electrical' => ProductDetailGroup.electrical,
      'furniture' => ProductDetailGroup.furniture,
      'grocery' => ProductDetailGroup.grocery,
      'pharmacy' => ProductDetailGroup.pharmacy,
      'clothing' => ProductDetailGroup.clothing,
      'other' => ProductDetailGroup.other,
      _ => ProductDetailGroup.common,
    };
  }

  /// Display order — Common always first.
  static const List<ProductDetailGroup> settingsOrder = [
    ProductDetailGroup.common,
    ProductDetailGroup.hardware,
    ProductDetailGroup.stationery,
    ProductDetailGroup.electrical,
    ProductDetailGroup.furniture,
    ProductDetailGroup.grocery,
    ProductDetailGroup.pharmacy,
    ProductDetailGroup.clothing,
    ProductDetailGroup.other,
  ];
}

/// Global catalog entry for a configurable product field.
class ProductFieldDefinition extends Equatable {
  const ProductFieldDefinition({
    required this.key,
    required this.label,
    required this.fieldType,
    required this.storage,
    this.columnName,
    this.options = const [],
    this.helpText,
    this.sortOrder = 100,
    this.group = ProductDetailGroup.common,
    this.settingsVisible = true,
  });

  final String key;
  final String label;
  final ProductFieldType fieldType;
  final ProductFieldStorage storage;
  final String? columnName;
  final List<String> options;
  final String? helpText;
  final int sortOrder;
  final ProductDetailGroup group;
  final bool settingsVisible;

  factory ProductFieldDefinition.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final options = <String>[];
    if (rawOptions is List) {
      for (final item in rawOptions) {
        if (item != null) options.add(item.toString());
      }
    }
    return ProductFieldDefinition(
      key: json['key'] as String,
      label: json['label'] as String,
      fieldType: ProductFieldType.fromDb(json['field_type'] as String?),
      storage: ProductFieldStorage.fromDb(json['storage'] as String?),
      columnName: json['column_name'] as String?,
      options: options,
      helpText: json['help_text'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 100,
      group: ProductDetailGroup.fromDb(json['group_key'] as String?),
      settingsVisible: json['settings_visible'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [
        key,
        label,
        fieldType,
        storage,
        columnName,
        options,
        helpText,
        sortOrder,
        group,
        settingsVisible,
      ];
}

/// Company enablement + placement for one field.
class CompanyProductField extends Equatable {
  const CompanyProductField({
    required this.id,
    required this.companyId,
    required this.fieldKey,
    required this.enabled,
    required this.required,
    required this.showInList,
    required this.showInCatalog,
    required this.sortOrder,
    required this.definition,
    this.labelOverride,
    this.optionsOverride,
  });

  final String id;
  final String companyId;
  final String fieldKey;
  final bool enabled;
  final bool required;
  final bool showInList;
  final bool showInCatalog;
  final int sortOrder;
  final String? labelOverride;
  final List<String>? optionsOverride;
  final ProductFieldDefinition definition;

  String get label =>
      (labelOverride != null && labelOverride!.trim().isNotEmpty)
          ? labelOverride!.trim()
          : definition.label;

  /// Company override wins; otherwise catalog defaults.
  List<String> get effectiveOptions {
    final override = optionsOverride;
    if (override != null && override.isNotEmpty) return override;
    return definition.options;
  }

  bool get isSelect => definition.fieldType == ProductFieldType.select;

  CompanyProductField copyWith({
    bool? enabled,
    bool? required,
    bool? showInList,
    bool? showInCatalog,
    int? sortOrder,
    String? labelOverride,
    List<String>? optionsOverride,
    bool clearOptionsOverride = false,
  }) {
    return CompanyProductField(
      id: id,
      companyId: companyId,
      fieldKey: fieldKey,
      enabled: enabled ?? this.enabled,
      required: required ?? this.required,
      showInList: showInList ?? this.showInList,
      showInCatalog: showInCatalog ?? this.showInCatalog,
      sortOrder: sortOrder ?? this.sortOrder,
      labelOverride: labelOverride ?? this.labelOverride,
      optionsOverride: clearOptionsOverride
          ? null
          : (optionsOverride ?? this.optionsOverride),
      definition: definition,
    );
  }

  factory CompanyProductField.fromJoinedRow(Map<String, dynamic> json) {
    final defRaw = json['product_field_definitions'];
    final defMap = defRaw is Map<String, dynamic>
        ? defRaw
        : defRaw is Map
            ? Map<String, dynamic>.from(defRaw)
            : <String, dynamic>{
                'key': json['field_key'],
                'label': json['field_key'],
                'field_type': 'text',
                'storage': 'attribute',
                'sort_order': 100,
              };

    List<String>? optionsOverride;
    final rawOverride = json['options_override'];
    if (rawOverride is List) {
      optionsOverride = [
        for (final item in rawOverride)
          if (item != null) item.toString(),
      ];
    }

    return CompanyProductField(
      id: json['id'] as String,
      companyId: json['company_id'] as String,
      fieldKey: json['field_key'] as String,
      enabled: json['enabled'] as bool? ?? false,
      required: json['required'] as bool? ?? false,
      showInList: json['show_in_list'] as bool? ?? false,
      showInCatalog: json['show_in_catalog'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 100,
      labelOverride: json['label_override'] as String?,
      optionsOverride: optionsOverride,
      definition: ProductFieldDefinition.fromJson(defMap),
    );
  }

  Map<String, dynamic> toUpdatePayload() {
    return {
      'enabled': enabled,
      'required': required,
      'show_in_list': showInList,
      'show_in_catalog': showInCatalog,
      'sort_order': sortOrder,
      'label_override': labelOverride,
      'options_override': optionsOverride,
    };
  }

  @override
  List<Object?> get props => [
        id,
        companyId,
        fieldKey,
        enabled,
        required,
        showInList,
        showInCatalog,
        sortOrder,
        labelOverride,
        optionsOverride,
        definition,
      ];
}

/// Resolved product field config for forms / catalog / list.
class ProductFieldConfig extends Equatable {
  ProductFieldConfig({required List<CompanyProductField> fields})
      : fields = List.unmodifiable(
          [...fields]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
        );

  final List<CompanyProductField> fields;

  /// Fields that appear in Product Details settings (excludes standard columns).
  List<CompanyProductField> get forSettings => fields
      .where((f) => f.definition.settingsVisible && f.fieldKey != 'description')
      .toList(growable: false);

  List<CompanyProductField> get enabled =>
      fields.where((f) => f.enabled).toList(growable: false);

  List<CompanyProductField> get forEditor => enabled;

  List<CompanyProductField> get forList =>
      enabled.where((f) => f.showInList).toList(growable: false);

  List<CompanyProductField> get forCatalog =>
      enabled.where((f) => f.showInCatalog).toList(growable: false);

  bool isEnabled(String key) =>
      fields.any((f) => f.fieldKey == key && f.enabled);

  CompanyProductField? byKey(String key) {
    for (final field in fields) {
      if (field.fieldKey == key) return field;
    }
    return null;
  }

  @override
  List<Object?> get props => [fields];
}
