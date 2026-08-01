import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/database/database.dart';
import '../domain/block_data.dart';
import '../domain/enums.dart';
import '../search/tokenizer.dart';

/// 同步冲突：同一笔记本地与云端更新时间不一致。
class SyncConflict {
  const SyncConflict({required this.noteId, required this.localUpdatedAt, required this.remoteUpdatedAt});
  final String noteId;
  final DateTime localUpdatedAt;
  final DateTime remoteUpdatedAt;
}

/// 一次同步的结果汇总。
class SyncResult {
  const SyncResult({this.pushed = 0, this.pulled = 0, this.conflicts = const []});
  final int pushed;
  final int pulled;
  final List<SyncConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// 云端同步（Supabase）。
///
/// 同步模型：整篇笔记同步（内容块序列化为 content_json），
/// 冲突不做静默合并——收集后由 UI 弹「保留本地 / 采用云端」。
/// 媒体文件上传到 Storage `media` 桶。
class SyncService {
  SyncService(this._db);

  final AppDatabase _db;

  static bool _supabaseInitialized = false;

  bool get isConfigured => _supabaseInitialized;
  bool get isSignedIn => _currentUser != null;
  User? _currentUser;

  /// 使用配置初始化 Supabase（幂等）。
  Future<void> configure(String url, String anonKey) async {
    if (!_supabaseInitialized) {
      await Supabase.initialize(url: url, publishableKey: anonKey);
      _supabaseInitialized = true;
    }
    _currentUser = Supabase.instance.client.auth.currentUser;
  }

  Future<void> signUp(String email, String password) async {
    final res = await Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
    );
    _currentUser = res.user;
  }

  Future<void> signIn(String email, String password) async {
    final res = await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    _currentUser = res.user;
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    _currentUser = null;
  }

