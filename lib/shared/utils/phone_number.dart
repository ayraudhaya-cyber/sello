/// Canonical phone numbers for Sello.
///
/// Storage is E.164 (`+94765644465`). Users may type local or international
/// forms. Sri Lanka is the default region only when the input has no country
/// code (`0…` trunk, 9-digit national, or `94` + national). Numbers that
/// already include `+` / `00` are treated as international and are never
/// given a Sri Lankan prefix.
///
/// Invalid or ambiguous input returns null — it is never rewritten into a
/// different number. Existing mixed DB values are parsed at use/save time;
/// there is no production backfill.
class PhoneNumber {
  const PhoneNumber._(this.e164);

  /// E.164 with a leading `+`, e.g. `+94765644465`.
  final String e164;

  static const defaultCallingCode = '94';
  static const _lkNsnLength = 9;
  static const _minIntlDigits = 8;
  static const _maxIntlDigits = 15;

  /// Digits only, for Text.lk `recipient` and `wa.me` (no `+`).
  String get smsRecipient => e164.substring(1);

  /// Same as [smsRecipient] — WhatsApp deep links use country code, no `+`.
  String get whatsappDigits => smsRecipient;

  /// Readable national form for Sri Lanka; E.164 otherwise.
  String get display {
    if (e164.startsWith('+94') && e164.length == 12) {
      final nsn = e164.substring(3);
      return '0${nsn.substring(0, 2)} ${nsn.substring(2, 5)} ${nsn.substring(5)}';
    }
    return e164;
  }

  /// Parse user or stored input. Null if empty, invalid, or ambiguous.
  static PhoneNumber? tryParse(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (!_onlyPhoneChars(text)) return null;

    final international =
        text.startsWith('+') || _digitsOf(text).startsWith('00');
    var digits = _digitsOf(text);
    if (digits.isEmpty) return null;
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
      if (digits.isEmpty) return null;
    }

    if (international) return _fromInternational(digits);
    return _fromDefaultRegion(digits);
  }

  /// E.164 for persistence, or null when [raw] is blank.
  /// Invalid non-empty input returns null (callers must validate first).
  static String? normalizeStorage(String? raw) {
    final trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return tryParse(trimmed)?.e164;
  }

  /// Friendly display for a stored value. Unparseable legacy text is shown as-is.
  static String displayOf(String? stored) {
    final trimmed = stored?.trim() ?? '';
    if (trimmed.isEmpty) return '';
    return tryParse(trimmed)?.display ?? trimmed;
  }

  static String? displayOrNull(String? stored) {
    final value = displayOf(stored);
    return value.isEmpty ? null : value;
  }

  /// Form validator. Blank is allowed unless [required] is true.
  static String? validator(String? value, {bool required = false}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return required ? 'Enter a valid phone number.' : null;
    }
    if (tryParse(trimmed) == null) {
      return 'Enter a valid phone number.';
    }
    return null;
  }

  static PhoneNumber? _fromInternational(String digits) {
    if (digits.startsWith('0')) return null;
    if (digits.startsWith(defaultCallingCode)) {
      if (digits.length != defaultCallingCode.length + _lkNsnLength) {
        return null;
      }
      if (digits[defaultCallingCode.length] == '0') return null;
      return PhoneNumber._('+$digits');
    }
    if (digits.length < _minIntlDigits || digits.length > _maxIntlDigits) {
      return null;
    }
    return PhoneNumber._('+$digits');
  }

  static PhoneNumber? _fromDefaultRegion(String digits) {
    if (digits.startsWith('0')) {
      final nsn = digits.substring(1);
      if (nsn.length != _lkNsnLength || nsn.startsWith('0')) return null;
      return PhoneNumber._('+$defaultCallingCode$nsn');
    }
    if (digits.startsWith(defaultCallingCode) &&
        digits.length == defaultCallingCode.length + _lkNsnLength) {
      if (digits[defaultCallingCode.length] == '0') return null;
      return PhoneNumber._('+$digits');
    }
    if (digits.length == _lkNsnLength && !digits.startsWith('0')) {
      return PhoneNumber._('+$defaultCallingCode$digits');
    }
    return null;
  }

  static bool _onlyPhoneChars(String text) {
    for (final code in text.codeUnits) {
      final isDigit = code >= 48 && code <= 57;
      final isPlus = code == 43;
      final isSep =
          code == 32 ||
          code == 45 ||
          code == 40 ||
          code == 41 ||
          code == 46 ||
          code == 47;
      if (!isDigit && !isPlus && !isSep) return false;
    }
    return true;
  }

  static String _digitsOf(String text) {
    final buffer = StringBuffer();
    for (final code in text.codeUnits) {
      if (code >= 48 && code <= 57) buffer.writeCharCode(code);
    }
    return buffer.toString();
  }
}
