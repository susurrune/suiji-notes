import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/core.dart';
import '../../core/state/providers.dart';
import '../../ui/widgets/app_empty_state.dart';
import '../editor/editor_screen.dart';

/// 待办视图：聚合所有清单块，支持优先级/截止时间、右滑完成、左滑操作。
class TodosTab extends ConsumerStatefulWidget {
  const TodosTab({super.key});

  @override
  ConsumerState<TodosTab> createState() => _TodosTabState();
}

class _TodosTabState extends ConsumerState<TodosTab> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// 顶部输入「添加待办」→ 新建一篇含单个清单块的笔记。
  Future<void> _addTodo(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    _input.clear();
    final notes = ref.read(noteRepositoryProvider);
    await notes.createNote(const Uuid().v4(), blocks: [
      BlockDraft(
        BlockType.checklist,
        ChecklistBlockData(items: [
          ChecklistItem(id: const Uuid().v4(), text: t),
        ]),
      ),
    ]);
  }

  Future<void> _markDone(TodoEntry e, bool done) async {
    await ref.read(noteRepositoryProvider).updateChecklistItem(
          e.noteId,
          e.blockId,
          e.item.copyWith(done: done),
        );
  }

  /// 左滑操作：优先级 + 截止时间。
  Future<void> _showActions(TodoEntry e) async {
    var priority = e.item.priority;
    var dueAt = e.item.dueAt;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined, size: 20),
                    const SizedBox(width: 8),
                    const Text('优先级'),
                    const Spacer(),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: 0, label: Text('普通')),
                        ButtonSegment(value: 1, label: Text('低')),
                        ButtonSegment(value: 2, label: Text('中')),
                        ButtonSegment(value: 3, label: Text('高')),
                      ],
                      selected: {priority},
                      onSelectionChanged: (s) =>
                          setSheetState(() => priority = s.first),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(dueAt == null ? '设置截止时间' : '截止：${_fmt(dueAt!)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: dueAt ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setSheetState(() => dueAt = picked);
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await ref.read(noteRepositoryProvider).updateChecklistItem(
                            e.noteId,
                            e.blockId,
                            e.item.copyWith(priority: priority, dueAt: dueAt),
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('保存'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todos = ref.watch(todosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('待办')),
      body: Column(
        children: [
          // 快捷新建
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _input,
              decoration: InputDecoration(
                hintText: '添加待办…',
                prefixIcon: const Icon(Icons.add_task),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _addTodo(_input.text),
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: _addTodo,
            ),
          ),
          Expanded(
            child: todos.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (list) {
                if (list.isEmpty) {
                  return const AppEmptyState(
                    icon: Icons.check_circle_outline,
                    title: '暂无待办',
                    subtitle: '在上方输入，或在笔记里创建清单',
                  );
                }
                final sorted = _sorted(list);
                final firstDoneIndex =
                    sorted.indexWhere((t) => t.item.done);
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  itemCount: sorted.length + (firstDoneIndex >= 0 ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (firstDoneIndex >= 0 && i == firstDoneIndex) {
                      return const _DoneHeader();
                    }
                    // 无已完成项时 firstDoneIndex = -1，直接按原下标取；
                    // 有已完成项时，「已完成」标题插入在 firstDoneIndex 处。
                    final item = firstDoneIndex < 0
                        ? sorted[i]
                        : sorted[i < firstDoneIndex ? i : i - 1];
                    return RepaintBoundary(child: _buildRow(item));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(TodoEntry e) {
    final theme = Theme.of(context);
    final item = e.item;
    final done = item.done;
    final key = ValueKey('${e.noteId}:${e.blockId}:${item.id}');
    final row = ListTile(
      leading: Checkbox(
        value: done,
        onChanged: (v) => _markDone(e, v ?? false),
        shape: const CircleBorder(),
      ),
      title: Text(
        item.text,
        style: theme.textTheme.bodyLarge?.copyWith(
          decoration: done ? TextDecoration.lineThrough : null,
          color: done ? theme.colorScheme.outline : null,
        ),
      ),
      subtitle: done
          ? null
          : Row(
              children: [
                if (item.priority > 0) ...[
                  _PriorityBadge(level: item.priority),
                  const SizedBox(width: 6),
                ],
                if (item.dueAt != null) ...[
                  Icon(Icons.event, size: 12, color: _dueColor(theme, item)),
                  const SizedBox(width: 2),
                  Text(_fmt(item.dueAt!),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: _dueColor(theme, item))),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    e.noteTitle.isEmpty ? '来自笔记' : e.noteTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              ],
            ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EditorScreen(noteId: e.noteId)),
      ),
    );

    if (done) return row;

    return Dismissible(
      key: ValueKey('d-sr-$key'),
      direction: DismissDirection.startToEnd,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: Colors.green.shade600,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(
          children: [
            Icon(Icons.check, color: Colors.white),
            SizedBox(width: 8),
            Text('完成',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        await _markDone(e, true);
        return true;
      },
      child: Dismissible(
        key: ValueKey('d-sl-$key'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune, color: Colors.black54),
              const SizedBox(width: 6),
              Text('优先级 / 截止',
                  style: TextStyle(
                      color: theme.colorScheme.onSecondaryContainer)),
            ],
          ),
        ),
        confirmDismiss: (_) async {
          await _showActions(e);
          return false;
        },
        child: row,
      ),
    );
  }

  List<TodoEntry> _sorted(List<TodoEntry> todos) {
    final pending = todos.where((t) => !t.item.done).toList()
      ..sort((a, b) {
        if (a.item.priority != b.item.priority) {
          return b.item.priority.compareTo(a.item.priority);
        }
        final ad = a.item.dueAt;
        final bd = b.item.dueAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
    final done = todos.where((t) => t.item.done).toList();
    return [...pending, ...done];
  }

  Color _dueColor(ThemeData theme, ChecklistItem item) {
    if (item.dueAt == null) return theme.colorScheme.outline;
    return item.dueAt!.isBefore(DateTime.now())
        ? theme.colorScheme.error
        : theme.colorScheme.outline;
  }

  String _fmt(DateTime t) =>
      '${t.month}月${t.day}日';
}

/// 「已完成」分组标题。
class _DoneHeader extends StatelessWidget {
  const _DoneHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
      child: Text(
        '已完成',
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.outline,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      3 => Colors.red,
      2 => Colors.orange,
      _ => Colors.amber,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('P$level',
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
