import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';

/// 文件夹（树形归档）管理。
class FolderRepository {
  FolderRepository(this._db);
  final AppDatabase _db;

  /// 全部文件夹（扁平），由 UI 层按 parentId 组织成树。
  Stream<List<Folder>> watchAll() {
    return (_db.select(_db.folders)
          ..orderBy([
            (f) => OrderingTerm(expression: f.sortOrder),
            (f) => OrderingTerm(expression: f.createdAt),
          ]))
        .watch();
  }

  Future<Folder?> getFolder(String id) async {
    return (_db.select(_db.folders)..where((f) => f.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Folder> createFolder(String name, {String? parentId}) async {
    final now = DateTime.now();
    final id = const Uuid().v4();
    await _db.into(_db.folders).insert(FoldersCompanion.insert(
      id: id,
      name: name,
      parentId: Value(parentId),
      createdAt: now,
      updatedAt: now,
    ));
    return (await getFolder(id))!;
  }

  Future<void> renameFolder(String id, String name) async {
    await (_db.update(_db.folders)..where((f) => f.id.equals(id))).write(
      FoldersCompanion(name: Value(name), updatedAt: Value(DateTime.now())),
    );
  }

  /// 移动文件夹（改变父级）。禁止成为自己的后代。
  Future<void> moveFolder(String id, String? newParentId) async {
    if (newParentId == id) return;
    await (_db.update(_db.folders)..where((f) => f.id.equals(id))).write(
      FoldersCompanion(parentId: Value(newParentId), updatedAt: Value(DateTime.now())),
    );
  }

  /// 删除文件夹：其子文件夹上移一层，其下笔记移回收件箱（folderId=null）。
  Future<void> deleteFolder(String id) async {
    final folder = await getFolder(id);
    if (folder == null) return;
    await _db.transaction(() async {
      final parentId = folder.parentId;
      // 子文件夹重挂到被删文件夹的父级
      await (_db.update(_db.folders)..where((f) => f.parentId.equals(id))).write(
        FoldersCompanion(parentId: Value(parentId), updatedAt: Value(DateTime.now())),
      );
      // 该文件夹下的笔记移回收件箱
      await (_db.update(_db.notes)..where((n) => n.folderId.equals(id))).write(
        NotesCompanion(folderId: const Value(null)),
      );
      await (_db.delete(_db.folders)..where((f) => f.id.equals(id))).go();
    });
  }
}