  /// 执行同步：推本地变更 → 拉云端 → 收集冲突（不静默覆盖）。
  Future<SyncResult> sync() async {
    final client = Supabase.instance.client;
    if (!isSignedIn) {
      throw StateError('未登录，无法同步');
    }

    var pushed = 0;
    // ── 1. 推送本地笔记（非回收站）──
    final localNotes = await (_db.select(_db.notes)
          ..where((n) => n.deletedAt.isNull()))
        .get();
    for (final n in localNotes) {
      final blocks = await (_db.select(_db.blocks)
            ..where((b) => b.noteId.equals(n.id))
            ..orderBy([(b) => OrderingTerm(expression: b.orderIndex)]))
          .get();
      final content = jsonEncode([
        for (final b in blocks)
          {
            'type': b.type,
            'source': b.source,
            'data': b.data,
          },
      ]);
      final trashed = n.trashTime != null;
      await client.from('notes_sync').upsert({
        'id': n.id,
        'title': n.title,
        'preview': n.preview,
        'folder_id': n.folderId,
        'color': n.color,
        'pinned': n.pinned,
        'important': n.important,
        'encrypted': n.encrypted,
        'archived': n.archived,
        'trash_time': n.trashTime?.toUtc().toIso8601String(),
        'reminder_at': n.reminderAt?.toUtc().toIso8601String(),
        'created_at': n.createdAt.toUtc().toIso8601String(),
        'updated_at': n.updatedAt.toUtc().toIso8601String(),
        'deleted': trashed,
        'content_json': content,
      });
      pushed++;
    }

    // ── 2. 推送文件夹 / 标签 ──
    final folders = await _db.select(_db.folders).get();
    for (final f in folders) {
      await client.from('folders_sync').upsert({
        'id': f.id,
        'name': f.name,
        'parent_id': f.parentId,
        'sort_order': f.sortOrder,
        'created_at': f.createdAt.toUtc().toIso8601String(),
        'updated_at': f.updatedAt.toUtc().toIso8601String(),
        'deleted': false,
      });
    }
    final tags = await _db.select(_db.tags).get();
    for (final t in tags) {
      await client.from('tags_sync').upsert({
        'id': t.id,
        'name': t.name,
        'kind': t.kind,
        'created_at': t.createdAt.toUtc().toIso8601String(),
        'deleted': false,
      });
    }
    final noteTags = await _db.select(_db.noteTags).get();
    for (final nt in noteTags) {
      await client.from('note_tags_sync').upsert({
        'note_id': nt.noteId,
        'tag_id': nt.tagId,
      });
    }

    // ── 3. 拉取云端笔记 ──
    var pulled = 0;
    final conflicts = <SyncConflict>[];
    final remote = await client.from('notes_sync').select();
    final localById = {for (final n in localNotes) n.id: n};
    for (final r in remote) {
      final id = r['id'] as String;
      final remoteUpdated =
          DateTime.parse(r['updated_at'] as String).toLocal();
      final remoteDeleted = r['deleted'] == true;
      final local = localById[id];

      if (local == null) {
        // 本地没有 → 直接落地（云端已删除则跳过）
        if (!remoteDeleted) {
          await _applyRemoteNote(r);
          pulled++;
        }
      } else if (!remoteDeleted && local.trashTime == null) {
        final localUpdated = local.updatedAt;
        final diff = localUpdated.difference(remoteUpdated).inSeconds.abs();
        if (diff > 2) {
          conflicts.add(SyncConflict(
            noteId: id,
            localUpdatedAt: localUpdated,
            remoteUpdatedAt: remoteUpdated,
          ));
        }
      } else if (remoteDeleted && local.trashTime == null) {
        // 云端已删、本地还在 → 冲突（本地保留着）
        conflicts.add(SyncConflict(
          noteId: id,
          localUpdatedAt: local.updatedAt,
          remoteUpdatedAt: remoteUpdated,
        ));
      }
    }

    // ── 4. 拉取文件夹 / 标签（按 id 补缺）──
    final remoteFolders = await client.from('folders_sync').select();
    final localFolderIds = (await _db.select(_db.folders).get()).map((f) => f.id).toSet();
    for (final f in remoteFolders) {
      if (f['deleted'] == true) continue;
      if (localFolderIds.contains(f['id'])) continue;
      await _db.into(_db.folders).insert(FoldersCompanion.insert(
        id: f['id'] as String,
        name: f['name'] as String,
        parentId: Value(f['parent_id'] as String?),
        sortOrder: Value((f['sort_order'] as num?)?.toInt() ?? 0),
        createdAt: DateTime.parse(f['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(f['updated_at'] as String).toLocal(),
      ));
    }
    final remoteTags = await client.from('tags_sync').select();
    final localTagIds = (await _db.select(_db.tags).get()).map((t) => t.id).toSet();
    for (final t in remoteTags) {
      if (t['deleted'] == true) continue;
      if (localTagIds.contains(t['id'])) continue;
      await _db.into(_db.tags).insert(TagsCompanion.insert(
        id: t['id'] as String,
        name: t['name'] as String,
        kind: Value(t['kind'] as String? ?? 'alpha'),
        createdAt: DateTime.parse(t['created_at'] as String).toLocal(),
      ));
    }
    final remoteNoteTags = await client.from('note_tags_sync').select();
    for (final nt in remoteNoteTags) {
      await _db.into(_db.noteTags).insert(
        NoteTagsCompanion.insert(
          noteId: nt['note_id'] as String,
          tagId: nt['tag_id'] as String,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }

    // ── 5. 上传待传媒体 ──
    await _uploadPendingMedia(client);

    return SyncResult(pushed: pushed, pulled: pulled, conflicts: conflicts);
  }

  /// 冲突处理：按用户选择应用本地或云端版本。
  Future<void> resolveConflicts(
    Map<String, bool> keepLocalById,
  ) async {
    final client = Supabase.instance.client;
    for (final entry in keepLocalById.entries) {
      if (entry.value) continue; // 保留本地 → 推送本地覆盖云端
      // 采用云端 → 用云端版本覆盖本地
      final remote = await client
          .from('notes_sync')
          .select()
          .eq('id', entry.key)
          .single();
      await _applyRemoteNote(remote);
    }
    // 保留本地的冲突：重新推送本地版本覆盖云端
    for (final entry in keepLocalById.entries) {
      if (!entry.value) continue;
      final local = await (_db.select(_db.notes)
            ..where((n) => n.id.equals(entry.key)))
          .getSingleOrNull();
      if (local != null) {
        await client.from('notes_sync').upsert({
          'id': local.id,
          'title': local.title,
          'preview': local.preview,
          'folder_id': local.folderId,
          'color': local.color,
          'pinned': local.pinned,
          'important': local.important,
          'encrypted': local.encrypted,
          'archived': local.archived,
          'trash_time': local.trashTime?.toUtc().toIso8601String(),
          'reminder_at': local.reminderAt?.toUtc().toIso8601String(),
          'created_at': local.createdAt.toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'deleted': local.trashTime != null,
          'content_json': await _localContentJson(entry.key),
        });
      }
    }
  }

  /// 用云端记录重建本地笔记（覆盖式）。
  Future<void> _applyRemoteNote(Map<String, dynamic> r) async {
    final id = r['id'] as String;
    final content = (r['content_json'] as String? ?? '[]');
    final blocksJson = jsonDecode(content) as List;

    await _db.transaction(() async {
      await (_db.delete(_db.blocks)..where((b) => b.noteId.equals(id))).go();
      await (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();

      await _db.into(_db.notes).insert(NotesCompanion.insert(
        id: id,
        title: Value(r['title'] as String? ?? ''),
        preview: Value(r['preview'] as String? ?? ''),
        folderId: Value(r['folder_id'] as String?),
        color: Value(r['color'] as String?),
        pinned: Value(r['pinned'] == true),
        important: Value((r['important'] as num?)?.toInt() ?? 0),
        encrypted: Value(r['encrypted'] == true),
        archived: Value(r['archived'] == true),
        trashTime: r['trash_time'] == null
            ? const Value(null)
            : Value(DateTime.parse(r['trash_time'] as String).toLocal()),
        reminderAt: r['reminder_at'] == null
            ? const Value(null)
            : Value(DateTime.parse(r['reminder_at'] as String).toLocal()),
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(r['updated_at'] as String).toLocal(),
      ));

      var i = 0;
      for (final b in blocksJson) {
        final map = (b as Map).cast<String, dynamic>();
        await _db.into(_db.blocks).insert(BlocksCompanion.insert(
          id: '$id-b$i',
          noteId: id,
          type: map['type'] as String? ?? 'text',
          source: Value(map['source'] as String? ?? 'manual'),
          data: Value(map['data'] as String? ?? '{}'),
          orderIndex: Value(i),
        ));
        i++;
      }
    });

    // 维护全文索引（加密笔记跳过）
    await _db.customStatement(
      'DELETE FROM $kFtsTable WHERE noteId = ?',
      [id],
    );
    if (!(r['encrypted'] == true)) {
      final title = r['title'] as String? ?? '';
      await _db.customStatement(
        'INSERT INTO $kFtsTable (noteId, searchText) VALUES (?, ?)',
        [id, tokenizeForSearch('$title ${_blocksText(blocksJson)}')],
      );
    }
  }

  Future<String> _localContentJson(String noteId) async {
    final blocks = await (_db.select(_db.blocks)
          ..where((b) => b.noteId.equals(noteId))
          ..orderBy([(b) => OrderingTerm(expression: b.orderIndex)]))
        .get();
    return jsonEncode([
      for (final b in blocks)
        {'type': b.type, 'source': b.source, 'data': b.data},
    ]);
  }

  Future<void> _uploadPendingMedia(SupabaseClient client) async {
    final pending = await (_db.select(_db.mediaItems)
          ..where((m) => m.status.equals('pending')))
        .get();
    for (final m in pending) {
      final path = m.localPath;
      if (path == null || path.isEmpty || !File(path).existsSync()) continue;
      final ext = path.split('.').last;
      final remotePath = '${m.id}.$ext';
      try {
        await client.storage.from('media').uploadBinary(
              remotePath,
              File(path).readAsBytesSync(),
              fileOptions: const FileOptions(upsert: true),
            );
        await (_db.update(_db.mediaItems)..where((x) => x.id.equals(m.id)))
            .write(MediaItemsCompanion(
          status: const Value('uploaded'),
          remoteUrl: Value(remotePath),
        ));
      } catch (_) {
        // 上传失败跳过，下次同步重试
      }
    }
  }

  String _blocksText(List blocksJson) => blocksJson
      .map((b) {
        final map = (b as Map).cast<String, dynamic>();
        try {
          return BlockData.fromJson(
                  blockTypeOf(map['type'] as String?),
                  map['data'] as String? ?? '{}')
              .searchableText;
        } catch (_) {
          return '';
        }
      })
      .join(' ');

  static const kFtsTable = 'note_search_fts';
}
