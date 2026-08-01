/// 领域枚举与值类型。
///
/// 与存储层解耦：所有功能模块引用这里的枚举，而不是直接依赖 drift 生成的类型。
library;

/// 内容块类型。一篇笔记由若干块按序组成，支持任意混排。
enum BlockType {
  text,
  checklist,
  image,
  drawing,
  voice,
  table,
  heading,
  bullet,
  divider,
}

/// 文本来源。标记块内容来自手动输入、图片 OCR 还是语音转写，
/// 用于全文检索范围与「按来源筛选」。
enum BlockSource { manual, imageOcr, voiceAsr }

/// 标签类型（参考原子笔记：字母 / 数字 / 图形三类）。
enum TagKind { alpha, numeric, shape }

/// 媒体文件上传状态（Phase 3 云同步使用）。
enum MediaStatus { pending, uploaded }

/// 变更日志操作类型（Phase 3 云同步的 outbox 记录）。
enum SyncOp { insert, update, delete }

/// 笔记重要程度（0=普通，1-3 递进）。
enum NoteImportance { normal, low, medium, high }

/// 笔记颜色标记（视觉分类，参考 Keep 卡片背景色）。
enum NoteColor {
  none,
  yellow,
  green,
  blue,
  pink,
  purple,
  orange,
  teal,
}

// ────────────────────────────────────────────────────────────
// 字符串 <-> 枚举 转换（数据库列为普通 text，存枚举 .name）。
// 未知值回落默认，保证旧数据/脏数据不崩溃。
// ────────────────────────────────────────────────────────────

BlockType blockTypeOf(String? s) =>
    BlockType.values.asNameMap()[s] ?? BlockType.text;
String blockTypeName(BlockType v) => v.name;

BlockSource blockSourceOf(String? s) =>
    BlockSource.values.asNameMap()[s] ?? BlockSource.manual;

TagKind tagKindOf(String? s) => TagKind.values.asNameMap()[s] ?? TagKind.alpha;

MediaStatus mediaStatusOf(String? s) =>
    MediaStatus.values.asNameMap()[s] ?? MediaStatus.pending;

SyncOp syncOpOf(String? s) => SyncOp.values.asNameMap()[s] ?? SyncOp.update;
