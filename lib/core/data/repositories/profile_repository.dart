import 'package:drift/drift.dart';

import '../database/database.dart';

/// 个人资料管理（单行：id 恒为 'me'）。
/// 纯本地：头像为应用目录内文件路径，昵称文本。云账号随 Phase 3 同步接入。
class ProfileRepository {
  ProfileRepository(this._db);
  final AppDatabase _db;

  static const meId = 'me';

  Future<Profile?> getProfile() async {
    return (_db.select(_db.profiles)..where((p) => p.id.equals(meId)))
        .getSingleOrNull();
  }

  Future<void> updateName(String name) =>
      _upsert(name: name);

  Future<void> updateAvatar(String? avatarPath) =>
      _upsert(avatarPath: avatarPath);

  Future<void> updateSyncConfig(String? url, String? anonKey) =>
      _upsert(syncUrl: url, syncAnonKey: anonKey);

  Future<void> _upsert({
    String? name,
    String? avatarPath,
    String? syncUrl,
    String? syncAnonKey,
  }) async {
    final now = DateTime.now();
    final existing = await getProfile();
    if (existing == null) {
      await _db.into(_db.profiles).insert(ProfilesCompanion.insert(
        id: meId,
        name: Value(name ?? ''),
        avatarPath: Value(avatarPath),
        syncUrl: Value(syncUrl),
        syncAnonKey: Value(syncAnonKey),
        updatedAt: now,
      ));
    } else {
      await (_db.update(_db.profiles)..where((p) => p.id.equals(meId))).write(
        ProfilesCompanion(
          name: Value(name ?? existing.name),
          avatarPath: Value(avatarPath ?? existing.avatarPath),
          syncUrl: Value(syncUrl ?? existing.syncUrl),
          syncAnonKey: Value(syncAnonKey ?? existing.syncAnonKey),
          updatedAt: Value(now),
        ),
      );
    }
  }
}
