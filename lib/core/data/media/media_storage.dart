import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 媒体文件持久化：把 image_picker 等产出的临时文件复制到应用私有目录，
/// 保证删除临时文件后笔记仍可展示。
class MediaStorage {
  MediaStorage._();

  /// 复制一份外部文件到应用媒体目录，返回目标绝对路径。
  static Future<String> persist(File source, {String? preferredName}) async {
    final dir = await _mediaDir();
    final name = preferredName?.isNotEmpty == true
        ? preferredName!
        : '${const Uuid().v4()}${p.extension(source.path)}';
    final dest = p.join(dir.path, name);
    await source.copy(dest);
    return dest;
  }

  /// 删除媒体文件（若仍在应用目录内）。
  static Future<void> deleteIfInternal(String path) async {
    if (path.isEmpty) return;
    final dir = await _mediaDir();
    final normalized = p.normalize(path);
    if (!normalized.startsWith(p.normalize(dir.path))) return;
    final f = File(normalized);
    if (await f.exists()) {
      await f.delete();
    }
  }

  static Future<Directory> _mediaDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'media'));
    await dir.create(recursive: true);
    return dir;
  }
}
