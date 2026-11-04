import 'package:intl/intl.dart';
import 'package:sello/shared/models/company_settings.dart';

abstract final class SelloFormatters {
  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'en_US',
    symbol: '\$',
    decimalDigits: 2,
  );

  static final NumberFormat _quantityWhole = NumberFormat.decimalPattern(
    'en_US',
  );
  static final NumberFormat _quantityDecimal = NumberFormat.decimalPattern(
    'en_US',
  );
  static final DateFormat _date = DateFormat('dd MMM yyyy');

  static String currency(num value, {String? symbol}) {
    if (symbol != null && symbol.isNotEmpty) {
      return NumberFormat.currency(
        locale: 'en_US',
        symbol: symbol,
        decimalDigits: 2,
      ).format(value);
    }
    return _currency.format(value);
  }

  /// Summary cards and insight lines. [AmountDisplayStyle.exact] matches [currency].
  ///
  /// Lakhs and millions only shorten amounts large enough for that unit.
  /// Smaller amounts stay exact so a few thousand does not become `0.08m`.
  static String summaryAmount(
    num value, {
    required String symbol,
    required AmountDisplayStyle style,
  }) {
    final exact = currency(value, symbol: symbol);
    final scaled = switch (style) {
      AmountDisplayStyle.lakhs => _scaled(value, 100000),
      AmountDisplayStyle.millions => _scaled(value, 1000000),
      AmountDisplayStyle.exact => null,
    };
    if (scaled == null) return exact;
    final unit = style == AmountDisplayStyle.lakhs
        ? (scaled.$1 == '1' ? 'lakh' : 'lakhs')
        : 'm';
    final body = unit == 'm' ? '${scaled.$1}$unit' : '${scaled.$1} $unit';
    final text = '$symbol$body';
    return scaled.$2 ? '-$text' : text;
  }

  /// Absolute scaled text, and whether the original value was negative.
  static (String, bool)? _scaled(num value, num divisor) {
    final abs = value.abs();
    if (abs < divisor) return null;
    final scaled = abs / divisor;
    final digits = scaled >= 100 ? 0 : (scaled >= 10 ? 1 : 2);
    var text = scaled.toStringAsFixed(digits);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return (text, value < 0);
  }

  static String quantity(num value) {
    if (value == value.roundToDouble()) {
      return _quantityWhole.format(value.round());
    }
    return _quantityDecimal.format(value);
  }

  /// Reads a quantity typed or prefilled with grouping, such as `5,000`.
  static num? tryParseQuantity(String raw) {
    final cleaned = raw.trim().replaceAll(',', '').replaceAll(' ', '');
    if (cleaned.isEmpty) return null;
    return num.tryParse(cleaned);
  }

  static String date(DateTime? value) {
    if (value == null) return '-';
    return _date.format(value.toLocal());
  }

  static String dateTime(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('dd MMM yyyy · HH:mm').format(value.toLocal());
  }

  /// Display symbol for company currency codes.
  static String currencySymbol(String? currencyCode) {
    return switch ((currencyCode ?? 'USD').trim().toUpperCase()) {
      'LKR' => 'Rs ',
      'EUR' => '€',
      'GBP' => '£',
      'INR' => '₹',
      'JPY' => '¥',
      _ => '\$',
    };
  }
}
