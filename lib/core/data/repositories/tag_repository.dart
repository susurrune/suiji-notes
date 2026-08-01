import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/enums.dart';
import '../database/database.dart';

/// 标签（跨文件夹打标）与 笔记-标签 关系管理。
class TagRepository {
  TagRepository(this._db);
  final AppDatabase _db;

  Stream<List<Tag>> watchAll() {
    return (_db.select(_db.tags)..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .watch();
  }

  Future<List<Tag>> tagsForNote(String noteId) async {
    final rows = await (_db.select(_db.noteTags)..where((t) => t.noteId.equals(noteId)))
        .get();
    final ids = rows.map((r) => r.tagId).toList();
    if (ids.isEmpty) return const [];
    return (_db.select(_db.tags)..where((t) => t.id.isIn(ids))).get();
  }

  /// 替换一篇笔记的全部标签。
  Future<void> setTagsForNote(String noteId, List<String> tagIds) async {
    await _db.transaction(() async {
      await (_db.delete(_db.noteTags)..where((t) => t.noteId.equals(noteId))).go();
      for (final tagId in tagIds) {
        await _db.into(_db.noteTags).insert(
          NoteTagsCompanion.insert(noteId: noteId, tagId: tagId),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  /// 创建标签；同名同类型已存在则返回既有标签。
  Future<Tag> createTag(String name, TagKind kind) async {
    final existing = await (_db.select(_db.tags)
          ..where((t) => t.name.equals(name) & t.kind.equals(kind.name)))
        .getSingleOrNull();
    if (existing != null) return existing;
    final id = const Uuid().v4();
    await _db.into(_db.tags).insert(TagsCompanion.insert(
      id: id,
      name: name,
      kind: Value(kind.name),
      createdAt: DateTime.now(),
    ));
    return (await (_db.select(_db.tags)..where((t) => t.id.equals(id))).getSingle());
  }

  Future<void> renameTag(String id, String name) async {
    await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
      TagsCompanion(name: Value(name)),
    );
  }

  Future<void> deleteTag(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.noteTags)..where((t) => t.tagId.equals(id))).go();
      await (_db.delete(_db.tags)..where((t) => t.id.equals(id))).go();
    });
  }
}
