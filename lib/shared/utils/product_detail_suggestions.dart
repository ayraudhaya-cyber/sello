/// Curated suggestion lists for Product Details controls.
///
/// Used as autocomplete hints — custom values are always allowed.
/// Display order of fields themselves comes from [CompanyProductField.sortOrder],
/// not from this catalog.
abstract final class ProductDetailSuggestions {
  static const materials = <String>[
    'Aluminum',
    'Brass',
    'Bronze',
    'Carbon steel',
    'Ceramic',
    'Chrome',
    'Glass',
    'Leather',
    'Plastic',
    'Plywood',
    'Rubber',
    'Stainless steel',
    'Steel',
    'Wood',
    'Zinc',
  ];

  static const colors = <String>[
    'Black',
    'White',
    'Silver',
    'Gold',
    'Chrome',
    'Brass',
    'Bronze',
    'Grey',
    'Brown',
    'Beige',
    'Red',
    'Blue',
    'Green',
    'Yellow',
    'Orange',
    'Pink',
    'Purple',
    'Clear',
    'Matte black',
    'Antique brass',
  ];

  static const sizes = <String>[
    'XS',
    'S',
    'M',
    'L',
    'XL',
    'XXL',
    'Small',
    'Medium',
    'Large',
    'One size',
    'Custom',
  ];

  static const brands = <String>[
    'Generic',
    'OEM',
    'Private label',
  ];

  static const finishes = <String>[
    'Matte',
    'Gloss',
    'Satin',
    'Powder coated',
    'Anodized',
    'Polished',
    'Brushed',
    'Painted',
    'Natural',
  ];

  /// Suggestions for a field key, merged with any definition options.
  static List<String> forKey(String fieldKey, {List<String> options = const []}) {
    final curated = switch (fieldKey) {
      'material' => materials,
      'color' || 'colour' => colors,
      'size' => sizes,
      'brand' => brands,
      'finish' => finishes,
      _ => const <String>[],
    };

    final seen = <String>{};
    final merged = <String>[];
    for (final value in [...options, ...curated]) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      merged.add(trimmed);
    }
    return merged;
  }

  static bool usesAutocomplete(String fieldKey) {
    return switch (fieldKey) {
      'material' ||
      'color' ||
      'colour' ||
      'size' ||
      'brand' ||
      'finish' =>
        true,
      _ => false,
    };
  }
}
