import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/core/core.dart';

/// 数据层集成测试：验证统一笔记模型 + FTS5 全文检索 + 文件夹/标签 + 回收站。
void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late FolderRepository folders;
  late TagRepository tags;
  late SearchRepository search;
  late ProfileRepository profile;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    notes = NoteRepository(db);
    folders = FolderRepository(db);
    tags = TagRepository(db);
    search = SearchRepository(db);
    profile = ProfileRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('创建笔记并检索：标题、正文、OCR/ASR 来源文本均可命中', () async {
    final n = await notes.createNote(
      'note-1',
      blocks: const [
        BlockDraft(BlockType.text, TextBlockData('今天要买牛奶和面包')),
        BlockDraft(
          BlockType.checklist,
          ChecklistBlockData(items: [ChecklistItem(id: 'c1', text: '写周报')]),
        ),
      ],
    );
    // 标题派生自首个文本块
    expect(n.note.title, contains('今天要买牛奶'));

    // 正文命中
    var hits = await search.searchNotes(query: '牛奶');
    expect(hits.map((e) => e.id), contains('note-1'));
    // 清单项命中
    hits = await search.searchNotes(query: '周报');
    expect(hits.map((e) => e.id), contains('note-1'));
    // 无关查询不命中
    hits = await search.searchNotes(query: '不存在的内容');
    expect(hits, isEmpty);

    // 保存后内容更新：语音转写文本（source=ASR）可被检索
    await notes.saveNoteContent('note-1', const [
      BlockDraft(BlockType.text, TextBlockData('会议纪要')),
      BlockDraft(
        BlockType.voice,
        VoiceBlockData(mediaId: 'm1', transcript: '语音转写内容'),
        source: BlockSource.voiceAsr,
      ),
    ]);
    hits = await search.searchNotes(query: '转写');
    expect(hits.map((e) => e.id), contains('note-1'));
  });

  test('文件夹 / 标签 / 颜色 / 置顶 / 重要度管理', () async {
    final f = await folders.createFolder('工作');
    final sub = await folders.createFolder('项目A', parentId: f.id);
    final t = await tags.createTag('urgent', TagKind.alpha);

    await notes.createNote(
      'n1',
      folderId: sub.id,
      color: 'yellow',
      blocks: const [BlockDraft(BlockType.text, TextBlockData('alpha 内容'))],
    );
    await tags.setTagsForNote('n1', [t.id]);
    await notes.setPinned('n1', true);
    await notes.setImportance('n1', 2);

    // 标签查询
    expect((await tags.tagsForNote('n1')).map((e) => e.id), contains(t.id));
    expect((await search.searchNotes(tagId: t.id)).map((e) => e.id), contains('n1'));

    // 颜色筛选
    expect((await search.searchNotes(color: 'yellow')).map((e) => e.id), contains('n1'));

    // 文件夹删除：子文件夹上移到根，被删文件夹直属的笔记移回收件箱；
    // 子文件夹里的笔记保留原归属（n1 在 项目A，不受影响）。
    await folders.deleteFolder(f.id);
    final moved = await notes.getNote('n1');
    expect(moved!.note.folderId, sub.id);
    final subAfter = await folders.getFolder(sub.id);
    expect(subAfter!.parentId, isNull);
    final foldersAfter = await folders.watchAll().first;
    expect(foldersAfter.map((e) => e.name), contains('项目A'));
  });

  test('回收站：软删除 → 列表移除 → 恢复', () async {
    await notes.createNote('n2',
        blocks: const [BlockDraft(BlockType.text, TextBlockData('hi'))]);

    await notes.trashNote('n2');
    var trash = await notes.watchTrash().first;
    expect(trash.map((e) => e.id), contains('n2'));
    // 正常列表不出现
    var active = await notes.watchNotes().first;
    expect(active.map((e) => e.id), isNot(contains('n2')));

    await notes.restoreNote('n2');
    trash = await notes.watchTrash().first;
    expect(trash.map((e) => e.id), isNot(contains('n2')));
    active = await notes.watchNotes().first;
    expect(active.map((e) => e.id), contains('n2'));
  });

  test('加密笔记：密文存储、不入检索、密码解锁后可读', () async {
    final secrets = SecretService(db);
    await secrets.setup('mypassword');
    final noteRepo = NoteRepository(db, secrets);

    await noteRepo.createNote(
      'secret',
      encrypted: true,
      blocks: const [BlockDraft(BlockType.text, TextBlockData('机密密码abc123'))],
    );

    // 不入明文检索
    final hits = await search.searchNotes(query: '机密');
    expect(hits, isEmpty);

    // 存储为密文（不含明文，带 enc:v1: 前缀）
    final raw = await db.select(db.blocks).get();
    expect(raw.single.data.startsWith('enc:v1:'), isTrue);
    expect(raw.single.data.contains('机密密码'), isFalse);

    // 锁定后读取：标题为空、块为密文（不透明文）
    secrets.lock();
    final locked = await noteRepo.getNote('secret');
    expect(locked!.note.title, isEmpty);
    expect(locked.blocks.single.data, isNot(contains('机密密码')));

    // 错误密码无法解锁
    expect(await secrets.unlock('wrong'), isFalse);
    // 正确密码解锁后可读明文
    expect(await secrets.unlock('mypassword'), isTrue);
    final opened = await noteRepo.getNote('secret');
    expect(opened!.blocks.single.data, contains('机密密码'));
    expect(opened.note.encrypted, isTrue);
  });

  test('待办聚合：跨笔记清单汇总 + 勾选更新', () async {
    await notes.createNote('t1', blocks: const [
      BlockDraft(
        BlockType.checklist,
        ChecklistBlockData(items: [
          ChecklistItem(id: 'a', text: '买牛奶'),
          ChecklistItem(id: 'b', text: '写报告'),
        ]),
      ),
    ]);
    await notes.createNote('t2', blocks: const [
      BlockDraft(
        BlockType.checklist,
        ChecklistBlockData(items: [ChecklistItem(id: 'c', text: '开会')]),
      ),
    ]);

    final todos = await notes.watchTodos().first;
    expect(todos.length, 3);

    final a = todos.firstWhere((t) => t.item.id == 'a');
    await notes.updateChecklistItem(
        a.noteId, a.blockId, a.item.copyWith(done: true, priority: 2));

    final todos2 = await notes.watchTodos().first;
    final updated = todos2.firstWhere((t) => t.item.id == 'a').item;
    expect(updated.done, isTrue);
    expect(updated.priority, 2);
  });

  test('个人资料：昵称与头像可保存读取', () async {
    // 初始为空
    expect(await profile.getProfile(), isNull);

    await profile.updateName('小明');
    var p = await profile.getProfile();
    expect(p!.name, '小明');
    expect(p.avatarPath, isNull);

    await profile.updateAvatar('/path/to/avatar.png');
    p = await profile.getProfile();
    expect(p!.avatarPath, '/path/to/avatar.png');
    // 更新昵称不覆盖头像
    await profile.updateName('小红');
    p = await profile.getProfile();
    expect(p!.name, '小红');
    expect(p.avatarPath, '/path/to/avatar.png');
  });
}
