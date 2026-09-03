import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/employees/employee_login_invite_response.dart';

void main() {
  group('EmployeeLoginInviteResponse', () {
    test('function name is invite-employee-login', () {
      expect(
        EmployeeLoginInviteResponse.functionName,
        'invite-employee-login',
      );
    });

    test('parses successful invite payload', () {
      final invite = EmployeeLoginInviteResponse.tryParseSuccess({
        'ok': true,
        'account_ready': true,
        'email_delivered': true,
      });
      expect(invite, isNotNull);
      expect(invite!.accountReady, isTrue);
      expect(invite.emailDelivered, isTrue);
      expect(invite.emailUnavailable, isFalse);
    });

    test('parses account ready when email delivery failed', () {
      final invite = EmployeeLoginInviteResponse.tryParseSuccess({
        'ok': true,
        'account_ready': true,
        'email_delivered': false,
      });
      expect(invite, isNotNull);
      expect(invite!.accountReady, isTrue);
      expect(invite.emailDelivered, isFalse);
      expect(invite.emailUnavailable, isTrue);
    });

    test('rejects non-ok payloads', () {
      expect(
        EmployeeLoginInviteResponse.tryParseSuccess({
          'ok': false,
          'reason': 'forbidden',
        }),
        isNull,
      );
    });

    test('maps authorization failure reasons', () {
      expect(
        EmployeeLoginInviteResponse.failureMessage({'reason': 'forbidden'}),
        contains('permission'),
      );
      expect(
        EmployeeLoginInviteResponse.failureMessage({'reason': 'unauthorized'}),
        contains('Sign in'),
      );
      expect(
        EmployeeLoginInviteResponse.failureMessage({
          'reason': 'auth_user_in_use',
        }),
        contains('another person'),
      );
    });

    test('asMap accepts nested JSON string', () {
      final map = EmployeeLoginInviteResponse.asMap(
        '{"ok":true,"account_ready":true,"email_delivered":false}',
      );
      expect(map?['ok'], isTrue);
      expect(map?['account_ready'], isTrue);
    });
  });
}
