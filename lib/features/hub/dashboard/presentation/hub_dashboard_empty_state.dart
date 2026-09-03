import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';

/// Compact / centered empty treatment for Hub Dashboard cards only.
///
/// Tall cards center icon + title + optional description.
/// Short cards use a horizontal icon + title row.
class HubDashboardEmptyState extends StatelessWidget {
  const HubDashboardEmptyState.tall({
    super.key,
    required this.icon,
    required this.title,
    required this.tone,
    required this.soft,
    this.message,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  }) : compact = false;

  const HubDashboardEmptyState.compact({
    super.key,
    required this.icon,
    required this.title,
    required this.tone,
    required this.soft,
    this.padding = const EdgeInsets.symmetric(vertical: 10),
  })  : compact = true,
        message = null;

  final IconData icon;
  final String title;
  final String? message;
  final Color tone;
  final Color soft;
  final bool compact;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Padding(
        padding: padding,
        child: Row(
          children: [
            _IconWell(icon: icon, tone: tone, soft: soft, size: 32, iconSize: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconWell(icon: icon, tone: tone, soft: soft, size: 40, iconSize: 20),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.01 * 14,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
              ),
              if (message != null && message!.trim().isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconWell extends StatelessWidget {
  const _IconWell({
    required this.icon,
    required this.tone,
    required this.soft,
    required this.size,
    required this.iconSize,
  });

  final IconData icon;
  final Color tone;
  final Color soft;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        border: Border.all(color: tone.withValues(alpha: 0.12)),
      ),
      child: Icon(icon, size: iconSize, color: tone),
    );
  }
}
