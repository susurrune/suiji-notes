import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../core/state/providers.dart';
import '../../ui/widgets/app_empty_state.dart';

/// 文件夹管理：树形展示、新建、重命名、删除。
class FolderManagerScreen extends ConsumerWidget {
  const FolderManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersListProvider);
    final repo = ref.read(folderRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('文件夹管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createFolder(context, repo, folders.value ?? const []),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('新建文件夹'),
      ),
      body: folders.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (list) => list.isEmpty
            ? const AppEmptyState(
                icon: Icons.create_new_folder_outlined,
                title: '还没有文件夹',
                subtitle: '点右下角新建，按工作 / 学习 / 生活归档',
              )
            : _FolderTreeView(
                nodes: _buildTree(list),
                repo: repo,
              ),
      ),
    );
  }

  void _createFolder(
      BuildContext context, FolderRepository repo, List<Folder> all) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _FolderDialog(all: all, onCreate: (name, parentId) async {
        await repo.createFolder(name, parentId: parentId);
        if (ctx.mounted) Navigator.pop(ctx);
      }),
    );
  }
}

class _FolderTreeView extends StatelessWidget {
  const _FolderTreeView({required this.nodes, required this.repo});
  final List<_FolderNode> nodes;
  final FolderRepository repo;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final n in nodes) _renderNode(context, n, 0),
      ],
    );
  }

  Widget _renderNode(BuildContext context, _FolderNode node, int depth) {
    final theme = Theme.of(context);
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(left: 16.0 + depth * 20, right: 8),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.folder_outlined,
                size: 18, color: theme.colorScheme.onPrimaryContainer),
          ),
          title: Text(node.folder.name),
          trailing: Wrap(
            spacing: 0,
            children: [
              IconButton(
                tooltip: '重命名',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => _renameFolder(context, node.folder),
              ),
              IconButton(
                tooltip: '删除',
                icon: Icon(Icons.delete_outline,
                    size: 20, color: theme.colorScheme.error),
                onPressed: () => _deleteFolder(context, node.folder),
              ),
            ],
          ),
        ),
        for (final child in node.children) _renderNode(context, child, depth + 1),
      ],
    );
  }

  void _renameFolder(BuildContext ctx, Folder folder) {
    final ctrl = TextEditingController(text: folder.name);
    showDialog<void>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('重命名文件夹'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              repo.renameFolder(folder.id, ctrl.text.trim());
              Navigator.pop(dctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _deleteFolder(BuildContext ctx, Folder folder) {
    showDialog<void>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('删除文件夹？'),
        content: const Text('其中的笔记将移回「全部」，子文件夹会上移一级。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dctx).colorScheme.error,
            ),
            onPressed: () {
              repo.deleteFolder(folder.id);
              Navigator.pop(dctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _FolderDialog extends StatefulWidget {
  const _FolderDialog({required this.all, required this.onCreate});
  final List<Folder> all;
  final Future<void> Function(String name, String? parentId) onCreate;

  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<_FolderDialog> {
  final _name = TextEditingController();
  String? _parentId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建文件夹'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(hintText: '文件夹名称'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _parentId,
            decoration: const InputDecoration(labelText: '上级文件夹'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('（无，作为一级文件夹）')),
              for (final f in widget.all)
                DropdownMenuItem<String?>(value: f.id, child: Text(f.name)),
            ],
            onChanged: (v) => setState(() => _parentId = v),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            widget.onCreate(name, _parentId);
          },
          child: const Text('创建'),
        ),
      ],
    );
  }
}

/// 文件夹树节点。
class _FolderNode {
  _FolderNode(this.folder);
  final Folder folder;
  final List<_FolderNode> children = [];
}

List<_FolderNode> _buildTree(List<Folder> folders) {
  final byId = <String, _FolderNode>{};
  for (final f in folders) {
    byId[f.id] = _FolderNode(f);
  }
  final roots = <_FolderNode>[];
  for (final f in folders) {
    final node = byId[f.id]!;
    final parent = f.parentId == null ? null : byId[f.parentId];
    if (parent != null) {
      parent.children.add(node);
    } else {
      roots.add(node);
    }
  }
  return roots;
}
