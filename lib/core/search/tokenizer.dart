/// 面向 FTS5 的中文分词。
///
/// SQLite FTS5 默认 tokenizer (unicode61) 会把连续 CJK 字符当作一个 token，
/// 无法实现中文子串匹配。解决方案：索引与查询都用同一分词器——
/// - CJK 单字之间插入空格（"快速检索" -> "快 速 检 索"），FTS5 对空格分隔的
///   单字 token 做隐式 AND 匹配，实现"按任意子串命中"。
/// - 拉丁字母/数字保留为完整单词（"flutter 3" -> "flutter 3"）。
library;

final _cjkPattern = RegExp(r'[㐀-䶿一-鿿豈-﫿]');
final _latinPattern = RegExp(r'[A-Za-z0-9_]+');

/// 把任意文本转成 FTS5 索引/查询用 token 串。
String tokenizeForSearch(String input) {
  if (input.isEmpty) return '';
  final buffer = StringBuffer();
  var i = 0;
  while (i < input.length) {
    final ch = input[i];
    if (_cjkPattern.hasMatch(ch)) {
      buffer
        ..write(ch)
        ..write(' ');
      i++;
    } else if (RegExp(r'[A-Za-z0-9]').hasMatch(ch)) {
      final match = _latinPattern.firstMatch(input.substring(i));
      final word = match!.group(0)!;
      buffer
        ..write(word)
        ..write(' ');
      i += word.length;
    } else {
      i++;
    }
  }
  return buffer.toString().trim();
}

/// 把用户查询转成 FTS5 MATCH 表达式。
/// 末位 token 加前缀通配符 `*`，实现"输入即搜"的增量命中。
String buildMatchQuery(String rawQuery) {
  final tokens = tokenizeForSearch(rawQuery).split(' ');
  if (tokens.isEmpty) return '';
  final parts = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (t.isEmpty) continue;
    if (i == tokens.length - 1) {
      parts.add('$t*');
    } else {
      parts.add(t);
    }
  }
  return parts.join(' ');
}
