import 'package:flutter_test/flutter_test.dart';
import 'package:sello/services/auth/auth_email_personalization.dart';

void main() {
  group('AuthEmailPersonalization', () {
    test('emailLocal takes the part before @', () {
      expect(
        AuthEmailPersonalization.emailLocal('velvetkutty@gmail.com'),
        'velvetkutty',
      );
      expect(
        AuthEmailPersonalization.emailLocal('  Ayra.Udhaya@Example.COM '),
        'ayra.udhaya',
      );
    });

    test('fields prefer full name and include company role badge data', () {
      expect(
        AuthEmailPersonalization.fields(
          email: 'velvetkutty@gmail.com',
          fullName: 'Velvet Kutty',
          companyName: 'Test Business',
          roleLabel: AuthEmailPersonalization.roleSalesRep,
        ),
        {
          'full_name': 'Velvet Kutty',
          'greeting_name': 'Velvet Kutty',
          'email_local': 'velvetkutty',
          'company_name': 'Test Business',
          'role_label': 'Sales Rep',
        },
      );
    });

    test('fields omit empty name but still keep email_local for Hi velvetkutty', () {
      expect(
        AuthEmailPersonalization.fields(
          email: 'velvetkutty@gmail.com',
          companyName: 'Test Business',
          roleLabel: AuthEmailPersonalization.roleOwner,
        ),
        {
          'email_local': 'velvetkutty',
          'company_name': 'Test Business',
          'role_label': 'Owner',
        },
      );
    });

    test('isTeamInviteMetadata only accepts the invite flag', () {
      expect(
        AuthEmailPersonalization.isTeamInviteMetadata({
          AuthEmailPersonalization.teamInviteKey: true,
        }),
        isTrue,
      );
      expect(
        AuthEmailPersonalization.isTeamInviteMetadata({
          AuthEmailPersonalization.teamInviteKey: false,
        }),
        isFalse,
      );
      expect(
        AuthEmailPersonalization.isTeamInviteMetadata({
          'role_label': 'Sales Rep',
        }),
        isFalse,
      );
      expect(AuthEmailPersonalization.isTeamInviteMetadata(null), isFalse);
    });
  });
}
