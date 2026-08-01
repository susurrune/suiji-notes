import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/block_data.dart';
import '../../domain/enums.dart';
import '../../search/tokenizer.dart';
import '../../security/secret_service.dart';
import '../database/database.dart';
import '../database/tables.dart';

/// 笔记 + 内容块 + 媒体 的聚合视图，供编辑器与列表使用。
class NoteWithBlocks {
  const NoteWithBlocks({required this.note, required this.blocks, this.media = const []});
  final Note note;
  final List<Block> blocks; // 按 orderIndex 升序
  final List<MediaItem> media;
}

/// 笔记生命周期与内容管理。
///
/// 原则：
/// - 写操作全部在事务内完成（笔记 + 块 + 搜索索引 + 变更日志一致）。
/// - 任何变更写入 ChangeLogs（outbox），Phase 3 同步引擎据此推拉。
/// - 加密笔记不写入 FTS 明文索引。
class NoteRepository {
  NoteRepository(this._db, [SecretService? secrets]) : _secrets = secrets;
  final AppDatabase _db;
  final SecretService? _secrets;

  // ───────────────────────── 查询 ─────────────────────────

  /// 按 id 取笔记聚合。
  Future<NoteWithBlocks?> getNote(String id) async {
    final note = await (_db.select(_db.notes)..where((n) => n.id.equals(id)))
        .getSingleOrNull();
    if (note == null) return null;
    return _loadAggregate(note);
  }

  /// 读取时是否已解锁解密（加密笔记需要解锁才能拿到明文内容）。
  bool canDecryptEncrypted() => _secrets?.unlocked ?? false;

  /// 列表：非回收站、可选按文件夹/归档过滤，置顶优先 + 更新时间倒序。
  Stream<List<Note>> watchNotes({String? folderId, bool archived = false}) {
    final q = _db.select(_db.notes)
      ..where((n) {
        var cond = n.deletedAt.isNull() &
            n.trashTime.isNull() &
            n.archived.equals(archived);
        if (folderId != null) cond &= n.folderId.equals(folderId);
        return cond;
      })
      ..orderBy([
        (n) => OrderingTerm(expression: n.pinned, mode: OrderingMode.desc),
        (n) => OrderingTerm(expression: n.updatedAt, mode: OrderingMode.desc),
      ]);
    return q.watch();
  }

  /// 回收站列表（软删除）。
  Stream<List<Note>> watchTrash() {
    final q = _db.select(_db.notes)
      ..where((n) => n.trashTime.isNotNull())
      ..orderBy([
        (n) => OrderingTerm(expression: n.trashTime, mode: OrderingMode.desc),
      ]);
    return q.watch();
  }

  // ───────────────────────── 新建 / 保存 ─────────────────────────

  /// 新建笔记（含内容块），一次事务写库 + 建索引 + 记日志。
  Future<NoteWithBlocks> createNote(
    String id, {
    String? folderId,
    String? color,
    bool pinned = false,
    int important = 0,
    bool encrypted = false,
    List<BlockDraft> blocks = const [],
  }) async {
    final now = DateTime.now();
    // 加密笔记不存明文标题/预览
    final title = encrypted ? '' : deriveTitle(blocks);
    final preview = encrypted ? '' : buildNotePreview(blocks);
    await _db.transaction(() async {
      await _db.into(_db.notes).insert(NotesCompanion.insert(
        id: id,
        folderId: Value(folderId),
        color: Value(color),
        pinned: Value(pinned),
        important: Value(important),
        encrypted: Value(encrypted),
        title: Value(title),
        preview: Value(preview),
        createdAt: now,
        updatedAt: now,
      ));
      await _insertBlocks(id, blocks, encrypt: encrypted);
      await _reindex(id, title);
      await _log('note', id, SyncOp.insert, await _notePayload(id, title));
    });
    return (await getNote(id))!;
  }

  /// 整体替换一篇笔记的内容块（编辑器保存路径）。
  Future<void> saveNoteContent(String noteId, List<BlockDraft> blocks) async {
    final now = DateTime.now();
    final note = await (_db.select(_db.notes)..where((n) => n.id.equals(noteId)))
        .getSingleOrNull();
    final encrypted = note?.encrypted ?? false;
    // 加密笔记不存明文标题/预览
    final title = encrypted ? '' : deriveTitle(blocks);
    final preview = encrypted ? '' : buildNotePreview(blocks);
    await _db.transaction(() async {
      await (_db.delete(_db.blocks)..where((b) => b.noteId.equals(noteId)))
          .go();
      await _insertBlocks(noteId, blocks, encrypt: encrypted);
      await (_db.update(_db.notes)..where((n) => n.id.equals(noteId))).write(
        NotesCompanion(
          title: Value(title),
          preview: Value(preview),
          updatedAt: Value(now),
        ),
      );
      await _reindex(noteId, title);
      await _log('note', noteId, SyncOp.update, await _notePayload(noteId, title));
    });
  }

