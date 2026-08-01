import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/core.dart';
import '../../core/state/providers.dart';
import '../../ui/widgets/app_empty_state.dart';
import '../editor/editor_screen.dart';

/// 「随笔」栏：日记式速记，记录一天的小感想、想写的句子。
/// 条目存为「随笔」文件夹下的笔记，按日期分组展示。
class SuibiTab extends ConsumerStatefulWidget {
  const SuibiTab({super.key});

  @override
  ConsumerState<SuibiTab> createState() => _SuibiTabState();
}

class _SuibiTabState extends ConsumerState<SuibiTab> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    _input.clear();
    final folderId = await ref.read(suibiFolderProvider.future);
    await ref.read(noteRepositoryProvider).createNote(
          const Uuid().v4(),
          folderId: folderId,
          blocks: [BlockDraft(BlockType.text, TextBlockData(t))],
        );
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(suibiNotesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('随笔')),
      body: Column(
        children: [
          _JournalInput(controller: _input, onSave: _save),
          Expanded(
            child: notes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (items) => items.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.mode_edit_outline,
                      title: '今天，还没有写下什么',
                      subtitle: '记下此刻的心情或一句想说的话',
                    )
                  : _SuibiTimeline(items: items),
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶部日记输入卡（暖色质感）。
class _JournalInput extends StatelessWidget {
  const _JournalInput({required this.controller, required this.onSave});
  final TextEditingController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  theme.colorScheme.surfaceContainerHigh,
                  theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
                ]
              : const [
                  Color(0xFFFFF6E9),
                  Color(0xFFFDF1E2),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_stories,
                  size: 18,
                  color: theme.colorScheme.primary.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Text(
                '此刻的想法',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            decoration: const InputDecoration(
              hintText: '今天，想写点什么…',
              border: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('记下'),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 按日期分组的随笔时间线。
class _SuibiTimeline extends StatelessWidget {
  const _SuibiTimeline({required this.items});
  final List<Note> items;

  @override
  Widget build(BuildContext context) {
    // 按「创建日期」分组（创建时间决定归属日），组内创建时间倒序
    final sorted = [...items]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final groups = <String, List<Note>>{};
    for (final n in sorted) {
      final day = '${n.createdAt.year}-${n.createdAt.month.toString().padLeft(2, '0')}-${n.createdAt.day.toString().padLeft(2, '0')}';
      groups.putIfAbsent(day, () => []).add(n);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: days.length,
      itemBuilder: (_, i) {
        final day = days[i];
        final list = groups[day]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DayHeader(day: day),
            for (final n in list)
              _SuibiEntry(note: n),
          ],
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});
  final String day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dt = DateTime.tryParse(day);
    final label = dt == null ? day : formatFullDateWithWeekday(dt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: theme.colorScheme.primary.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

class _SuibiEntry extends StatelessWidget {
  const _SuibiEntry({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hm = formatTime(note.createdAt);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EditorScreen(noteId: note.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  note.preview.isEmpty ? note.title : note.preview,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.55,
                    fontFamily: 'serif',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                hm,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

