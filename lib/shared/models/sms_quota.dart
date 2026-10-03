/// Current Text.lk pack for one tenant.
///
/// [baseline] is the highest live remainder seen since the token was assigned
/// or last replaced. A top-up raises it. This is not lifetime usage.
class SmsQuota {
  const SmsQuota({
    required this.remaining,
    required this.baseline,
    this.expiresOn,
  });

  final int remaining;
  final int baseline;
  final String? expiresOn;

  int get used => baseline >= remaining ? baseline - remaining : 0;

  /// Share of the current pack still available, from 0 to 1.
  double get remainingFraction {
    if (baseline <= 0) return 0;
    return (remaining / baseline).clamp(0.0, 1.0);
  }

  /// Share still available, from 0 to 100.
  double get remainingPercent => remainingFraction * 100;

  String get caption => '$used used / $baseline';

  /// Amber when 20% or less of the current pack remains, unless already critical.
  bool get isLow => !isCritical && remainingFraction <= 0.2;

  /// Red when fewer than 25 SMS remain.
  bool get isCritical => remaining < 25;

  static const rechargeContact = '0765644465';

  /// Live remainder and usage. Low remaining also asks the owner to contact Sello.
  String get tooltip {
    final usage = '$remaining SMS left · $used used of $baseline';
    if (!isCritical) return usage;
    return '$usage\nTo top up this quota, contact the Sello team on $rechargeContact.';
  }

  /// Fields the app is allowed to keep. The API token is never one of them.
  Map<String, Object?> toClientJson() {
    return {
      'remaining': remaining,
      'baseline': baseline,
      'used': used,
      'remaining_percent': remainingPercent,
      'expires_on': expiresOn,
    };
  }

  /// Applies one live Text.lk reading to the stored high-water mark.
  static SmsQuota observe({
    required int? storedBaseline,
    required int remaining,
    String? expiresOn,
  }) {
    final baseline = storedBaseline == null || remaining > storedBaseline
        ? remaining
        : storedBaseline;
    return SmsQuota(
      remaining: remaining,
      baseline: baseline,
      expiresOn: expiresOn,
    );
  }

  /// Null unless the server returned a quota for this company.
  static SmsQuota? tryParse(Map<String, dynamic>? json) {
    if (json == null || json['status'] != 'ok') return null;
    if (json['remaining'] == null || json['baseline'] == null) return null;
    return SmsQuota.fromEdgeJson(json);
  }

  factory SmsQuota.fromEdgeJson(Map<String, dynamic> json) {
    final expiry = json['expires_on'];
    return SmsQuota(
      remaining: _asInt(json['remaining']),
      baseline: _asInt(json['baseline']),
      expiresOn: expiry is String && expiry.trim().isNotEmpty
          ? expiry.trim()
          : null,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }
}
