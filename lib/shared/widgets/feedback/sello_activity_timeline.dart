import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/models/app_notification.dart';

/// Reusable company activity timeline — Customer / Product / Order / etc.
class SelloActivityTimeline extends StatelessWidget {
  const SelloActivityTimeline({
    super.key,
    required this.events,
    this.emptyMessage = 'No activity yet.',
    this.dense = false,
    this.onEventTap,
  });

  final List<CompanyActivityEvent> events;
  final String emptyMessage;
  final bool dense;
  final ValueChanged<CompanyActivityEvent>? onEventTap;

  static final _timeFmt = DateFormat('dd MMM · HH:mm');

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Text(
        emptyMessage,
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: dense ? 12.5 : 13,
          color: AppColors.textSecondary,
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < events.length; i++) ...[
          if (i > 0) SizedBox(height: dense ? 10 : 12),
          _ActivityRow(
            event: events[i],
            timeLabel: _timeFmt.format(events[i].createdAt.toLocal()),
            dense: dense,
            onTap: onEventTap == null ? null : () => onEventTap!(events[i]),
          ),
        ],
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.event,
    required this.timeLabel,
    required this.dense,
    this.onTap,
  });

  final CompanyActivityEvent event;
  final String timeLabel;
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: dense ? 7 : 8,
          height: dense ? 7 : 8,
          margin: EdgeInsets.only(top: dense ? 5 : 6, right: 10),
          decoration: BoxDecoration(
            color: _toneFor(context, event.category),
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.summary,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: dense ? 12.5 : 13.5,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (event.actorName != null && event.actorName!.isNotEmpty)
                    event.actorName!,
                  event.category.label,
                  timeLabel,
                ].join(' · '),
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: dense ? 11 : 11.5,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }

  Color _toneFor(BuildContext context, NotificationCategory category) {
    return switch (category) {
      NotificationCategory.orders => AppColors.ops,
      NotificationCategory.inventory => AppColors.warning,
      NotificationCategory.payments => AppColors.success,
      NotificationCategory.customers => AppColors.info,
      NotificationCategory.suppliers => context.brandAccent,
      NotificationCategory.products => AppColors.inventory,
      NotificationCategory.schedule ||
      NotificationCategory.visits =>
        AppColors.ops,
      NotificationCategory.team => context.brandAccent,
      NotificationCategory.intelligence => AppColors.ai,
      NotificationCategory.reliability => context.brandAccent,
      NotificationCategory.system => AppColors.textTertiary,
    };
  }
}
