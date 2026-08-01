import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/providers.dart';
import '../../core/sync/sync_service.dart';

/// 云同步设置卡片：项目配置 / 账号登录 / 立即同步 / 冲突处理。
class SyncSection extends ConsumerStatefulWidget {
  const SyncSection({super.key});

  @override
  ConsumerState<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<SyncSection> {
  final _url = TextEditingController();
  final _anonKey = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider).valueOrNull;
    _url.text = profile?.syncUrl ?? '';
    _anonKey.text = profile?.syncAnonKey ?? '';
  }

  @override
  void dispose() {
    _url.dispose();
    _anonKey.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    final url = _url.text.trim();
    final key = _anonKey.text.trim();
    if (url.isEmpty || key.isEmpty) {
      setState(() => _status = '请填写项目 URL 和 anon key');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(syncServiceProvider).configure(url, key);
      await ref.read(profileRepositoryProvider).updateSyncConfig(url, key);
      ref.invalidate(profileProvider);
      setState(() => _status = '配置已保存');
    } catch (e) {
      setState(() => _status = '配置失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signUp() async {
    await _auth((s) => s.signUp(_email.text.trim(), _password.text));
  }

  Future<void> _signIn() async {
    await _auth((s) => s.signIn(_email.text.trim(), _password.text));
  }

  Future<void> _auth(Future<void> Function(SyncService) action) async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _status = '请填写邮箱和密码');
      return;
    }
    setState(() => _busy = true);
    try {
      await action(ref.read(syncServiceProvider));
      setState(() => _status = '已登录：${_email.text.trim()}');
      _password.clear();
    } catch (e) {
      setState(() => _status = '登录失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _busy = true;
      _status = '正在同步…';
    });
    try {
      final result = await ref.read(syncServiceProvider).sync();
      if (!mounted) return;
      setState(() {
        _status = result.hasConflicts
            ? '发现 ${result.conflicts.length} 处冲突，请处理'
            : '同步完成：推送 ${result.pushed}，拉取 ${result.pulled}';
      });
      if (result.hasConflicts) {
        await _showConflicts(result.conflicts);
      }
    } catch (e) {
      if (mounted) setState(() => _status = '同步失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showConflicts(List<SyncConflict> conflicts) async {
    final keepLocal = <String, bool>{};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => AlertDialog(
          title: Text('${conflicts.length} 篇笔记存在冲突'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in conflicts)
                  CheckboxListTile(
                    value: keepLocal[c.noteId] ?? true,
                    title: Text(c.noteId.length > 20
                        ? '${c.noteId.substring(0, 20)}…'
                        : c.noteId),
                    subtitle: Text(
                        '本地 ${_fmt(c.localUpdatedAt)} · 云端 ${_fmt(c.remoteUpdatedAt)}'),
                    onChanged: (v) =>
                        setSheet(() => keepLocal[c.noteId] = v ?? true),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('勾选 = 保留本地版本（覆盖云端）；取消勾选 = 采用云端版本',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await ref
                    .read(syncServiceProvider)
                    .resolveConflicts(keepLocal);
                if (mounted) setState(() => _status = '冲突已处理');
              },
              child: const Text('应用选择'),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime t) =>
      '${t.month}月${t.day}日 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sync = ref.read(syncServiceProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.cloud_sync_outlined,
                      size: 20, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('云同步',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text('Supabase 免费后端，多设备同步',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: '项目 URL',
                hintText: 'https://xxxx.supabase.co',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _anonKey,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'anon key',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _busy ? null : _saveConfig,
              child: const Text('保存配置'),
            ),
            const Divider(height: 28),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '邮箱',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码', isDense: true),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _signUp,
                    child: const Text('注册'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _signIn,
                    child: const Text('登录'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _syncNow,
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('立即同步'),
            ),
            const SizedBox(height: 6),
            Text(
              _status.isEmpty
                  ? (sync.isSignedIn ? '已登录' : '尚未登录')
                  : _status,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 4),
            Text(
              '首次使用：在 Supabase SQL Editor 执行 docs/supabase_schema.sql',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
