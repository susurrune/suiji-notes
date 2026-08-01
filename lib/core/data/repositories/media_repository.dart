import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/enums.dart';
import '../database/database.dart';

/// 媒体资源（图片/语音/手绘二进制）管理。
///
/// MVP 阶段媒体为本地文件；Phase 3 云同步时 `status` 追踪上传进度。
class MediaRepository {
  MediaRepository(this._db);
  final AppDatabase _db;

  Future<MediaItem> createMedia({
    required String noteId,
    String? blockId,
    required String localPath,
    required String mime,
    int size = 0,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.mediaItems).insert(MediaItemsCompanion.insert(
      id: id,
      noteId: noteId,
      blockId: Value(blockId),
      localPath: Value(localPath),
      mime: Value(mime),
      size: Value(size),
      createdAt: DateTime.now(),
    ));
    return (await (_db.select(_db.mediaItems)..where((m) => m.id.equals(id)))
        .getSingle());
  }

  Future<void> setMediaStatus(String id, MediaStatus status) async {
    await (_db.update(_db.mediaItems)..where((m) => m.id.equals(id))).write(
      MediaItemsCompanion(status: Value(status.name)),
    );
  }

  Future<MediaItem?> getMedia(String id) async {
    return (_db.select(_db.mediaItems)..where((m) => m.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<MediaItem>> mediaForNote(String noteId) async {
    return (_db.select(_db.mediaItems)..where((m) => m.noteId.equals(noteId))).get();
  }

  Future<void> deleteMedia(String id) async {
    await (_db.delete(_db.mediaItems)..where((m) => m.id.equals(id))).go();
  }
}
