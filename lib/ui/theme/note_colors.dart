import 'package:flutter/material.dart';

/// 颜色标记 -> 实际色值（浅色卡片底）。
/// 名称对应 [NoteColor] 枚举的 `.name`。
Color? noteColorOf(String? name) {
  return switch (name) {
    'yellow' => const Color(0xFFFEF3C7),
    'green' => const Color(0xFFDCFCE7),
    'blue' => const Color(0xFFDBEAFE),
    'pink' => const Color(0xFFFCE7F3),
    'purple' => const Color(0xFFF3E8FF),
    'orange' => const Color(0xFFFFEDD5),
    'teal' => const Color(0xFFCCFBF1),
    _ => null,
  };
}
