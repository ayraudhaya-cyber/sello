import 'package:flutter/material.dart';
import 'package:sello/services/updates/release_notes_formatter.dart';

/// One friendly highlight line with a matching icon + emoji.
class ReleaseHighlightLine {
  const ReleaseHighlightLine({
    required this.text,
    required this.icon,
    required this.emoji,
  });

  final String text;
  final IconData icon;
  final String emoji;
}

/// Turns release notes into client-friendly highlight rows.
abstract final class ReleaseHighlightsPresenter {
  static const fallbackLines = <String>[
    'We polished a few everyday screens to make them smoother.',
    'Small fixes and improvements based on what you asked for.',
  ];

  static List<ReleaseHighlightLine> lines(String? notes) {
    final bullets = ReleaseNotesFormatter.bullets(notes);
    final source = bullets.isEmpty ? fallbackLines : bullets;
    return [for (final text in source) decorate(text)];
  }

  static ReleaseHighlightLine decorate(String text) {
    final lower = text.toLowerCase();
    if (_matches(lower, const ['password', 'sign in', 'login', 'account'])) {
      return ReleaseHighlightLine(
        text: text,
        icon: Icons.lock_outline_rounded,
        emoji: '🔐',
      );
    }
    if (_matches(lower, const ['cheque', 'check', 'bank'])) {
      return ReleaseHighlightLine(
        text: text,
        icon: Icons.account_balance_outlined,
        emoji: '🏦',
      );
    }
    if (_matches(lower, const ['payment', 'collection', 'paid', 'credit'])) {
      return ReleaseHighlightLine(
        text: text,
        icon: Icons.payments_outlined,
        emoji: '💳',
      );
    }
    if (_matches(lower, const ['discount', 'order', 'invoice', 'receipt'])) {
      return ReleaseHighlightLine(
        text: text,
        icon: Icons.receipt_long_outlined,
        emoji: '🧾',
      );
    }
    if (_matches(lower, const ['customer', 'shop', 'visit'])) {
      return ReleaseHighlightLine(
        text: text,
        icon: Icons.storefront_outlined,
        emoji: '🏪',
      );
    }
    if (_matches(lower, const ['team', 'employee', 'invite', 'email'])) {
      return ReleaseHighlightLine(
        text: text,
        icon: Icons.groups_outlined,
        emoji: '👥',
      );
    }
    if (_matches(lower, const ['product', 'stock', 'inventory'])) {
      return ReleaseHighlightLine(
        text: text,
        icon: Icons.inventory_2_outlined,
        emoji: '📦',
      );
    }
    return ReleaseHighlightLine(
      text: text,
      icon: Icons.auto_awesome_rounded,
      emoji: '✨',
    );
  }

  static bool _matches(String lower, List<String> keys) {
    for (final key in keys) {
      if (lower.contains(key)) return true;
    }
    return false;
  }
}
