import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/notifications/outbound/messaging_phone.dart';
import 'package:sello/shared/utils/phone_number.dart';

void main() {
  group('PhoneNumber.tryParse Sri Lanka default region', () {
    test('0765644465 → +94765644465', () {
      expect(PhoneNumber.tryParse('0765644465')?.e164, '+94765644465');
    });

    test('076 564 4465 → +94765644465', () {
      expect(PhoneNumber.tryParse('076 564 4465')?.e164, '+94765644465');
    });

    test('+94 76 564 4465 → +94765644465', () {
      expect(PhoneNumber.tryParse('+94 76 564 4465')?.e164, '+94765644465');
    });

    test('94765644465 → +94765644465', () {
      expect(PhoneNumber.tryParse('94765644465')?.e164, '+94765644465');
    });

    test('hyphens and parentheses are allowed', () {
      expect(PhoneNumber.tryParse('(076) 564-4465')?.e164, '+94765644465');
    });

    test('9-digit national number uses Sri Lanka', () {
      expect(PhoneNumber.tryParse('765644465')?.e164, '+94765644465');
    });
  });

  group('PhoneNumber international numbers', () {
    test('existing valid US number is not given a Sri Lanka prefix', () {
      expect(PhoneNumber.tryParse('+1 415 555 2671')?.e164, '+14155552671');
      expect(PhoneNumber.tryParse('+14155552671')?.smsRecipient, '14155552671');
    });

    test('00 international prefix is treated as +', () {
      expect(PhoneNumber.tryParse('0094765644465')?.e164, '+94765644465');
    });

    test('UK number with country code is kept', () {
      expect(PhoneNumber.tryParse('+447911123456')?.e164, '+447911123456');
    });
  });

  group('PhoneNumber rejects invalid or ambiguous input', () {
    test('too short', () {
      expect(PhoneNumber.tryParse('123'), isNull);
      expect(PhoneNumber.tryParse('07656'), isNull);
    });

    test('letters are rejected', () {
      expect(PhoneNumber.tryParse('076abc4465'), isNull);
    });

    test('10-digit number without trunk 0 is not assumed Sri Lankan', () {
      expect(PhoneNumber.tryParse('4155552671'), isNull);
    });

    test('does not rewrite invalid input into a different number', () {
      expect(PhoneNumber.normalizeStorage('07656'), isNull);
      expect(PhoneNumber.normalizeStorage('not-a-phone'), isNull);
    });

    test('blank is empty storage, not an error', () {
      expect(PhoneNumber.normalizeStorage(''), isNull);
      expect(PhoneNumber.normalizeStorage('   '), isNull);
      expect(PhoneNumber.validator(''), isNull);
      expect(PhoneNumber.validator('', required: true), isNotNull);
    });
  });

  group('PhoneNumber SMS and display', () {
    test('SMS receives digits without +', () {
      expect(PhoneNumber.tryParse('0765644465')?.smsRecipient, '94765644465');
      expect(MessagingPhone.international('0765644465'), '94765644465');
    });

    test('Test SMS uses the same normalization path', () {
      expect(
        MessagingPhone.international('076 564 4465'),
        PhoneNumber.tryParse('076 564 4465')?.smsRecipient,
      );
      expect(MessagingPhone.international('076 564 4465'), '94765644465');
    });

    test('WhatsApp uses the same country-code digits as SMS', () {
      expect(
        MessagingPhone.preferredWhatsApp(null, '0765644465'),
        '94765644465',
      );
      expect(MessagingPhone.preferredSms('0765644465', null), '94765644465');
    });

    test('Sri Lanka display is grouped, storage stays E.164', () {
      final parsed = PhoneNumber.tryParse('0765644465')!;
      expect(parsed.e164, '+94765644465');
      expect(parsed.display, '076 564 4465');
      expect(PhoneNumber.displayOf('+94765644465'), '076 564 4465');
    });

    test('legacy stored local numbers still parse for SMS', () {
      expect(MessagingPhone.international('0771234567'), '94771234567');
    });
  });
}