  // ───────────────────────── 属性操作 ─────────────────────────

  Future<void> setPinned(String id, bool pinned) =>
      _touch(id, NotesCompanion(pinned: Value(pinned)));

  Future<void> setImportance(String id, int level) =>
      _touch(id, NotesCompanion(important: Value(level)));

  Future<void> setColor(String id, String? color) =>
      _touch(id, NotesCompanion(color: Value(color)));

  Future<void> setArchived(String id, bool archived) =>
      _touch(id, NotesCompanion(archived: Value(archived)));

  Future<void> setEncrypted(String id, bool encrypted) =>
      _touch(id, NotesCompanion(encrypted: Value(encrypted)));

  Future<void> setReminder(String id, DateTime? reminderAt) =>
      _touch(id, NotesCompanion(reminderAt: Value(reminderAt)));

  Future<void> moveToFolder(String id, String? folderId) =>
      _touch(id, NotesCompanion(folderId: Value(folderId)));

  /// 移入回收站（软删除，记录时间用于可恢复期限）。
  Future<void> trashNote(String id) async {
    await _touch(id, NotesCompanion(trashTime: Value(DateTime.now())));
  }

  /// 从回收站恢复。
  Future<void> restoreNote(String id) async {
    await _touch(id, NotesCompanion(trashTime: Value(null)));
  }

