import 'package:drift/drift.dart';

import '../../domain/enums.dart';
import '../../search/tokenizer.dart';
import '../database/database.dart';
import '../database/tables.dart';

/// FTS5 全文检索 + 组合筛选。
///
/// 检索范围：标题 + 文本块 + OCR/ASR 来源文本（见 [tokenizeForSearch]）。
/// 加密笔记不入索引，因此不会在明文检索中暴露。
class SearchRepository {
  SearchRepository(this._db);
  final AppDatabase _db;

  /// 检索笔记。
  ///
  /// [query] 为空时等价于「浏览」：按更新时间倒序返回全部（含组合筛选）。
  /// [query] 非空时走 FTS5 MATCH，按相关度排序。
  Future<List<Note>> searchNotes({
    String query = '',
    String? folderId,
    String? tagId,
    String? color,
    BlockType? type,
    DateTime? from,
    DateTime? to,
  }) async {
    final ids = <String>[];
    if (query.trim().isNotEmpty) {
      final matchQuery = buildMatchQuery(query);
      if (matchQuery.isEmpty) return const [];
      final rows = await _db.customSelect(
        'SELECT noteId FROM ${FtsSchema.tableName} '
        'WHERE ${FtsSchema.tableName} MATCH ? ORDER BY rank',
        variables: [Variable(matchQuery)],
      ).get();
      ids.addAll(rows.map((r) => r.read<String>('noteId')));
      if (ids.isEmpty) return const [];
    }

    // 预取筛选用 id 集合（避免在 where 闭包内 await）
    final tagged = tagId == null
        ? null
        : await (_db.select(_db.noteTags)..where((t) => t.tagId.equals(tagId)))
              .map((t) => t.noteId)
              .get();
    final typed = type == null
        ? null
        : await (_db.select(_db.blocks)
                  ..where((b) => b.type.equals(type.name)))
              .map((b) => b.noteId)
              .get();

    // 组合筛选：在命中集（或全部）上叠加
    final q = _db.select(_db.notes)
      ..where((n) {
        var cond = n.deletedAt.isNull() & n.trashTime.isNull();
        if (ids.isNotEmpty) cond &= n.id.isIn(ids);
        if (folderId != null) cond &= n.folderId.equals(folderId);
        if (color != null) cond &= n.color.equals(color);
        if (from != null) cond &= n.updatedAt.isBiggerOrEqualValue(from);
        if (to != null) cond &= n.updatedAt.isSmallerOrEqualValue(to);
        if (tagged != null) cond &= n.id.isIn(tagged);
        if (typed != null) cond &= n.id.isIn(typed);
        return cond;
      });

    List<Note> notes;
    if (ids.isNotEmpty) {
      notes = await q.get();
      // 按 FTS 相关度顺序还原
      final order = <String, int>{for (var i = 0; i < ids.length; i++) ids[i]: i};
      notes.sort((a, b) =>
          (order[a.id] ?? 1 << 30).compareTo(order[b.id] ?? 1 << 30));
    } else {
      notes = await (q
            ..orderBy([
              (n) =>
                  OrderingTerm(expression: n.updatedAt, mode: OrderingMode.desc),
            ]))
          .get();
    }
    return notes;
  }
}
