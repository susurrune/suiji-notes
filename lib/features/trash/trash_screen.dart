import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../core/state/providers.dart';
import '../../ui/widgets/app_empty_state.dart';

/// 回收站：恢复 / 彻底删除。
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trash = ref.watch(trashListProvider);
    final notes = ref.read(noteRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('回收站')),
      body: trash.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (items) => items.isEmpty
            ? const AppEmptyState(
                icon: Icons.delete_sweep_outlined,
                title: '回收站是空的',
                subtitle: '删除的笔记会在这里保留 30 天',
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final n = items[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: Text(
                        n.title.isEmpty ? '无标题' : n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '删除于 ${_fmt(n.trashTime ?? n.updatedAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: '恢复',
                            icon: const Icon(Icons.settings_backup_restore),
                            onPressed: () => notes.restoreNote(n.id),
                          ),
                          IconButton(
                            tooltip: '彻底删除',
                            icon: Icon(
                              Icons.delete_forever,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            onPressed: () => _confirmPurge(context, notes, n),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  void _confirmPurge(BuildContext context, NoteRepository notes, Note n) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除？'),
        content: const Text('此操作不可恢复，将从本机移除该笔记。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              notes.deletePermanently(n.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
