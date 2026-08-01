import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/data/media/media_storage.dart';
import '../../core/export/note_exporter.dart';
import '../../core/state/providers.dart';
import '../../ui/widgets/profile_avatar.dart';
import '../folders/folder_manager_screen.dart';
import '../sync/sync_section.dart';
import '../tags/tag_manager_screen.dart';
import '../trash/trash_screen.dart';

/// 设置：分组卡片 + 着色图标，外观更精致。
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const _ProfileCard(),
          const _SectionTitle('云同步'),
          const SyncSection(),
          const _SectionTitle('外观'),
          Card(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Row(
                    children: [
                      const _TintedIcon(icon: Icons.brightness_6_outlined),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('主题模式',
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            Text('浅色 / 深色 / 跟随系统',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 三段式选择
                      SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, label: Text('跟随')),
                          ButtonSegment(value: ThemeMode.light, label: Text('浅')),
                          ButtonSegment(value: ThemeMode.dark, label: Text('深')),
                        ],
                        selected: {themeMode},
                        onSelectionChanged: (s) => ref
                            .read(themeModeProvider.notifier)
                            .state = s.first,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _SectionTitle('数据'),
          Card(
            child: Column(
              children: [
                _TintedTile(
                  icon: Icons.label_outline,
                  title: '标签管理',
                  subtitle: '字母 / 数字 / 图形三类标签',
                  tint: theme.colorScheme.tertiaryContainer,
                  iconColor: theme.colorScheme.onTertiaryContainer,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const TagManagerScreen()),
                  ),
                ),
                _divider(theme),
                _TintedTile(
                  icon: Icons.create_new_folder_outlined,
                  title: '文件夹管理',
                  subtitle: '树形归档分类',
                  tint: theme.colorScheme.primaryContainer,
                  iconColor: theme.colorScheme.onPrimaryContainer,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const FolderManagerScreen()),
                  ),
                ),
                _divider(theme),
                _TintedTile(
                  icon: Icons.delete_outline,
                  title: '回收站',
                  subtitle: '恢复或彻底删除已删除的笔记',
                  tint: theme.colorScheme.errorContainer,
                  iconColor: theme.colorScheme.onErrorContainer,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TrashScreen()),
                  ),
                ),
                _divider(theme),
                _TintedTile(
                  icon: Icons.ios_share,
                  title: '数据导出',
                  subtitle: '导出为 Markdown / TXT',
                  tint: theme.colorScheme.secondaryContainer,
                  iconColor: theme.colorScheme.onSecondaryContainer,
                  onTap: () => _showExportSheet(context, ref),
                ),
              ],
            ),
          ),
          const _SectionTitle('关于'),
          Card(
            child: const AboutListTile(
              icon: Icon(Icons.auto_stories_outlined),
              applicationName: '随记',
              applicationVersion: 'MVP 0.2',
              aboutBoxChildren: [Text('轻量快速记录 + 结构化管理')],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(ThemeData theme) => Divider(
        height: 1,
        indent: 66,
        color: theme.dividerColor.withValues(alpha: 0.5),
      );

  void _showExportSheet(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('导出为 Markdown'),
              subtitle: const Text('含格式，适合迁移到其他笔记软件'),
              onTap: () async {
                final path = await NoteExporter(db).exportMarkdown();
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                messenger.showSnackBar(
                  SnackBar(content: Text('已导出：$path')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('导出为 TXT'),
              subtitle: const Text('纯文本，通用性最强'),
              onTap: () async {
                final path = await NoteExporter(db).exportText();
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                messenger.showSnackBar(
                  SnackBar(content: Text('已导出：$path')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('导出为 PDF'),
              subtitle: const Text('含格式与图片，适合打印分享'),
              onTap: () async {
                final path = await NoteExporter(db).exportPdf();
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                messenger.showSnackBar(
                  SnackBar(content: Text('已导出：$path')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 个人资料卡：头像（相册上传，本地持久化）+ 昵称。
class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  Future<void> _pickAvatar(BuildContext context, WidgetRef ref) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;
    final path = await MediaStorage.persist(File(picked.path));
    await ref.read(profileRepositoryProvider).updateAvatar(path);
    ref.invalidate(profileProvider);
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, String current) async {
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置昵称'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '你的昵称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(profileRepositoryProvider).updateName(name);
      ref.invalidate(profileProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(profileProvider).valueOrNull;
    final name = profile?.name ?? '';
    final hasProfile = name.isNotEmpty || (profile?.avatarPath ?? '').isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ProfileAvatar(
              path: profile?.avatarPath,
              size: 64,
              onTap: () => _pickAvatar(context, ref),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasProfile && name.isNotEmpty ? name : '未设置昵称',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'serif',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasProfile
                        ? '点击头像更换 · 点击昵称编辑'
                        : '点击设置头像和昵称',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
            if (hasProfile && name.isEmpty)
              TextButton(
                onPressed: () => _editName(context, ref, ''),
                child: const Text('设置昵称'),
              )
            else
              Icon(Icons.edit_outlined,
                  size: 20, color: theme.colorScheme.outlineVariant),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// 着色圆角方块图标（设置页统一视觉元素）。
class _TintedIcon extends StatelessWidget {
  const _TintedIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, size: 20, color: theme.colorScheme.onPrimaryContainer),
    );
  }
}

class _TintedTile extends StatelessWidget {
  const _TintedTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: theme.colorScheme.outlineVariant,
      ),
    );
  }
}
