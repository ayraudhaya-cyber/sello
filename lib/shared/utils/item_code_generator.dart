/// Deterministic, business-agnostic item-code suggestions.
///
/// Parent: `ROLEX TOWER BOLT` -> `ROLEXTB`.
/// Variant: parent `ROLEXTB` + option `4 INCHES` -> `ROLEXTB4`.
///
/// Output is always upper-case letters and digits only (no spaces or
/// punctuation), which satisfies `products.sku` / `product_variants.sku`
/// (non-blank, unique per company among live rows).
abstract final class ItemCodeGenerator {
  static const int maxParentLength = 10;
  static const int maxVariantSuffixLength = 6;
  static const int maxLength = 20;

  static const _joinerWords = {
    'AND',
    'OF',
    'THE',
    'FOR',
    'WITH',
    'A',
    'AN',
    'IN',
    'ON',
    'TO',
  };

  /// Unit words that add no meaning after a number ("4 INCHES" -> 4).
  static const _redundantUnitWords = {
    'INCH',
    'INCHES',
    'IN',
    'PC',
    'PCS',
    'PIECE',
    'PIECES',
    'NO',
    'NOS',
    'UNIT',
    'UNITS',
  };

  static const _sizeWords = {
    'XSMALL': 'XS',
    'SMALL': 'S',
    'MEDIUM': 'M',
    'LARGE': 'L',
    'XLARGE': 'XL',
    'XXLARGE': 'XXL',
    'EXTRALARGE': 'XL',
  };

  /// Suggests a parent code from a product name. Empty when the name has no
  /// letters or digits.
  static String parentFromName(String name) {
    final tokens = _tokens(name);
    if (tokens.isEmpty) return '';

    if (tokens.length == 1) {
      return _clip(tokens.first, 8);
    }

    final buffer = StringBuffer();
    var first = true;
    for (final token in tokens) {
      if (first) {
        buffer.write(_clip(token, 6));
        first = false;
        continue;
      }
      if (_joinerWords.contains(token)) continue;
      if (_hasDigit(token)) {
        buffer.write(_clip(token, 5));
      } else {
        buffer.write(token[0]);
      }
    }
    final result = buffer.toString();
    return _clip(result.isEmpty ? tokens.first : result, maxParentLength);
  }

  /// Suggests a variant code from the parent code and the option value.
  /// Empty when either input has no usable characters.
  static String variantFromOption({
    required String parentCode,
    required String optionLabel,
  }) {
    final parent = normalize(parentCode);
    if (parent.isEmpty) return '';
    final suffix = _optionSuffix(optionLabel);
    if (suffix.isEmpty) return '';
    return _clip('$parent$suffix', maxLength);
  }

  /// Returns [base] when free, otherwise the first free variation.
  ///
  /// Comparison is case-insensitive. Variants use a letter suffix (so
  /// `ROLEXTB4` -> `ROLEXTB4A`) to avoid reading like a different size;
  /// parents use a number (`ROLEXTB` -> `ROLEXTB2`).
  static String makeUnique(
    String base,
    Iterable<String> taken, {
    bool letterSuffix = false,
  }) {
    final code = normalize(base);
    if (code.isEmpty) return '';
    final used = {for (final t in taken) normalize(t)};
    if (!used.contains(code)) return code;

    if (letterSuffix) {
      for (final unit in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) {
        final candidate = _withSuffix(code, unit);
        if (!used.contains(candidate)) return candidate;
      }
    }
    for (var n = 2; n < 10000; n++) {
      final candidate = _withSuffix(code, '$n');
      if (!used.contains(candidate)) return candidate;
    }
    return code;
  }

  /// Upper-cases and strips everything except letters and digits.
  static String normalize(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String _withSuffix(String code, String suffix) {
    final room = maxLength - suffix.length;
    final head = code.length > room ? code.substring(0, room) : code;
    return '$head$suffix';
  }

  static String _optionSuffix(String label) {
    final raw = label.toUpperCase().replaceAllMapped(
      RegExp(r'(\d)\.(\d)'),
      (m) => '${m[1]}P${m[2]}',
    );
    final tokens = _tokens(raw);
    if (tokens.isEmpty) return '';

    final alphaCount = tokens
        .where((t) => !_hasDigit(t) && !_redundantUnitWords.contains(t))
        .length;

    final buffer = StringBuffer();
    var previousWasNumber = false;
    for (final token in tokens) {
      final isNumber = _hasDigit(token);
      if (isNumber) {
        buffer.write(token);
        previousWasNumber = true;
        continue;
      }
      if (previousWasNumber && _redundantUnitWords.contains(token)) {
        previousWasNumber = false;
        continue;
      }
      previousWasNumber = false;
      final size = _sizeWords[token];
      if (size != null) {
        buffer.write(size);
      } else if (alphaCount > 1) {
        buffer.write(token[0]);
      } else {
        buffer.write(_clip(token, 3));
      }
    }
    return _clip(buffer.toString(), maxVariantSuffixLength);
  }

  static List<String> _tokens(String value) {
    return [
      for (final part in value.toUpperCase().split(RegExp(r'[^A-Z0-9]+')))
        if (part.isNotEmpty) part,
    ];
  }

  static bool _hasDigit(String value) => RegExp(r'\d').hasMatch(value);

  static String _clip(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);
}
