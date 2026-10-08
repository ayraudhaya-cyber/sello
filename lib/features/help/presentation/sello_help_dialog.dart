import 'package:flutter/material.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/features/help/sello_help_content.dart';
import 'package:sello/shared/widgets/widgets.dart';

Future<void> showSelloHelp(
  BuildContext context, {
  String? initialTopicId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => SelloHelpDialog(initialTopicId: initialTopicId),
  );
}

class SelloHelpDialog extends StatefulWidget {
  const SelloHelpDialog({super.key, this.initialTopicId});

  final String? initialTopicId;

  @override
  State<SelloHelpDialog> createState() => _SelloHelpDialogState();
}

class _SelloHelpDialogState extends State<SelloHelpDialog> {
  String? _topicId;

  @override
  void initState() {
    super.initState();
    _topicId = widget.initialTopicId;
  }

  SelloHelpTopic? get _topic {
    final id = _topicId;
    if (id == null) return null;
    for (final topic in SelloHelpContent.topics) {
      if (topic.id == id) return topic;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final topic = _topic;
    return SelloFormDialog(
      title: topic?.title ?? SelloHelpContent.title,
      subtitle: topic == null ? SelloHelpContent.subtitle : null,
      maxWidth: 640,
      fullscreenOnMobile: true,
      body: topic == null
          ? _TopicList(onOpen: (id) => setState(() => _topicId = id))
          : _TopicBody(topic: topic),
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            if (topic != null)
              SelloButton(
                label: 'All topics',
                variant: SelloButtonVariant.outline,
                onPressed: () => setState(() => _topicId = null),
              ),
            const Spacer(),
            SelloButton(
              label: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicList extends StatelessWidget {
  const _TopicList({required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < SelloHelpContent.topics.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: AppColors.outlineSubtle),
          _TopicRow(
            topic: SelloHelpContent.topics[i],
            onTap: () => onOpen(SelloHelpContent.topics[i].id),
          ),
        ],
      ],
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.topic, required this.onTap});

  final SelloHelpTopic topic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                topic.title,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicBody extends StatelessWidget {
  const _TopicBody({required this.topic});

  final SelloHelpTopic topic;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < topic.steps.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${i + 1}.',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  topic.steps[i],
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14.5,
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
        for (final note in topic.notes) ...[
          const SizedBox(height: 16),
          Text(
            note,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13.5,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
