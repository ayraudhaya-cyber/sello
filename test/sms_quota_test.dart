import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sello/shared/models/sms_quota.dart';

void main() {
  group('high-water mark', () {
    test('A. first balance starts the pack at the live remainder', () {
      final quota = SmsQuota.observe(storedBaseline: null, remaining: 100);

      expect(quota.baseline, 100);
      expect(quota.used, 0);
      expect(quota.remainingPercent, 100);
      expect(quota.caption, '0 used / 100');
      expect(quota.tooltip, '100 SMS left · 0 used of 100');
      expect(quota.isLow, isFalse);
      expect(quota.isCritical, isFalse);
    });

    test('B. sending SMS keeps the pack and counts used units', () {
      final quota = SmsQuota.observe(storedBaseline: 100, remaining: 80);

      expect(quota.baseline, 100);
      expect(quota.used, 20);
      expect(quota.remaining, 80);
      expect(quota.remainingPercent, closeTo(80, 0.001));
    });

    test('C. a higher live balance becomes the new pack and used resets', () {
      final quota = SmsQuota.observe(storedBaseline: 5, remaining: 505);

      expect(quota.baseline, 505);
      expect(quota.used, 0);
      expect(quota.caption, '0 used / 505');
      expect(quota.tooltip, '505 SMS left · 0 used of 505');
      expect(quota.remainingPercent, 100);
    });

    test('C2. usage after that top-up keeps the new pack', () {
      final afterSend = SmsQuota.observe(storedBaseline: 505, remaining: 495);

      expect(afterSend.baseline, 505);
      expect(afterSend.used, 10);
      expect(afterSend.caption, '10 used / 505');
      expect(afterSend.tooltip, '495 SMS left · 10 used of 505');
    });

    test('D. use after a top-up counts only against the new pack', () {
      final toppedUp = SmsQuota.observe(storedBaseline: 100, remaining: 580);
      final afterSend = SmsQuota.observe(
        storedBaseline: toppedUp.baseline,
        remaining: 550,
      );

      expect(afterSend.baseline, 580);
      expect(afterSend.used, 30);
      expect(afterSend.remainingPercent, closeTo(550 / 580 * 100, 0.001));
    });

    test('E. a lower balance does not shrink the pack', () {
      final quota = SmsQuota.observe(storedBaseline: 580, remaining: 400);

      expect(quota.baseline, 580);
      expect(quota.used, 180);
    });

    test('low balance is amber at 20% left and red below 25 SMS', () {
      final amber = SmsQuota.observe(storedBaseline: 200, remaining: 40);
      final justAbove = SmsQuota.observe(storedBaseline: 100, remaining: 25);
      final red = SmsQuota.observe(storedBaseline: 100, remaining: 24);
      final healthy = SmsQuota.observe(storedBaseline: 100, remaining: 50);

      expect(justAbove.isCritical, isFalse);
      expect(justAbove.isLow, isFalse);
      expect(amber.isLow, isTrue);
      expect(amber.isCritical, isFalse);
      expect(red.isCritical, isTrue);
      expect(red.isLow, isFalse);
      expect(healthy.isLow, isFalse);
      expect(healthy.isCritical, isFalse);
      expect(
        red.tooltip,
        contains('To top up this quota, contact the Sello team on 0765644465.'),
      );
      expect(justAbove.tooltip, isNot(contains('0765644465')));
    });
  });

  group('client payload', () {
    test('F. no company token hides the quota block', () {
      expect(SmsQuota.tryParse({'status': 'unconfigured'}), isNull);
      expect(SmsQuota.tryParse({'status': 'hidden'}), isNull);
      expect(SmsQuota.tryParse(null), isNull);
    });

    test('G. a token on the payload is not kept for the client', () {
      final quota = SmsQuota.tryParse({
        'status': 'ok',
        'remaining': 80,
        'baseline': 100,
        'used': 20,
        'remaining_percent': 80,
        'expires_on': '13th Sep 26, 9:56 PM',
        'textlk_api_token': '7449|secret',
      });

      expect(quota, isNotNull);
      expect(quota!.used, 20);
      expect(quota.caption, '20 used / 100');
      expect(quota.tooltip, '80 SMS left · 20 used of 100');
      expect(quota.tooltip, isNot(contains('until')));
      expect(quota.tooltip, isNot(contains('xpir')));
      expect(quota.tooltip, isNot(contains('Sep')));
      expect(quota.toClientJson().containsKey('textlk_api_token'), isFalse);
      expect(quota.toClientJson().values.join(), isNot(contains('7449|')));
    });

    test('quota response and send fallback do not return the token', () {
      final quotaSource = File(
        'supabase/functions/sms-quota/index.ts',
      ).readAsStringSync();
      final sendSource = File(
        'supabase/functions/send-outbound-sms/index.ts',
      ).readAsStringSync();

      expect(quotaSource, contains("status: \"unconfigured\""));
      expect(quotaSource, isNot(contains('textlk_api_token,')));
      expect(
        quotaSource.substring(quotaSource.lastIndexOf('return json({')),
        isNot(contains('textlk_api_token')),
      );
      expect(sendSource, contains('return tenantToken || envToken'));
    });
  });
}
