import 'package:sello/services/notifications/outbound/messaging_phone.dart';
import 'package:sello/services/notifications/outbound/outbound_channel.dart';

/// Outcome of an automatic SMS attempt. Never thrown into order/collection writes.
enum OutboundSmsStatus {
  sent,
  alreadySent,
  skippedMissingSender,
  skipped,
  failed,
}

class OutboundSmsRequest {
  const OutboundSmsRequest({
    required this.eventId,
    required this.recipientKind,
    required this.recipientKey,
    required this.recipient,
    required this.message,
  });

  final String eventId;
  final OutboundRecipientKind recipientKind;
  final String recipientKey;
  final String recipient;
  final String message;

  /// Body sent to the Edge Function. Never includes API token or Sender ID.
  Map<String, String> toJson() => {
        'event_id': eventId,
        'recipient_kind': recipientKind.dbValue,
        'recipient_key': recipientKey,
        'recipient': recipient,
        'message': message,
      };
}

class OutboundSmsResult {
  const OutboundSmsResult(this.status, {this.reason, this.activated});

  final OutboundSmsStatus status;
  final String? reason;

  /// Set only for Sender ID verification. True after Text.lk accept + save.
  final bool? activated;

  bool get didSend => status == OutboundSmsStatus.sent;

  bool get senderActivated => didSend && activated == true;
}

/// Server-side SMS delivery. Implementations must not embed Text.lk secrets.
abstract class OutboundSmsSender {
  Future<OutboundSmsResult> send(OutboundSmsRequest request);

  /// Configuration test. Uses the same Edge Function / Text.lk path.
  Future<OutboundSmsResult> sendTest({required String recipient});

  /// Onboarding verification. Sends with a candidate Sender ID; the server
  /// persists it only after Text.lk accepts. Token stays server-side.
  Future<OutboundSmsResult> verifySender({
    required String recipient,
    required String senderId,
  });
}

/// Client payload and copy for Settings → Test SMS. Token and Sender ID stay
/// off the client; the Edge Function supplies the message body.
abstract final class OutboundSmsTest {
  static const message =
      'This is a test SMS from Sello. Your SMS configuration is working.';

  static Map<String, String> requestJson(String recipient) => {
        'purpose': 'test',
        'recipient': recipient,
      };

  static String? tenantBlockReason({
    required bool smsEnabled,
    required String? senderId,
  }) {
    if (!smsEnabled) return 'Turn on SMS and save.';
    if (SmsSenderId.normalize(senderId) == null) {
      return 'SMS Sender ID is not configured yet.';
    }
    return null;
  }

  static String feedback(OutboundSmsResult result) {
    if (result.didSend) return 'Test SMS sent.';
    return switch (result.reason) {
      'missing_sender_id' => 'SMS Sender ID is not configured yet.',
      'sms_disabled' => 'Turn on SMS and save.',
      'forbidden' => 'Only Owner or Manager can send a test SMS.',
      'invalid_recipient' => 'Enter a valid phone number.',
      'invalid_request' =>
        'SMS test is not available on the server yet. Redeploy send-outbound-sms.',
      'claim_failed' =>
        'SMS test is not set up on the server yet. Run migration 049, then redeploy send-outbound-sms.',
      'sms_not_configured' => 'SMS is not configured on the server.',
      'provider_error' =>
          'The SMS provider did not accept the message. Check the Sender ID.',
      'network' => 'Could not reach the SMS service.',
      'already_sent' => 'Test SMS sent.',
      final reason? => 'Could not send the test SMS ($reason).',
      _ => 'Could not send the test SMS.',
    };
  }
}

/// Owner onboarding Sender ID verification. Candidate Sender ID is sent to
/// the Edge Function only; the API token never leaves the server.
abstract final class OutboundSmsVerify {
  static const title = 'Set up SMS notifications';
  static const explanation =
      'To send SMS notifications, enter the Sender ID registered for your business. '
      'This is the name your customers will see when they receive SMS notifications from Sello.';
  static const successTitle = 'SMS is ready';
  static const successBody =
      'Your Sender ID has been verified and saved.';
  static const rejectedMessage =
      "We couldn't verify this Sender ID. Please make sure it is registered for your business or contact Sello support.";

  static Map<String, String> requestJson({
    required String recipient,
    required String senderId,
  }) =>
      {
        'purpose': 'verify_sender',
        'recipient': recipient,
        'sender_id': senderId,
      };

  static String? blockReason({
    required String? senderId,
    required String? phone,
  }) {
    if (SmsSenderId.tryParse(senderId) == null) {
      return 'Enter a valid Sender ID (3 to 11 letters or digits).';
    }
    if (MessagingPhone.international(phone) == null) {
      return 'Enter a valid phone number.';
    }
    return null;
  }

  static String feedback(OutboundSmsResult result) {
    if (result.senderActivated) return successBody;
    return switch (result.reason) {
      'sender_id_rejected' || 'provider_error' => rejectedMessage,
      'invalid_sender_id' =>
        'Enter a valid Sender ID (3 to 11 letters or digits).',
      'sender_id_locked' => 'This Sender ID is managed by Sello.',
      'activation_failed' =>
        "We couldn't save this Sender ID. Contact Sello support.",
      'activation_unavailable' =>
        'SMS verification is not available on the server yet. Redeploy send-outbound-sms.',
      'forbidden' => 'Only Owner or Manager can verify a Sender ID.',
      'invalid_recipient' => 'Enter a valid phone number.',
      'claim_failed' =>
        'SMS verification is not set up on the server yet. Run migration 051, then redeploy send-outbound-sms.',
      'sms_not_configured' => 'SMS is not configured on the server.',
      'network' => 'Could not reach the SMS service.',
      final reason? => 'Could not verify this Sender ID ($reason).',
      _ => rejectedMessage,
    };
  }

  /// Client cannot overwrite a locked, different Sender ID.
  static bool canActivateCandidate({
    required String? storedSenderId,
    required bool editable,
    required String candidate,
  }) {
    if (SmsSenderId.tryParse(candidate) == null) return false;
    final stored = SmsSenderId.tryParse(storedSenderId);
    if (stored == null) return true;
    if (stored == candidate) return true;
    return editable;
  }
}

OutboundSmsStatus outboundSmsStatusFromJson(String? raw) {
  return switch (raw) {
    'sent' => OutboundSmsStatus.sent,
    'already_sent' => OutboundSmsStatus.alreadySent,
    'skipped' => OutboundSmsStatus.skipped,
    'failed' => OutboundSmsStatus.failed,
    _ => OutboundSmsStatus.failed,
  };
}
