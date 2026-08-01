import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';
import '../data/repositories/profile_repository.dart';
import '../domain/block_data.dart';
import '../security/secret_service.dart';
import '../sync/sync_service.dart';
import '../data/repositories/folder_repository.dart';
import '../data/repositories/media_repository.dart';
import '../data/repositories/note_repository.dart';
import '../data/repositories/search_repository.dart';
import '../data/repositories/tag_repository.dart';

// ────────────────────────────────────────────────────────────
// 数据层 Provider（应用生命周期内单例）
// ────────────────────────────────────────────────────────────

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final secretServiceProvider = Provider<SecretService>(
  (ref) => SecretService(ref.watch(databaseProvider)),
);

final noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => NoteRepository(
    ref.watch(databaseProvider),
    ref.watch(secretServiceProvider),
  ),
);

final folderRepositoryProvider = Provider<FolderRepository>(
  (ref) => FolderRepository(ref.watch(databaseProvider)),
);

final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => TagRepository(ref.watch(databaseProvider)),
);

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => SearchRepository(ref.watch(databaseProvider)),
);

final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => MediaRepository(ref.watch(databaseProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(databaseProvider)),
);

/// 个人资料（昵称 + 头像本地路径）。
final profileProvider = FutureProvider<Profile?>((ref) {
  return ref.watch(profileRepositoryProvider).getProfile();
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref.watch(databaseProvider));
});

// ────────────────────────────────────────────────────────────
// 偏好设置
// ────────────────────────────────────────────────────────────

/// 主题模式（跟随系统 / 浅色 / 深色）。
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

/// 列表 / 网格视图切换。
final viewModeProvider = StateProvider<bool>((ref) => false); // false=列表 true=网格

/// 主列表（按选中文件夹过滤，非回收站，置顶优先）。
final notesListProvider = StreamProvider<List<Note>>((ref) {
  final folderId = ref.watch(selectedFolderProvider);
  return ref.watch(noteRepositoryProvider).watchNotes(folderId: folderId);
});

/// 回收站列表。
final trashListProvider = StreamProvider<List<Note>>((ref) {
  return ref.watch(noteRepositoryProvider).watchTrash();
});

/// 全部文件夹（扁平列表，UI 层按 parentId 组织成树）。
final foldersListProvider = StreamProvider<List<Folder>>((ref) {
  return ref.watch(folderRepositoryProvider).watchAll();
});

/// 全部标签。
final tagsListProvider = StreamProvider<List<Tag>>((ref) {
  return ref.watch(tagRepositoryProvider).watchAll();
});

/// 当前主列表选中的文件夹（null = 全部）。
final selectedFolderProvider = StateProvider<String?>((ref) => null);

/// 待办视图（聚合所有清单块）。
final todosProvider = StreamProvider<List<TodoEntry>>((ref) {
  return ref.watch(noteRepositoryProvider).watchTodos();
});

/// 「随笔」文件夹：首次使用自动创建，返回其 id。
final suibiFolderProvider = FutureProvider<String?>((ref) async {
  final folders = ref.watch(folderRepositoryProvider);
  final all = await folders.watchAll().first;
  final existing = all.where((f) => f.name == '随笔').firstOrNull;
  if (existing != null) return existing.id;
  final created = await folders.createFolder('随笔');
  return created.id;
});

/// 随笔条目（「随笔」文件夹下的笔记，按更新时间倒序）。
final suibiNotesProvider = StreamProvider<List<Note>>((ref) async* {
  final folderId = await ref.watch(suibiFolderProvider.future);
  if (folderId == null) {
    yield const [];
    return;
  }
  yield* ref.watch(noteRepositoryProvider).watchNotes(folderId: folderId);
});

