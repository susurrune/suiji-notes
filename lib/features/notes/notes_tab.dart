import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../core/state/providers.dart';
import '../../ui/widgets/app_empty_state.dart';
import '../../ui/widgets/note_card.dart';
import '../../ui/widgets/profile_avatar.dart';
import '../editor/editor_screen.dart';
import '../folders/folder_manager_screen.dart';
import '../search/search_screen.dart';

/// 笔记主列表（文件夹筛选 + 网格/列表切换 + 搜索入口 + 一键速记）。
class NotesTab extends ConsumerWidget {
  const NotesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grid = ref.watch(viewModeProvider);
    final notes = ref.watch(notesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('随记'),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            tooltip: grid ? '切换到列表' : '切换到网格',
            icon: Icon(grid ? Icons.view_list : Icons.grid_view),
            onPressed: () =>
                ref.read(viewModeProvider.notifier).state = !grid,
          ),
        ],
      ),
      body: Column(
        children: [
          const _HomeHeader(),
          const _FolderChips(),
          Expanded(
            child: notes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (items) => items.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.edit_note,
                      title: '还没有笔记',
                      subtitle: '点击右下角「新建」，随手记录灵感',
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: grid
                          ? GridView.builder(
                              key: const ValueKey('grid'),
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.86,
                              ),
                              itemCount: items.length,
                              itemBuilder: (_, i) => RepaintBoundary(
                                child: NoteCard(
                                  note: items[i],
                                  compact: true,
                                  onTap: () =>
                                      _openEditor(context, ref, items[i].id),
                                ),
                              ),
                            )
                          : ListView.builder(
                              key: const ValueKey('list'),
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                              itemCount: items.length,
                              itemBuilder: (_, i) => RepaintBoundary(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: NoteCard(
                                    note: items[i],
                                    onTap: () =>
                                        _openEditor(context, ref, items[i].id),
                                  ),
                                ),
                              ),
                            ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('新建'),
      ),
    );
  }

  void _openEditor(BuildContext context, WidgetRef ref, String? noteId) {
    final folderId = ref.read(selectedFolderProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          noteId: noteId,
          initialFolderId: noteId == null ? folderId : null,
        ),
      ),
    );
  }
}

/// 首页日期题头（日记式开篇 + 头像问候）。
class _HomeHeader extends ConsumerWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final profile = ref.watch(profileProvider).valueOrNull;
    final name = profile?.name ?? '';
    final greeting = name.isEmpty
        ? '今天想记录点什么？'
        : '你好，$name，今天想记录点什么？';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${now.month}月${now.day}日 · 星期${weekdays[now.weekday - 1]}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontFamily: 'serif',
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 2,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1),
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary.withValues(alpha: 0.7),
                            theme.colorScheme.primary.withValues(alpha: 0.15),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        greeting,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if ((profile?.avatarPath ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: ProfileAvatar(path: profile?.avatarPath, size: 40),
            ),
        ],
      ),
    );
  }
}

/// 文件夹筛选条：全部 / 各根文件夹 / 管理。
class _FolderChips extends ConsumerWidget {
  const _FolderChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersListProvider);
    final selected = ref.watch(selectedFolderProvider);
    final roots = folders.value?.where((f) => f.parentId == null).toList() ??
        const <Folder>[];

    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                avatar: const Icon(Icons.inbox_outlined, size: 16),
                label: const Text('全部'),
                selected: selected == null,
                onSelected: (_) =>
                    ref.read(selectedFolderProvider.notifier).state = null,
              ),
            ),
            for (final f in roots)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  avatar: const Icon(Icons.folder_outlined, size: 16),
                  label: Text(f.name),
                  selected: selected == f.id,
                  onSelected: (_) => ref
                      .read(selectedFolderProvider.notifier)
                      .state = selected == f.id ? null : f.id,
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: IconButton(
                tooltip: '管理文件夹',
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const FolderManagerScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

