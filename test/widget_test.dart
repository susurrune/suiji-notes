import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notes_app/core/core.dart';
import 'package:notes_app/ui/widgets/note_card.dart';

/// 纯组件测试（不触碰数据库，避免 drift 原生查询与 FakeAsync 的兼容问题）。
/// 应用整体的集成验证在 Android 模拟器上进行。
void main() {
  Note makeNote({String title = '', String preview = '', String? color}) => Note(
        id: '1',
        title: title,
        preview: preview,
        color: color,
        pinned: false,
        important: 0,
        encrypted: false,
        archived: false,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
      );

  testWidgets('NoteCard 渲染标题与预览', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteCard(
            note: makeNote(title: '会议纪要', preview: '讨论了 Q3 计划'),
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('会议纪要'), findsOneWidget);
    expect(find.text('讨论了 Q3 计划'), findsOneWidget);
  });

  testWidgets('NoteCard 空笔记显示占位', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NoteCard(note: makeNote(), onTap: () {})),
      ),
    );
    expect(find.text('空笔记'), findsOneWidget);
  });

  testWidgets('NoteCard 颜色标记作用于背景', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteCard(
            note: makeNote(title: '黄色笔记', color: 'yellow'),
            onTap: () {},
          ),
        ),
      ),
    );
    final card = tester.widget<Card>(find.byType(Card));
    expect(card.color, const Color(0xFFFEF3C7));
  });
}
