import 'package:intl/intl.dart';

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

  static String quantity(num value) {
    if (value == value.roundToDouble()) {
      return _quantityWhole.format(value.round());
    }
    return _quantityDecimal.format(value);
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
