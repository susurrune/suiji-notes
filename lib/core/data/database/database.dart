import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

/// 应用数据库（本地优先的唯一事实源）。
///
/// 分层约定：UI/功能层不直接触碰数据库，一律经 `core/data/repositories` 访问。
@DriftDatabase(
  tables: [
    Folders,
    Tags,
    NoteTags,
    Notes,
    Blocks,
    MediaItems,
    ChangeLogs,
    Profiles,
    Secrets,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // FTS5 虚拟表用原生 SQL 创建（drift 2.34 无内建 FTS 注解）。
          await customStatement(FtsSchema.createStatement);
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(notes, notes.preview);
          }
          if (from < 3) {
            await m.createTable(profiles);
          }
          if (from < 4) {
            await m.createTable(secrets);
          }
          if (from < 5) {
            await m.addColumn(profiles, profiles.syncUrl);
            await m.addColumn(profiles, profiles.syncAnonKey);
          }
        },
      );

  static QueryExecutor _open() {
    return driftDatabase(
      name: 'suiji',
      native: DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