  /// 彻底删除（物理删除 + 清理索引与变更日志）。
  Future<void> deletePermanently(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.blocks)..where((b) => b.noteId.equals(id))).go();
      await _db.customStatement(
          'DELETE FROM ${FtsSchema.tableName} WHERE noteId = ?', [id]);
      await (_db.delete(_db.noteTags)..where((t) => t.noteId.equals(id))).go();
      await (_db.delete(_db.mediaItems)..where((m) => m.noteId.equals(id))).go();
      await (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();
      await _log('note', id, SyncOp.delete, '{}');
    });
  }

  /// 按删除时间清理超期回收站笔记（可恢复期限由调用方传天数）。
  Future<int> purgeTrashOlderThan(Duration age) async {
    final cutoff = DateTime.now().subtract(age);
    final expired = await (_db.select(_db.notes)
          ..where((n) => n.trashTime.isNotNull() & n.trashTime.isSmallerThanValue(cutoff)))
        .get();
    for (final n in expired) {
      await deletePermanently(n.id);
    }
    return expired.length;
  }

  // ───────────────────────── 待办聚合 ─────────────────────────

  /// 聚合所有非回收站笔记中的清单块为待办条目（供待办视图）。
  Stream<List<TodoEntry>> watchTodos() {
    final q = _db.select(_db.notes).join([
      innerJoin(_db.blocks, _db.blocks.noteId.equalsExp(_db.notes.id)),
    ])
      ..where(
        _db.notes.trashTime.isNull() &
            _db.notes.deletedAt.isNull() &
            _db.blocks.type.equals('checklist'),
      )
      ..orderBy([OrderingTerm(expression: _db.blocks.orderIndex)]);

    return q.watch().map((rows) {
      final todos = <TodoEntry>[];
      for (final row in rows) {
        final note = row.readTable(_db.notes);
        final block = row.readTable(_db.blocks);
        final data = BlockData.fromJson(blockTypeOf(block.type), block.data);
        if (data is! ChecklistBlockData) continue;
        for (final item in data.items) {
          todos.add(TodoEntry(
            noteId: note.id,
            noteTitle: note.title,
            blockId: block.id,
            item: item,
          ));
        }
      }
      return todos;
    });
  }

  /// 更新某个清单项（勾选 / 优先级 / 截止时间）。
  Future<void> updateChecklistItem(
    String noteId,
    String blockId,
    ChecklistItem updated,
  ) async {
    final agg = await getNote(noteId);
    if (agg == null) return;
    final drafts = <BlockDraft>[];
    for (final b in agg.blocks) {
      if (b.id == blockId) {
        final data = BlockData.fromJson(blockTypeOf(b.type), b.data);
        if (data is ChecklistBlockData) {
          drafts.add(BlockDraft(
            BlockType.checklist,
            ChecklistBlockData(items: [
              for (final it in data.items)
                it.id == updated.id ? updated : it,
            ]),
          ));
          continue;
        }
      }
      drafts.add(BlockDraft(
        blockTypeOf(b.type),
        BlockData.fromJson(blockTypeOf(b.type), b.data),
        source: blockSourceOf(b.source),
      ));
    }
    await saveNoteContent(noteId, drafts);
  }

  // ───────────────────────── 私有 ─────────────────────────

  Future<NoteWithBlocks> _loadAggregate(Note note) async {
    final blocksQ = _db.select(_db.blocks)
      ..where((b) => b.noteId.equals(note.id))
      ..orderBy([(b) => OrderingTerm(expression: b.orderIndex)]);
    final mediaQ = _db.select(_db.mediaItems)
      ..where((m) => m.noteId.equals(note.id));
    final blocks = await blocksQ.get();
    final media = await mediaQ.get();

    // 加密笔记：已解锁才解密块内容，否则返回密文原样（编辑器会显示锁定态）
    final blocksOut = <Block>[];
    for (final b in blocks) {
      var data = b.data;
      if (note.encrypted && canDecryptEncrypted()) {
        data = await _secrets!.decrypt(data);
      }
      blocksOut.add(b.copyWith(data: data));
    }
    return NoteWithBlocks(note: note, blocks: blocksOut, media: media);
  }

  Future<void> _insertBlocks(
    String noteId,
    List<BlockDraft> drafts, {
    bool encrypt = false,
  }) async {
    const uuid = Uuid();
    for (var i = 0; i < drafts.length; i++) {
      final d = drafts[i];
      var data = d.data.toJsonString();
      if (encrypt) data = await _secrets!.encrypt(data);
      await _db.into(_db.blocks).insert(BlocksCompanion.insert(
            id: uuid.v4(),
            noteId: noteId,
            type: d.type.name,
            source: Value(d.source.name),
            data: Value(data),
            orderIndex: Value(i),
          ));
    }
  }

  /// 维护 FTS 索引：预分词全文 = 标题 + 全部块的可检索文本。加密笔记跳过。
  /// FTS 表为原生虚拟表，用 DELETE + INSERT 做 upsert。
  Future<void> _reindex(String noteId, String title) async {
    final note = await (_db.select(_db.notes)..where((n) => n.id.equals(noteId)))
        .getSingleOrNull();
    final table = FtsSchema.tableName;
    await _db.customStatement('DELETE FROM $table WHERE noteId = ?', [noteId]);
    if (note == null || note.encrypted) return;
    final blocks = await (_db.select(_db.blocks)..where((b) => b.noteId.equals(noteId))).get();
    final searchable = blocks
        .map((b) => BlockData.fromJson(blockTypeOf(b.type), b.data).searchableText)
        .join(' ');
    final searchText = tokenizeForSearch('$title $searchable');
    await _db.customStatement(
      'INSERT INTO $table (noteId, searchText) VALUES (?, ?)',
      [noteId, searchText],
    );
  }

  /// 属性修改的统一路径：事务内更新 + 记日志。
  Future<void> _touch(String id, NotesCompanion changes) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
        changes.copyWith(updatedAt: Value(now)),
      );
      await _log('note', id, SyncOp.update, await _notePayload(id));
    });
  }

  Future<String> _notePayload(String id, [String? title]) async {
    final n = await (_db.select(_db.notes)..where((x) => x.id.equals(id)))
        .getSingleOrNull();
    return jsonEncode({
      'id': id,
      'title': title ?? n?.title ?? '',
      'updatedAt': n?.updatedAt.toIso8601String(),
    });
  }

  Future<void> _log(String entity, String entityId, SyncOp op, String payload) {
    return _db.into(_db.changeLogs).insert(ChangeLogsCompanion.insert(
          entity: entity,
          entityId: entityId,
          op: Value(op.name),
          ts: DateTime.now(),
          payload: Value(payload),
        ));
  }
}

/// 从块草稿派生标题：首个标题块 -> 首个文本块前 60 字 -> 空。
String deriveTitle(List<BlockDraft> drafts) {
  for (final d in drafts) {
    if (d.type == BlockType.heading) {
      final text = (d.data as HeadingBlockData).text.trim();
      if (text.isNotEmpty) return text;
    }
  }
  for (final d in drafts) {
    if (d.type == BlockType.text) {
      final text = (d.data as TextBlockData).text.trim();
      if (text.isNotEmpty) return text.length <= 60 ? text : text.substring(0, 60);
    }
  }
  return '';
}
