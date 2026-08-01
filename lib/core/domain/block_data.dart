import 'dart:convert';

import 'enums.dart';

/// 新建/保存笔记时的块草稿（领域层概念，编辑器与仓库共用）。
class BlockDraft {
  const BlockDraft(this.type, this.data, {this.source = BlockSource.manual});
  final BlockType type;
  final BlockData data;
  final BlockSource source;
}

/// 从块草稿构建列表卡片预览（去格式化纯文本，约 80 字）。
/// 由 NoteRepository 在保存时写入 Notes.preview，避免列表 N+1 查询。
String buildNotePreview(List<BlockDraft> drafts) {
  final parts = <String>[];
  for (final d in drafts) {
    if (parts.length >= 2) break; // 预览取前两段
    final t = switch (d.data) {
      TextBlockData(:final text) => text.trim(),
      HeadingBlockData(:final text) => text.trim(),
      ChecklistBlockData(:final items) => items.map((e) => e.text).join('、'),
      BulletBlockData(:final items) => items.join('、'),
      VoiceBlockData(:final transcript) => '🎤 $transcript'.trim(),
      ImageBlockData() => '🖼 图片',
      DrawingBlockData() => '✏️ 手绘',
      TableBlockData(:final rows) =>
        rows.isNotEmpty ? rows.first.join(' ') : '',
      DividerBlockData() => '',
    };
    if (t.isNotEmpty) parts.add(t);
  }
  final text = parts.join(' · ');
  return text.length <= 80 ? text : text.substring(0, 80);
}

/// 内容块的类型化数据。与 drift 的 `blocks.data`（JSON 文本列）互转。
///
/// 每新增一种笔记类型（需求 §四 的扩展性要求），只需新增一个子类 +
/// 在 `fromJson`/`toJson` 中登记，UI 层与存储层无需改动。
sealed class BlockData {
  const BlockData();

  Map<String, dynamic> toJson();

  String toJsonString() => jsonEncode(toJson());

  /// 块内全部可检索文本（供全文索引）。图片块本身无文本。
  String get searchableText => '';

  static BlockData fromJson(BlockType type, String json) {
    Map<String, dynamic> map;
    try {
      map = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      map = const {};
    }
    return switch (type) {
      BlockType.text => TextBlockData(map['text'] as String? ?? ''),
      BlockType.heading => HeadingBlockData(
        map['text'] as String? ?? '',
        level: (map['level'] as num?)?.toInt() ?? 1,
      ),
      BlockType.checklist => ChecklistBlockData(
        title: map['title'] as String? ?? '',
        items: (map['items'] as List? ?? const [])
            .map(
              (e) => ChecklistItem.fromJson(
                (e as Map).cast<String, dynamic>(),
              ),
            )
            .toList(),
      ),
      BlockType.image => ImageBlockData(
        mediaId: map['mediaId'] as String? ?? '',
        caption: map['caption'] as String?,
      ),
      BlockType.drawing => DrawingBlockData(
        mediaId: map['mediaId'] as String? ?? '',
      ),
      BlockType.voice => VoiceBlockData(
        mediaId: map['mediaId'] as String? ?? '',
        durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
        transcript: map['transcript'] as String? ?? '',
      ),
      BlockType.table => TableBlockData(
        rows: (map['rows'] as List? ?? const [])
            .map(
              (r) => (r as List).map((c) => c as String? ?? '').toList(),
            )
            .toList(),
      ),
      BlockType.bullet => BulletBlockData(
        (map['items'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
      ),
      BlockType.divider => const DividerBlockData(),
    };
  }
}

class TextBlockData extends BlockData {
  const TextBlockData(this.text);
  final String text;

  @override
  String get searchableText => text;

  @override
  Map<String, dynamic> toJson() => {'text': text};
}

class HeadingBlockData extends BlockData {
  const HeadingBlockData(this.text, {this.level = 1});
  final String text;
  final int level; // 1-3

  @override
  String get searchableText => text;

  @override
  Map<String, dynamic> toJson() => {'text': text, 'level': level};
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.text,
    this.done = false,
    this.priority = 0,
    this.dueAt,
  });

  final String id;
  final String text;
  final bool done;
  /// 优先级 0-3（0=普通）。
  final int priority;
  /// 截止时间（可选）。
  final DateTime? dueAt;

  ChecklistItem copyWith({
    String? text,
    bool? done,
    int? priority,
    DateTime? dueAt,
  }) =>
      ChecklistItem(
        id: id,
        text: text ?? this.text,
        done: done ?? this.done,
        priority: priority ?? this.priority,
        dueAt: dueAt ?? this.dueAt,
      );

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
    id: json['id'] as String? ?? '',
    text: json['text'] as String? ?? '',
    done: json['done'] as bool? ?? false,
    priority: (json['priority'] as num?)?.toInt() ?? 0,
    dueAt: json['dueAt'] == null
        ? null
        : DateTime.tryParse(json['dueAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'done': done,
    'priority': priority,
    if (dueAt != null) 'dueAt': dueAt!.toIso8601String(),
  };
}

class ChecklistBlockData extends BlockData {
  const ChecklistBlockData({this.title = '', this.items = const []});
  final String title;
  final List<ChecklistItem> items;

  @override
  String get searchableText =>
      [title, ...items.map((e) => e.text)].join(' ');

  @override
  Map<String, dynamic> toJson() => {
        'title': title,
        'items': items.map((e) => e.toJson()).toList(),
      };
}

class ImageBlockData extends BlockData {
  const ImageBlockData({required this.mediaId, this.caption});
  final String mediaId;
  final String? caption;

  @override
  String get searchableText => caption ?? '';

  @override
  Map<String, dynamic> toJson() => {
        'mediaId': mediaId,
        if (caption != null) 'caption': caption,
      };
}

class DrawingBlockData extends BlockData {
  const DrawingBlockData({required this.mediaId});
  final String mediaId;

  @override
  Map<String, dynamic> toJson() => {'mediaId': mediaId};
}

class VoiceBlockData extends BlockData {
  const VoiceBlockData({
    required this.mediaId,
    this.durationMs = 0,
    this.transcript = '',
  });
  final String mediaId;
  final int durationMs;
  final String transcript;

  @override
  String get searchableText => transcript;

  @override
  Map<String, dynamic> toJson() => {
        'mediaId': mediaId,
        'durationMs': durationMs,
        'transcript': transcript,
      };
}

class TableBlockData extends BlockData {
  const TableBlockData({this.rows = const []});
  final List<List<String>> rows;

  @override
  String get searchableText => rows.expand((r) => r).join(' ');

  @override
  Map<String, dynamic> toJson() => {'rows': rows};
}

class BulletBlockData extends BlockData {
  const BulletBlockData(this.items);
  final List<String> items;

  @override
  String get searchableText => items.join(' ');

  @override
  Map<String, dynamic> toJson() => {'items': items};
}

class DividerBlockData extends BlockData {
  const DividerBlockData();

  @override
  Map<String, dynamic> toJson() => const {};
}

/// 待办视图聚合条目：一篇笔记里某个清单块中的一项。
class TodoEntry {
  const TodoEntry({
    required this.noteId,
    required this.noteTitle,
    required this.blockId,
    required this.item,
  });

  final String noteId;
  final String noteTitle;
  final String blockId;
  final ChecklistItem item;
}
