import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/core.dart';

/// 文本块编辑。
class TextBlockEdit extends StatefulWidget {
  const TextBlockEdit({
    super.key,
    required this.initial,
    required this.onChanged,
    this.autofocus = false,
    this.enabled = true,
  });
  final TextBlockData initial;
  final ValueChanged<String> onChanged;
  final bool autofocus;
  final bool enabled;

  @override
  State<TextBlockEdit> createState() => _TextBlockEditState();
}

class _TextBlockEditState extends State<TextBlockEdit> {
  late final TextEditingController _c = TextEditingController(text: widget.initial.text);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _c,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      minLines: 1,
      maxLines: null,
      style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
      decoration: const InputDecoration(
        border: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.symmetric(vertical: 6),
      ),
      onChanged: (v) {
        if (v != widget.initial.text) widget.onChanged(v);
      },
    );
  }
}

/// 标题块编辑（层级 1-3）。
class HeadingBlockEdit extends StatefulWidget {
  const HeadingBlockEdit({
    super.key,
    required this.initial,
    required this.onChanged,
    this.autofocus = false,
  });
  final HeadingBlockData initial;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  State<HeadingBlockEdit> createState() => _HeadingBlockEditState();
}

class _HeadingBlockEditState extends State<HeadingBlockEdit> {
  late final TextEditingController _c =
      TextEditingController(text: widget.initial.text);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = switch (widget.initial.level) {
      1 => theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      2 => theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      _ => theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    };
    return TextField(
      controller: _c,
      autofocus: widget.autofocus,
      minLines: 1,
      maxLines: null,
      style: style,
      decoration: const InputDecoration(
        border: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.symmetric(vertical: 6),
      ),
      onChanged: widget.onChanged,
    );
  }
}

/// 清单块编辑（勾选 + 多行待办，支持增删）。
class ChecklistBlockEdit extends StatefulWidget {
  const ChecklistBlockEdit({
    super.key,
    required this.initial,
    required this.onChanged,
  });
  final ChecklistBlockData initial;
  final ValueChanged<ChecklistBlockData> onChanged;

  @override
  State<ChecklistBlockEdit> createState() => _ChecklistBlockEditState();
}

class _ChecklistBlockEditState extends State<ChecklistBlockEdit> {
  late final List<TextEditingController> _controllers = [
    for (final item in widget.initial.items)
      TextEditingController(text: item.text),
  ];

  void _emit() {
    final items = <ChecklistItem>[];
    for (var i = 0; i < widget.initial.items.length; i++) {
      final base = widget.initial.items[i];
      items.add(
        base.copyWith(
          text: _controllers[i].text,
          done: base.done,
        ),
      );
    }
    widget.onChanged(ChecklistBlockData(items: items));
  }

  void _addItem() {
    setState(() {
      _controllers.add(TextEditingController());
      widget.onChanged(
        ChecklistBlockData(items: [
          ...widget.initial.items,
          ChecklistItem(id: const Uuid().v4(), text: ''),
        ]),
      );
    });
  }

  void _removeItem(int index) {
    setState(() {
      _controllers.removeAt(index).dispose();
      final items = [...widget.initial.items]..removeAt(index);
      widget.onChanged(ChecklistBlockData(items: items));
    });
  }

  void _toggle(int index, bool done) {
    final items = [...widget.initial.items];
    items[index] = items[index].copyWith(done: done);
    widget.onChanged(ChecklistBlockData(items: items));
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.initial.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                value: items[i].done,
                onChanged: (v) => _toggle(i, v ?? false),
                shape: const CircleBorder(),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: TextField(
                  controller: _controllers[i],
                  minLines: 1,
                  maxLines: null,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.4,
                    decoration: items[i].done
                        ? TextDecoration.lineThrough
                        : null,
                    color: items[i].done
                        ? theme.colorScheme.outline
                        : null,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  onChanged: (_) => _emit(),
                ),
              ),
              if (items.length > 1)
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _removeItem(i),
                ),
            ],
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 2),
          child: TextButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加清单项'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
      ],
    );
  }
}

/// 项目符号块编辑（多行文本列表，支持增删）。
class BulletBlockEdit extends StatefulWidget {
  const BulletBlockEdit({
    super.key,
    required this.initial,
    required this.onChanged,
  });
  final BulletBlockData initial;
  final ValueChanged<BulletBlockData> onChanged;

  @override
  State<BulletBlockEdit> createState() => _BulletBlockEditState();
}

class _BulletBlockEditState extends State<BulletBlockEdit> {
  late final List<TextEditingController> _controllers = [
    for (final t in widget.initial.items) TextEditingController(text: t),
  ];

