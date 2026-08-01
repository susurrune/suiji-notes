import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../core/state/providers.dart';
import '../../ui/widgets/app_empty_state.dart';

/// 标签管理：新建（字母/数字/图形三类）、重命名、删除。
class TagManagerScreen extends ConsumerWidget {
  const TagManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsListProvider);
    final repo = ref.read(tagRepositoryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('标签管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createTag(context, repo),
        icon: const Icon(Icons.add),
        label: const Text('新建标签'),
      ),
      body: tags.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (list) {
          if (list.isEmpty) {
            return const AppEmptyState(
              icon: Icons.label_outline,
              title: '还没有标签',
              subtitle: '点右下角新建，用字母 / 数字 / 图形打标',
            );
          }
          final groups = <TagKind, List<Tag>>{
            for (final k in TagKind.values) k: list.where((t) => tagKindOf(t.kind) == k).toList(),
          };
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final k in TagKind.values) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Text(
                    switch (k) {
                      TagKind.alpha => '字母标签',
                      TagKind.numeric => '数字标签',
                      TagKind.shape => '图形标签',
                    },
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
                if (groups[k]!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                    child: Text('（空）',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ),
                for (final t in groups[k]!)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_tagIcon(t),
                          size: 18,
                          color: theme.colorScheme.onSecondaryContainer),
                    ),
                    title: Text(t.name),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: '重命名',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _renameTag(context, repo, t),
                        ),
                        IconButton(
                          tooltip: '删除',
                          icon: Icon(Icons.delete_outline,
                              size: 20, color: theme.colorScheme.error),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('删除标签？'),
                                content: Text('将移除「${t.name}」与所有笔记的关联。'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('取消')),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('删除'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) await repo.deleteTag(t.id);
                          },
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 16),
              ],
            ],
          );
        },
      ),
    );
  }

  void _createTag(BuildContext context, TagRepository repo) {
    final name = TextEditingController();
    var kind = TagKind.alpha;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('新建标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(hintText: '标签名称'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<TagKind>(
                segments: const [
                  ButtonSegment(value: TagKind.alpha, label: Text('字母')),
                  ButtonSegment(value: TagKind.numeric, label: Text('数字')),
                  ButtonSegment(value: TagKind.shape, label: Text('图形')),
                ],
                selected: {kind},
                onSelectionChanged: (s) => setState(() => kind = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final n = name.text.trim();
                if (n.isEmpty) return;
                repo.createTag(n, kind);
                Navigator.pop(ctx);
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  void _renameTag(BuildContext context, TagRepository repo, Tag tag) {
    final name = TextEditingController(text: tag.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名标签'),
        content: TextField(controller: name, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final n = name.text.trim();
              if (n.isEmpty) return;
              repo.renameTag(tag.id, n);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  IconData _tagIcon(Tag t) {
    return switch (t.kind) {
      'numeric' => Icons.tag,
      'shape' => Icons.square_outlined,
      _ => Icons.abc,
    };
  }
}
