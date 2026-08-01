import 'package:drift/drift.dart';

/// 文件夹（树形归档分类）。
@DataClassName('Folder')
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 标签（跨文件夹打标，字母/数字/图形三类）。
/// `kind` 存 TagKind.name 字符串（见 core/domain/enums.dart 与
/// 转换辅助 `tagKindOf`）。
@DataClassName('Tag')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => text().withDefault(const Constant('alpha'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 笔记-标签 多对多关系表。
@DataClassName('NoteTag')
class NoteTags extends Table {
  TextColumn get noteId => text()();
  TextColumn get tagId => text()();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}

/// 笔记（统一模型：速记卡片与文档笔记是同一模型的两种渲染密度）。
@DataClassName('Note')
class Notes extends Table {
  TextColumn get id => text()();
  /// 派生标题：取首个标题块或首个文本块前 N 字；可为空。
  TextColumn get title => text().withDefault(const Constant(''))();
  /// 列表卡片预览（去格式化后的纯文本摘录，保存时计算，避免列表 N+1 查询）。
  TextColumn get preview => text().withDefault(const Constant(''))();
  /// 所属文件夹；null = 收件箱（未归档）。
  TextColumn get folderId => text().nullable()();
  /// 颜色标记；null = 默认。
  TextColumn get color => text().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  IntColumn get important => integer().withDefault(const Constant(0))();
  /// 隐私笔记标记（加密内容存隔离区，不入明文索引）。
  BoolColumn get encrypted => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  /// 进回收站时间；null = 不在回收站。软删除 + 可恢复期限。
  DateTimeColumn get trashTime => dateTime().nullable()();
  DateTimeColumn get reminderAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  /// 彻底删除时间（硬删除标记，供清理）。
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 内容块。一篇笔记 = 若干块的有序集合。
/// `type`/`source` 存 BlockType/BlockSource.name 字符串。
@DataClassName('Block')
class Blocks extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  TextColumn get type => text()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  /// 块数据（JSON），按 type 解释。见 BlockData codec。
  TextColumn get data => text().withDefault(const Constant('{}'))();
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 媒体资源（图片/语音/手绘二进制的本地路径与上传状态）。
/// `status` 存 MediaStatus.name 字符串。
@DataClassName('MediaItem')
class MediaItems extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  /// 关联块；null = 尚未挂到某块。
  TextColumn get blockId => text().nullable()();
  TextColumn get localPath => text().nullable()();
  TextColumn get remoteUrl => text().nullable()();
  TextColumn get mime => text().nullable()();
  IntColumn get size => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 变更日志（outbox）。本地优先存储的增量来源，Phase 3 供同步引擎推拉。
/// `op` 存 SyncOp.name 字符串。
@DataClassName('ChangeLogEntry')
class ChangeLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get op => text().withDefault(const Constant('update'))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get ts => dateTime()();
  /// 变更快照（JSON），用于冲突合并决策。
  TextColumn get payload => text().withDefault(const Constant('{}'))();
}

/// 个人资料（单行，id 恒为 'me'）：头像本地路径 + 昵称 + 云同步配置。
@DataClassName('Profile')
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get avatarPath => text().nullable()();
  /// Supabase 项目 URL（云同步）。
  TextColumn get syncUrl => text().nullable()();
  /// Supabase anon key（云同步）。
  TextColumn get syncAnonKey => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 加密密钥存储（单行）：主密钥经「密码 PBKDF2 派生密钥」AES-GCM 封存。
/// 字段均为 base64 编码。错误密码由 GCM 认证失败识别。
@DataClassName('SecretRecord')
class Secrets extends Table {
  TextColumn get id => text()();
  /// PBKDF2 盐（base64）。
  TextColumn get salt => text()();
  /// 封存主密钥的 GCM nonce（base64）。
  TextColumn get nonce => text()();
  /// 封存后的主密钥密文（base64）。
  TextColumn get sealedKey => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// FTS5 全文检索虚拟表（由原生 SQL 在 migration 中创建，非 drift 表）。
///
/// 索引列存「预分词」后的文本：CJK 拆成单字（空格分隔），Latin 保留单词。
/// 加密笔记不写入此表。SQL 建表语句见 database.dart。
abstract final class FtsSchema {
  static const tableName = 'note_search_fts';
  static const createStatement = '''
CREATE VIRTUAL TABLE IF NOT EXISTS $tableName USING fts5(
  noteId UNINDEXED,
  searchText,
  tokenize = 'unicode61'
)''';
}