  void _emit() {
    widget.onChanged(BulletBlockData([
      for (final c in _controllers) c.text,
    ]));
  }

  void _add() {
    setState(() => _controllers.add(TextEditingController()));
    _emit();
  }

  void _remove(int i) {
    setState(() => _controllers.removeAt(i).dispose());
    _emit();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _controllers.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 6, right: 10),
                child: Icon(Icons.circle, size: 7),
              ),
              Expanded(
                child: TextField(
                  controller: _controllers[i],
                  minLines: 1,
                  maxLines: null,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  onChanged: (_) => _emit(),
                ),
              ),
              if (_controllers.length > 1)
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _remove(i),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 2),
          child: TextButton.icon(
            onPressed: _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加项目'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
      ],
    );
  }
}

/// 表格块编辑（行列网格，支持增行/增列/删行/删列）。
class TableBlockEdit extends StatefulWidget {
  const TableBlockEdit({
    super.key,
    required this.initial,
    required this.onChanged,
  });
  final TableBlockData initial;
  final ValueChanged<TableBlockData> onChanged;

  @override
  State<TableBlockEdit> createState() => _TableBlockEditState();
}

class _TableBlockEditState extends State<TableBlockEdit> {
  late final List<List<TextEditingController>> _controllers = [
    for (final row in widget.initial.rows)
      [for (final cell in row) TextEditingController(text: cell)],
  ];

  void _emit() {
    widget.onChanged(TableBlockData(rows: [
      for (final row in _controllers) [for (final c in row) c.text],
    ]));
  }

  void _addRow() {
    setState(() => _controllers.add([
          for (var c = 0; c < _controllers.first.length; c++)
            TextEditingController(),
        ]));
    _emit();
  }

  void _addColumn() {
    setState(() {
      for (final row in _controllers) {
        row.add(TextEditingController());
      }
    });
    _emit();
  }

  void _removeRow(int i) {
    setState(() {
      for (final c in _controllers.removeAt(i)) {
        c.dispose();
      }
    });
    _emit();
  }

  void _removeColumn(int j) {
    setState(() {
      for (final row in _controllers) {
        row.removeAt(j).dispose();
      }
    });
    _emit();
  }

  @override
  void dispose() {
    for (final row in _controllers) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_controllers.isEmpty) {
      return TextButton.icon(
        onPressed: _addRow,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('创建表格'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Table(
            border: TableBorder.all(
              color: theme.dividerColor.withValues(alpha: 0.5),
            ),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              for (var i = 0; i < _controllers.length; i++)
                TableRow(
                  children: [
                    for (var j = 0; j < _controllers[i].length; j++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: TextField(
                          controller: _controllers[i][j],
                          minLines: 1,
                          maxLines: null,
                          style: theme.textTheme.bodyMedium,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (_) => _emit(),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('增行'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            TextButton.icon(
              onPressed: _addColumn,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('增列'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            if (_controllers.length > 1)
              TextButton.icon(
                onPressed: () => _removeRow(_controllers.length - 1),
                icon: const Icon(Icons.remove, size: 16),
                label: const Text('删行'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            if (_controllers.first.length > 1)
              TextButton.icon(
                onPressed: () => _removeColumn(_controllers.first.length - 1),
                icon: const Icon(Icons.remove, size: 16),
                label: const Text('删列'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
          ],
        ),
      ],
    );
  }
}

/// 图片块显示（点击全屏预览，可删除，可识别文字）。
class ImageBlockEdit extends StatelessWidget {
  const ImageBlockEdit({
    super.key,
    required this.localPath,
    required this.onDelete,
    this.onOcr,
    this.ocrBusy = false,
  });
  final String localPath;
  final VoidCallback onDelete;
  /// 图片文字识别回调（可为空 = 不显示识别按钮）。
  final VoidCallback? onOcr;
  final bool ocrBusy;

  @override
  Widget build(BuildContext context) {
    final file = File(localPath);
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: file.existsSync()
              ? Image.file(
                  file,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 120,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                )
              : Container(
                  height: 120,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(child: Icon(Icons.image_not_supported_outlined)),
                ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton.filledTonal(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(backgroundColor: Colors.black54),
          ),
        ),
        if (onOcr != null)
          Positioned(
            bottom: 4,
            left: 4,
            child: IconButton.filledTonal(
              onPressed: ocrBusy ? null : onOcr,
              icon: ocrBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.text_fields, size: 18),
              tooltip: '识别图片文字',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
            ),
          ),
      ],
    );
  }
}

/// 分隔线。
class DividerBlockEdit extends StatelessWidget {
  const DividerBlockEdit({super.key});
  @override
  Widget build(BuildContext context) => const Divider(height: 24);
}
