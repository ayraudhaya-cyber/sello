import 'package:sello/shared/utils/phone_number.dart';

/// Best-effort phone normalization for WhatsApp / SMS.
///
/// Delegates to [PhoneNumber] so every channel uses the same E.164 rules.
abstract final class MessagingPhone {
  /// International digits for Text.lk (`947XXXXXXXX`), no leading `+`.
  static String? international(String? raw) =>
      PhoneNumber.tryParse(raw)?.smsRecipient;

  /// Digits for `wa.me` deep links (country code, no `+`).
  static String? digits(String? raw) =>
      PhoneNumber.tryParse(raw)?.whatsappDigits;

  /// Prefer WhatsApp number, then phone.
  static String? preferredWhatsApp(String? whatsapp, String? phone) =>
      digits(whatsapp) ?? digits(phone);

  static String? preferredSms(String? phone, String? whatsapp) =>
      international(phone) ?? international(whatsapp);
}

/// Tenant SMS Sender ID (public name, not an API secret).
abstract final class SmsSenderId {
  static const maxLength = 11;
  static final format = RegExp(r'^[A-Za-z0-9]{3,11}$');

  /// Exact Text.lk format. Does not strip or rewrite invalid input.
  static String? tryParse(String? raw) {
    final value = raw?.trim() ?? '';
    if (!format.hasMatch(value)) return null;
    return value;
  }

  /// Text.lk-approved IDs: 3–11 letters or digits, casing preserved.
  /// Strips spaces/punctuation as the user types; does not invent a new ID
  /// from an unrelated string beyond dropping illegal characters.
  static String? normalize(String? raw) {
    if (raw == null) return null;
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      final isUpper = rune >= 65 && rune <= 90;
      final isLower = rune >= 97 && rune <= 122;
      final isDigit = rune >= 48 && rune <= 57;
      if (isUpper || isLower || isDigit) buffer.writeCharCode(rune);
      if (buffer.length >= maxLength) break;
    }
    return tryParse(buffer.toString());
  }
}
