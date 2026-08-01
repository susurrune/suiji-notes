import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../theme/note_colors.dart';

/// 重要度 0-3 → 标志色。
Color _importanceColor(ThemeData theme, int level) {
  return switch (level) {
    3 => Colors.red,
    2 => Colors.orange,
    _ => Colors.amber.shade700,
  };
}

/// 笔记卡片（网格 / 列表共用）。
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    this.compact = false,
  });

  final Note note;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = noteColorOf(note.color);
    final isEncrypted = note.encrypted;
    final hasTitle = !isEncrypted && note.title.trim().isNotEmpty;
    final hasPreview = !isEncrypted && note.preview.trim().isNotEmpty;

    return Card(
      color: bg ?? theme.cardTheme.color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isEncrypted)
                Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 16, color: theme.colorScheme.tertiary),
                    const SizedBox(width: 6),
                    Text(
                      '已加密笔记',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                )
              else if (hasTitle || note.pinned)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        hasTitle ? note.title : '无标题',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontStyle: hasTitle ? null : FontStyle.italic,
                          color: hasTitle
                              ? null
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (note.important > 0) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.flag,
                        size: 14,
                        color: _importanceColor(theme, note.important),
                      ),
                    ],
                    if (note.pinned) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.push_pin,
                          size: 16, color: theme.colorScheme.onSurfaceVariant),
                    ],
                  ],
                ),
              if (hasPreview) ...[
                const SizedBox(height: 4),
                Text(
                  note.preview,
                  maxLines: compact ? 2 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (!hasTitle && !hasPreview)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '空笔记',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              // 创建日期（年月日，便于确定笔记创建时间）
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 12, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    formatFullDate(note.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
