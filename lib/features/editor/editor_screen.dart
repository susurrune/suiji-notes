import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/core.dart';
import '../../core/data/media/media_storage.dart';
import '../../core/state/providers.dart';
import '../../core/data/media/ocr_service.dart';
import '../../core/notifications/reminder_service.dart';
import '../../ui/theme/note_colors.dart';
import 'block_widgets.dart';
import 'drawing_canvas.dart';
import 'voice_capture.dart';

/// 编辑器内的一块（稳定 id 用于保 Key 与光标稳定）。
class _EditableBlock {
  _EditableBlock({required this.id, required this.draft});
  final String id;
  BlockDraft draft;
}

/// 块级块编辑器：文本 / 标题 / 清单 / 图片 / 分隔线，输入即存。
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, this.noteId, this.initialFolderId});
  final String? noteId;
  final String? initialFolderId;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  late String? _noteId = widget.noteId;
  /// 本次会话是否为「新建」笔记（区别于打开已有笔记）。
  late final bool _isNewNote = widget.noteId == null;
  final List<_EditableBlock> _blocks = [];
  bool _loaded = false;
  bool _dirty = false;
  bool _noteCreated = false;
  Timer? _saveTimer;
  DateTime? _savedAt;

  // 笔记元数据（新建时默认值，加载时填充）
  bool _pinned = false;
  int _important = 0;
  String? _color;
  String? _folderId;
  Set<String> _tagIds = {};
  DateTime? _createdAt;
  DateTime? _reminderAt;
  bool _encrypted = false;
  bool _locked = false;
  String _lockError = '';

  // 块级撤销栈（快照，最多 30 步）
  final List<List<_EditableBlock>> _undoStack = [];

  /// 结构变更前的撤销快照（文本键入不入栈，避免噪音）。
  void _pushUndo() {
    if (_undoStack.length >= 30) _undoStack.removeAt(0);
    _undoStack.add([
      for (final b in _blocks) _EditableBlock(id: b.id, draft: b.draft),
    ]);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _blocks
        ..clear()
        ..addAll(_undoStack.removeLast());
    });
    _onChanged();
  }

  // 媒体 id -> 本地路径（图片块渲染用）
  final Map<String, String> _mediaPaths = {};
  // 正在 OCR 的块下标
  final Set<int> _ocrBusy = {};

  NoteRepository get _notes => ref.read(noteRepositoryProvider);
  MediaRepository get _media => ref.read(mediaRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final id = _noteId;
    if (id != null) {
      final n = await _notes.getNote(id);
      if (!mounted) return;
      if (n != null) {
        final tags = await ref.read(tagRepositoryProvider).tagsForNote(id);
        if (!mounted) return;
        setState(() {
          _noteCreated = true; // 已有笔记，保存走 saveNoteContent，勿重复创建
          _pinned = n.note.pinned;
          _important = n.note.important;
          _color = n.note.color;
          _folderId = n.note.folderId;
          _createdAt = n.note.createdAt;
          _reminderAt = n.note.reminderAt;
          _encrypted = n.note.encrypted;
          // 加密笔记未解锁时不加载内容，显示锁定界面
          _locked = n.note.encrypted && !_notes.canDecryptEncrypted();
          _tagIds = tags.map((t) => t.id).toSet();
          if (_locked) {
            _loaded = true;
            return;
          }
          for (final b in n.blocks) {
            _blocks.add(
              _EditableBlock(
                id: b.id,
                draft: BlockDraft(
                  blockTypeOf(b.type),
                  BlockData.fromJson(blockTypeOf(b.type), b.data),
                  source: blockSourceOf(b.source),
                ),
              ),
            );
          }
          for (final m in n.media) {
            _mediaPaths[m.id] = m.localPath ?? '';
          }
          _loaded = true;
        });
      }
    } else {
      setState(() {
        _blocks.add(_EditableBlock(
          id: const Uuid().v4(),
          draft: const BlockDraft(BlockType.text, TextBlockData('')),
        ));
        _loaded = true;
      });
    }
  }

  // ───────────────────────── 保存（输入即存） ─────────────────────────

  void _onChanged() {
    setState(() => _dirty = true);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveNow);
  }

  /// 确保笔记行已创建（新建笔记的首存走 createNote，后续走 saveNoteContent）。
  Future<String> _ensureCreated() async {
    final id = _noteId ?? const Uuid().v4();
    _noteId = id;
    if (!_noteCreated) {
      await _notes.createNote(
        id,
        folderId: widget.initialFolderId,
        color: _color,
        pinned: _pinned,
        important: _important,
        blocks: [for (final b in _blocks) b.draft],
      );
      _noteCreated = true;
      _createdAt ??= DateTime.now();
      _dirty = false;
    }
    return id;
  }

  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    if (!_dirty) return;
    final id = await _ensureCreated();
    await _notes.saveNoteContent(id, [for (final b in _blocks) b.draft]);
    if (!mounted) return;
    setState(() {
      _dirty = false;
      _savedAt = DateTime.now();
    });
  }

  /// 退出时的收尾：本次新建且内容为空 → 直接丢弃（不留空笔记）；
  /// 否则按需保存。
  Future<void> _flushAndMaybePop(bool didPop) async {
    if (_isNewNote && _noteCreated && _isNoteEmpty()) {
      await _notes.deletePermanently(_noteId!);
      _dirty = false;
    } else if (_dirty) {
      await _saveNow();
    }
    if (didPop) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// 是否没有任何有效内容（用于空笔记自动删除）。
  bool _isNoteEmpty() {
    for (final b in _blocks) {
      final hasText = switch (b.draft.data) {
        TextBlockData(:final text) => text.trim().isNotEmpty,
        HeadingBlockData(:final text) => text.trim().isNotEmpty,
        ChecklistBlockData(:final items) =>
          items.any((i) => i.text.trim().isNotEmpty),
        BulletBlockData(:final items) =>
          items.any((i) => i.trim().isNotEmpty),
        ImageBlockData() => true,
        DrawingBlockData() => true,
        VoiceBlockData(:final transcript) => transcript.trim().isNotEmpty,
        _ => false,
      };
      if (hasText) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  // ───────────────────────── 块操作 ─────────────────────────

  void _addBlock(BlockType type, [BlockData? data]) {
    _pushUndo();
    final blank = switch (type) {
      BlockType.text => const TextBlockData(''),
      BlockType.heading => const HeadingBlockData(''),
      BlockType.checklist => const ChecklistBlockData(),
      BlockType.bullet => const BulletBlockData(['']),
      BlockType.table =>
        const TableBlockData(rows: [['', ''], ['', '']]),
      BlockType.divider => const DividerBlockData(),
      _ => null,
    };
    if (blank == null && type != BlockType.image) return;

    setState(() {
      _blocks.add(_EditableBlock(
        id: const Uuid().v4(),
        draft: BlockDraft(
          type,
          data ?? blank ?? const TextBlockData(''),
        ),
      ));
    });
    _onChanged();
  }

  Future<void> _addImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final savedPath = await MediaStorage.persist(File(picked.path));
    // 图片块需要笔记已存在（MediaItem 依赖 noteId）
    final id = await _ensureCreated();
    await _notes.saveNoteContent(id, [for (final b in _blocks) b.draft]);

    final mediaId = const Uuid().v4();
    await _media.createMedia(
      noteId: id,
      localPath: savedPath,
      mime: 'image/*',
    );
    _pushUndo();
    setState(() {
      _mediaPaths[mediaId] = savedPath;
      _blocks.add(_EditableBlock(
        id: const Uuid().v4(),
        draft: BlockDraft(BlockType.image, ImageBlockData(mediaId: mediaId)),
      ));
    });
    _onChanged();
  }

  /// 语音笔记：录音 + ASR 转写 → 插入语音块（转写文本可搜索）。
  Future<void> _addVoice() async {
    final result = await showVoiceCapture(context);
    if (result == null || !mounted) return;

    final id = await _ensureCreated();
    await _notes.saveNoteContent(id, [for (final b in _blocks) b.draft]);
    var mediaId = '';
    if (result.audioPath.isNotEmpty) {
      mediaId = const Uuid().v4();
      await _media.createMedia(
        noteId: id,
        localPath: result.audioPath,
        mime: 'audio/mp4',
      );
    }
    _pushUndo();
    setState(() {
      if (mediaId.isNotEmpty) _mediaPaths[mediaId] = result.audioPath;
      _blocks.add(_EditableBlock(
        id: const Uuid().v4(),
        draft: BlockDraft(
          BlockType.voice,
          VoiceBlockData(
            mediaId: mediaId,
            durationMs: result.durationMs,
            transcript: result.transcript,
          ),
          source: BlockSource.voiceAsr,
        ),
      ));
    });
    _onChanged();
  }

  /// OCR：识别图片块文字，在其后插入 source=imageOcr 文本块。
  Future<void> _ocrImage(int index) async {
    final b = _blocks[index];
    final image = b.draft.data as ImageBlockData;
    final path = _mediaPaths[image.mediaId];
    if (path == null || path.isEmpty) return;
    if (_ocrBusy.contains(index)) return;

    setState(() => _ocrBusy.add(index));
    final text = await OcrService.recognize(path);
    if (!mounted) return;
    setState(() => _ocrBusy.remove(index));
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('未识别到文字')));
      return;
    }
    _pushUndo();
    setState(() {
      _blocks.insert(
        index + 1,
        _EditableBlock(
          id: const Uuid().v4(),
          draft: BlockDraft(
            BlockType.text,
            TextBlockData(text),
            source: BlockSource.imageOcr,
          ),
        ),
      );
    });
    _onChanged();
  }

  /// 手绘：全屏画布 → PNG 持久化 → 插入手绘块。
  Future<void> _addDrawing() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const DrawingScreen()),
    );
    if (path == null || !mounted) return;

    final id = await _ensureCreated();
    await _notes.saveNoteContent(id, [for (final b in _blocks) b.draft]);
    final mediaId = const Uuid().v4();
    await _media.createMedia(noteId: id, localPath: path, mime: 'image/png');
    _pushUndo();
    setState(() {
      _mediaPaths[mediaId] = path;
      _blocks.add(_EditableBlock(
        id: const Uuid().v4(),
        draft: BlockDraft(BlockType.drawing, DrawingBlockData(mediaId: mediaId)),
      ));
    });
    _onChanged();
  }

  void _deleteBlock(int index) {
    _pushUndo();
    setState(() => _blocks.removeAt(index));
    _onChanged();
  }

  void _moveBlock(int index, int delta) {
    final to = index + delta;
    if (to < 0 || to >= _blocks.length) return;
    _pushUndo();
    setState(() {
      final b = _blocks.removeAt(index);
      _blocks.insert(to, b);
    });
    _onChanged();
  }

  void _onBlockLongPress(int index) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('上移'),
              enabled: index > 0,
              onTap: () {
                Navigator.pop(ctx);
                _moveBlock(index, -1);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward),
              title: const Text('下移'),
              enabled: index < _blocks.length - 1,
              onTap: () {
                Navigator.pop(ctx);
                _moveBlock(index, 1);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              title: Text('删除此块', style: TextStyle(color: theme.colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteBlock(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── 属性（颜色/重要度/删除） ─────────────────────────

  void _showMetaSheet() {
    final noteId = _noteId;
    if (noteId == null) return;
    final notes = _notes;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Consumer(
          builder: (context, ref, _) {
            final theme = Theme.of(context);
            final folders = ref.watch(foldersListProvider).value ?? const <Folder>[];
            final tags = ref.watch(tagsListProvider).value ?? const <Tag>[];
            final tagRepo = ref.read(tagRepositoryProvider);
            return SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 文件夹
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text('文件夹', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DropdownButtonFormField<String?>(
                      initialValue: _folderId,
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('（收件箱）')),
                        for (final f in folders)
                          DropdownMenuItem<String?>(value: f.id, child: Text(f.name)),
                      ],
                      onChanged: (v) {
                        notes.moveToFolder(noteId, v);
                        setState(() => _folderId = v);
                      },
                    ),
                  ),
                  // 标签
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('标签', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final t in tags)
                          FilterChip(
                            avatar: _tagIcon(t),
                            label: Text(t.name),
                            selected: _tagIds.contains(t.id),
                            onSelected: (on) async {
                              final next = {..._tagIds};
                              on ? next.add(t.id) : next.remove(t.id);
                              setState(() => _tagIds = next);
                              await tagRepo.setTagsForNote(noteId, next.toList());
                            },
                          ),
                        if (tags.isEmpty)
                          Text('还没有标签，去标签管理页创建',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
                      ],
                    ),
                  ),
                  const Divider(height: 28),
                  // 提醒
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: const Icon(Icons.alarm_outlined),
                    title: Text(
                      _reminderAt == null
                          ? '设置提醒'
                          : '提醒于 ${_fmtReminder(_reminderAt!)}',
                    ),
                    subtitle: const Text('到时通知你'),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        if (_reminderAt != null)
                          IconButton(
                            tooltip: '清除提醒',
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () async {
                              await notes.setReminder(noteId, null);
                              await ReminderService.cancel(noteId);
                              setState(() => _reminderAt = null);
                            },
                          ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () => _pickReminder(context, noteId, notes),
                  ),
                  const Divider(height: 28),
                  // 颜色
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('颜色标记', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Wrap(
                      spacing: 10,
                      children: [
                        for (final c in NoteColor.values)
                          _ColorDot(
                            color: noteColorOf(c.name),
                            selected: _color == c.name,
                            onTap: () {
                              final v = c == NoteColor.none ? null : c.name;
                              notes.setColor(noteId, v);
                              setState(() => _color = v);
                            },
                          ),
                      ],
                    ),
                  ),
                  // 重要度
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        const Icon(Icons.flag_outlined, size: 20),
                        const SizedBox(width: 8),
                        const Text('重要程度'),
                        const Spacer(),
                        SegmentedButton<int>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                              visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(value: 0, label: Text('普通')),
                            ButtonSegment(value: 1, label: Text('低')),
                            ButtonSegment(value: 2, label: Text('中')),
                            ButtonSegment(value: 3, label: Text('高')),
                          ],
                          selected: {_important},
                          onSelectionChanged: (s) {
                            final v = s.first;
                            notes.setImportance(noteId, v);
                            setState(() => _important = v);
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 28),
                  // 加密 / 取消加密
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      _encrypted ? Icons.lock_open_outlined : Icons.lock_outline,
                      color: _encrypted
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(_encrypted ? '取消加密' : '加密笔记'),
                    subtitle: Text(_encrypted
                        ? '内容将恢复为明文保存'
                        : '设置密码，笔记内容加密存储'),
                    onTap: () async {
                      if (_encrypted) {
                        await notes.setEncrypted(noteId, false);
                        await notes.saveNoteContent(
                            noteId, [for (final b in _blocks) b.draft]);
                        setState(() => _encrypted = false);
                      } else {
                        final pw = await _askPassword(ctx);
                        if (pw == null || pw.isEmpty) return;
                        await ref.read(secretServiceProvider).setup(pw);
                        await notes.setEncrypted(noteId, true);
                        await notes.saveNoteContent(
                            noteId, [for (final b in _blocks) b.draft]);
                        setState(() => _encrypted = true);
                      }
                    },
                  ),
                  const Divider(height: 28),
                  ListTile(
                    leading: Icon(Icons.delete_outline,
                        color: Theme.of(ctx).colorScheme.error),
                    title: Text('删除笔记',
                        style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ReminderService.cancel(noteId);
                      await notes.trashNote(noteId);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 设置加密密码（两次输入校验一致）。
  Future<String?> _askPassword(BuildContext ctx) {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    String? error;
    return showDialog<String>(
      context: ctx,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setSheet) => AlertDialog(
          title: const Text('设置加密密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: c1,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '输入密码（至少 4 位）',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: c2,
                obscureText: true,
                decoration: const InputDecoration(hintText: '再次输入密码'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (c1.text.length < 4) {
                  setSheet(() => error = '密码至少 4 位');
                  return;
                }
                if (c1.text != c2.text) {
                  setSheet(() => error = '两次输入的密码不一致');
                  return;
                }
                Navigator.pop(dctx, c1.text);
              },
              child: const Text('加密'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickReminder(
      BuildContext ctx, String noteId, NoteRepository notes) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: ctx,
      initialDate: _reminderAt ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !ctx.mounted) return;
    final time = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay.fromDateTime(_reminderAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;

    final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await notes.setReminder(noteId, at);
    await ReminderService.schedule(
      noteId: noteId,
      title: _blocks.isEmpty ? '笔记' : deriveTitle([for (final b in _blocks) b.draft]),
      at: at,
    );
    if (mounted) setState(() => _reminderAt = at);
  }

  String _fmtReminder(DateTime t) {
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return '${sameDay ? '' : '${t.month}月${t.day}日 '}'
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Widget _tagIcon(Tag t) {
    return switch (t.kind) {
      'numeric' => const Icon(Icons.tag, size: 16),
      'shape' => const Icon(Icons.square_outlined, size: 16),
      _ => const Icon(Icons.abc, size: 16),
    };
  }

  // ───────────────────────── 构建 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) await _flushAndMaybePop(true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_appBarTitle()),
          titleTextStyle: theme.textTheme.titleMedium,
          actions: [
            IconButton(
              tooltip: '撤销',
              icon: const Icon(Icons.undo),
              onPressed: _undoStack.isEmpty ? null : _undo,
            ),
            IconButton(
              tooltip: '置顶',
              icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () {
                final v = !_pinned;
                if (_noteId != null) _notes.setPinned(_noteId!, v);
                setState(() => _pinned = v);
              },
            ),
            IconButton(
              tooltip: '更多',
              icon: const Icon(Icons.more_vert),
              onPressed: _noteId == null ? null : _showMetaSheet,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(28),
            child: _savedAt == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '已保存 ${_savedAt!.hour.toString().padLeft(2, '0')}:${_savedAt!.minute.toString().padLeft(2, '0')}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
          ),
        ),
        body: _locked
            ? _buildLockView()
            : _loaded
                ? Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                          itemCount: _blocks.length,
                          itemBuilder: (context, i) => _buildBlock(i),
                        ),
                      ),
                      _buildAddBar(),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  /// 加密笔记锁定界面：输入密码解锁。
  Widget _buildLockView() {
    final theme = Theme.of(context);
    final ctrl = TextEditingController();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              ),
              child: Icon(Icons.lock_outline,
                  size: 40, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text('笔记已加密', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('输入密码解锁后才能查看',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 20),
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '密码',
                errorText: _lockError.isEmpty ? null : _lockError,
              ),
              onSubmitted: (_) => _unlock(ctrl.text),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _unlock(ctrl.text),
                icon: const Icon(Icons.lock_open_outlined, size: 18),
                label: const Text('解锁'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _unlock(String password) async {
    if (password.isEmpty) {
      setState(() => _lockError = '请输入密码');
      return;
    }
    final ok = await ref.read(secretServiceProvider).unlock(password);
    if (!mounted) return;
    if (!ok) {
      setState(() => _lockError = '密码错误');
      return;
    }
    setState(() {
      _locked = false;
      _lockError = '';
    });
    await _init();
  }

  Widget _buildBlock(int index) {
    final b = _blocks[index];
    final d = b.draft;
    final key = ValueKey(b.id);
    switch (d.type) {
      case BlockType.text:
        return GestureDetector(
          key: key,
          onLongPress: () => _onBlockLongPress(index),
          child: TextBlockEdit(
            initial: d.data as TextBlockData,
            autofocus: index == 0 && _noteId == null,
            onChanged: (t) {
              b.draft = BlockDraft(BlockType.text, TextBlockData(t));
              _onChanged();
            },
          ),
        );
      case BlockType.heading:
        return GestureDetector(
          key: key,
          onLongPress: () => _onBlockLongPress(index),
          child: HeadingBlockEdit(
            initial: d.data as HeadingBlockData,
            onChanged: (t) {
              final h = d.data as HeadingBlockData;
              b.draft = BlockDraft(
                  BlockType.heading, HeadingBlockData(t, level: h.level));
              _onChanged();
            },
          ),
        );
      case BlockType.checklist:
        return GestureDetector(
          key: key,
          onLongPress: () => _onBlockLongPress(index),
          child: ChecklistBlockEdit(
            initial: d.data as ChecklistBlockData,
            onChanged: (c) {
              b.draft = BlockDraft(BlockType.checklist, c);
              _onChanged();
            },
          ),
        );
      case BlockType.image:
        final image = d.data as ImageBlockData;
        return Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ImageBlockEdit(
            localPath: _mediaPaths[image.mediaId] ?? '',
            onDelete: () => _deleteBlock(index),
            onOcr: () => _ocrImage(index),
            ocrBusy: _ocrBusy.contains(index),
          ),
        );
      case BlockType.drawing:
        final drawing = d.data as DrawingBlockData;
        return Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: ImageBlockEdit(
            localPath: _mediaPaths[drawing.mediaId] ?? '',
            onDelete: () => _deleteBlock(index),
          ),
        );
      case BlockType.bullet:
        return GestureDetector(
          key: key,
          onLongPress: () => _onBlockLongPress(index),
          child: BulletBlockEdit(
            initial: d.data as BulletBlockData,
            onChanged: (bl) {
              b.draft = BlockDraft(BlockType.bullet, bl);
              _onChanged();
            },
          ),
        );
      case BlockType.table:
        return GestureDetector(
          key: key,
          onLongPress: () => _onBlockLongPress(index),
          child: TableBlockEdit(
            initial: d.data as TableBlockData,
            onChanged: (t) {
              b.draft = BlockDraft(BlockType.table, t);
              _onChanged();
            },
          ),
        );
      case BlockType.voice:
        final voice = d.data as VoiceBlockData;
        final theme = Theme.of(context);
        return Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.mic, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    voice.transcript.isEmpty ? '（无转写文本）' : voice.transcript,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (voice.durationMs > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${(voice.durationMs / 1000).round()}s',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _deleteBlock(index),
                ),
              ],
            ),
          ),
        );
      case BlockType.divider:
        return GestureDetector(
          key: key,
          onLongPress: () => _onBlockLongPress(index),
          child: const DividerBlockEdit(),
        );
    }
  }

  Widget _buildAddBar() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              _AddChip(
                icon: Icons.title,
                label: '文本',
                onTap: () => _addBlock(BlockType.text),
              ),
              _AddChip(
                icon: Icons.checklist,
                label: '清单',
                onTap: () => _addBlock(BlockType.checklist),
              ),
              _AddChip(
                icon: Icons.image_outlined,
                label: '图片',
                onTap: _addImage,
              ),
              _AddChip(
                icon: Icons.format_list_bulleted,
                label: '项目',
                onTap: () => _addBlock(BlockType.bullet),
              ),
              _AddChip(
                icon: Icons.grid_on,
                label: '表格',
                onTap: () => _addBlock(BlockType.table),
              ),
              _AddChip(
                icon: Icons.gesture,
                label: '手绘',
                onTap: _addDrawing,
              ),
              _AddChip(
                icon: Icons.mic_none,
                label: '语音',
                onTap: _addVoice,
              ),
              _AddChip(
                icon: Icons.horizontal_rule,
                label: '分隔线',
                onTap: () => _addBlock(BlockType.divider),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _appBarTitle() {
    // 显示创建时间（年月日），便于确定笔记何时创建
    return formatFullDate(_createdAt ?? DateTime.now());
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color ?? theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 16)
            : null,
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 4),
                Text(label, style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
