import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/database/database.dart';
import '../domain/block_data.dart';
import '../domain/enums.dart';
import '../utils/date_format.dart';

/// 数据导出：全部笔记 → TXT / Markdown / PDF。
class NoteExporter {
  NoteExporter(this._db);
  final AppDatabase _db;
  Map<String, String?> _mediaPaths = {};

  /// 导出全部活动笔记为 Markdown，返回文件路径。
  Future<String> exportMarkdown() => _export(format: _Format.markdown);

  /// 导出全部活动笔记为纯文本，返回文件路径。
  Future<String> exportText() => _export(format: _Format.text);

  /// 导出全部活动笔记为 PDF，返回文件路径。
  /// 中文渲染依赖运行时加载系统 CJK 字体（Android 自带 Noto Sans CJK）。
  Future<String> exportPdf() async {
    final notes = await (_db.select(_db.notes)
          ..where((n) => n.trashTime.isNull() & n.deletedAt.isNull()))
        .get();
    final blocks = await _db.select(_db.blocks).get();

    // 加载系统 CJK 字体（缺省时降级 Helvetica，中文可能显示为方块）
    pw.Font? cjk;
    const candidates = [
      '/system/fonts/NotoSansCJK-Regular.ttc',
      '/system/fonts/DroidSansFallback.ttf',
    ];
    for (final c in candidates) {
      final f = File(c);
      if (await f.exists()) {
        try {
          cjk = pw.Font.ttf(ByteData.sublistView(await f.readAsBytes()));
          break;
        } catch (_) {}
      }
    }

    final media = await _db.select(_db.mediaItems).get();
    _mediaPaths = {for (final m in media) m.id: m.localPath};

    final doc = pw.Document();
    final theme = pw.ThemeData.withFont(
      base: cjk ?? pw.Font.helvetica(),
    );

    for (final n in notes) {
      final noteBlocks = blocks
          .where((b) => b.noteId == n.id)
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      doc.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          header: (ctx) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text(
              '${n.title.trim().isEmpty ? '无标题' : n.title.trim()}'
              ' · ${formatFullDate(n.createdAt)}',
              style: pw.TextStyle(fontSize: 13, color: PdfColors.grey600),
            ),
          ),
          build: (ctx) => [
            for (final b in noteBlocks) _pdfBlock(b),
          ],
        ),
      );
    }

    final bytes = await doc.save();
    final dir = Directory(p.join(
        (await getApplicationDocumentsDirectory()).path, 'exports'));
    await dir.create(recursive: true);
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final file = File(p.join(dir.path, 'suiji_export_$stamp.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 块 → PDF 组件。
  pw.Widget _pdfBlock(Block b) {
    final data = BlockData.fromJson(blockTypeOf(b.type), b.data);
    return switch (data) {
      HeadingBlockData(:final text, :final level) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
          child: pw.Text(
            text.isEmpty ? ' ' : text,
            style: pw.TextStyle(
              fontSize: level == 1 ? 20 : level == 2 ? 17 : 15,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      TextBlockData(:final text) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(text.isEmpty ? ' ' : text, style: pw.TextStyle(fontSize: 12)),
        ),
      ChecklistBlockData(:final items) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final it in items)
                pw.Text(
                  '${it.done ? '☑' : '☐'} ${it.text}',
                  style: pw.TextStyle(fontSize: 12),
                ),
            ],
          ),
        ),
      BulletBlockData(:final items) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final it in items)
                pw.Text('•  $it', style: pw.TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ImageBlockData(:final mediaId) => _pdfImage(mediaId),
      DrawingBlockData(:final mediaId) => _pdfImage(mediaId),
      VoiceBlockData(:final transcript) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(
            transcript.isEmpty ? '🎤 语音笔记' : '🎤 $transcript',
            style: pw.TextStyle(fontSize: 12),
          ),
        ),
      TableBlockData(:final rows) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            children: [
              for (final r in rows)
                pw.TableRow(
                  children: [
                    for (final c in r)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(c, style: pw.TextStyle(fontSize: 10)),
                      ),
                  ],
                ),
            ],
          ),
        ),
      DividerBlockData() => pw.Divider(color: PdfColors.grey400),
    };
  }

  pw.Widget _pdfImage(String mediaId) {
    final path = _mediaPaths[mediaId];
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      try {
        return pw.Image(
          pw.MemoryImage(File(path).readAsBytesSync()),
          fit: pw.BoxFit.contain,
          width: 300,
        );
      } catch (_) {}
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text('[图片]',
          style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600)),
    );
  }

  Future<String> _export({required _Format format}) async {
    final notes = await (_db.select(_db.notes)
          ..where((n) => n.trashTime.isNull() & n.deletedAt.isNull()))
        .get();
    final blocks = await _db.select(_db.blocks).get();

    final buffer = StringBuffer();
    final notesByDate = <String, List<Note>>{};
    for (final n in notes) {
      final day = '${n.updatedAt.year}-${n.updatedAt.month.toString().padLeft(2, '0')}-${n.updatedAt.day.toString().padLeft(2, '0')}';
      notesByDate.putIfAbsent(day, () => []).add(n);
    }

    final days = notesByDate.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final day in days) {
      buffer.writeln(_header('📅 $day', format));
      for (final n in notesByDate[day]!) {
        buffer.writeln();
        final title = n.title.trim().isEmpty ? '无标题' : n.title.trim();
        buffer.writeln(_header('${_bullet(title, format)}${_pinnedTag(n)}', format));
        final noteBlocks = blocks
            .where((b) => b.noteId == n.id)
            .toList()
          ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
        for (final b in noteBlocks) {
          final line = _renderBlock(
              BlockData.fromJson(blockTypeOf(b.type), b.data), format);
          if (line.isNotEmpty) buffer.writeln(line);
        }
      }
      buffer.writeln();
    }

    final dir = Directory(p.join(
        (await getApplicationDocumentsDirectory()).path, 'exports'));
    await dir.create(recursive: true);
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final ext = format == _Format.markdown ? 'md' : 'txt';
    final file = File(p.join(dir.path, 'suiji_export_$stamp.$ext'));
    await file.writeAsString(buffer.toString(), flush: true);
    return file.path;
  }

  String _renderBlock(BlockData data, _Format format) {
    return switch (data) {
      HeadingBlockData(:final text, :final level) =>
        format == _Format.markdown
            ? '${'#' * level} $text'
            : '[${'#' * level}] $text',
      TextBlockData(:final text) => text,
      ChecklistBlockData(:final items) => items
          .map((e) => '${_bullet('', format)}${e.done ? '[x]' : '[ ]'} ${e.text}')
          .join('\n'),
      BulletBlockData(:final items) =>
        items.map((e) => '${_bullet('', format)} $e').join('\n'),
      VoiceBlockData(:final transcript) =>
        transcript.isEmpty ? '🎤 语音' : '🎤 $transcript',
      ImageBlockData(:final caption) => '🖼 ${caption ?? '图片'}',
      DrawingBlockData() => '✏️ 手绘',
      TableBlockData(:final rows) => rows
          .map((r) => '| ${r.join(' | ')} |')
          .join('\n'),
      DividerBlockData() => '---',
    };
  }

  String _header(String text, _Format format) =>
      format == _Format.markdown ? '## $text' : text;

  String _bullet(String s, _Format format) =>
      format == _Format.markdown ? '- $s'.trimRight() : '• $s'.trimRight();

  String _pinnedTag(Note n) => n.pinned ? ' 📌' : '';
}

enum _Format { markdown, text }
