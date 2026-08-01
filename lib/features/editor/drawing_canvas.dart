import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/data/media/media_storage.dart';

/// 手绘画布：多笔画自由绘制，支持撤销/清空/保存为 PNG。
/// 通过 `GlobalKey<DrawingCanvasState>` 访问撤销/清空/保存能力。
class DrawingCanvas extends StatefulWidget {
  const DrawingCanvas({super.key});
  final Color color = Colors.black87;
  final double strokeWidth = 4;

  @override
  State<DrawingCanvas> createState() => DrawingCanvasState();
}

class DrawingCanvasState extends State<DrawingCanvas> {
  final List<List<Offset>> _strokes = [];
  List<Offset>? _current;

  bool get isEmpty => _strokes.isEmpty;

  void undo() {
    setState(() {
      if (_strokes.isNotEmpty) _strokes.removeLast();
    });
  }

  void clear() => setState(() => _strokes.clear());

  /// 渲染当前画布为 PNG 并持久化到应用目录，返回文件路径。
  Future<String> saveAsPng(GlobalKey boundaryKey) async {
    final boundary = boundaryKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final tmp = File(p.join(
        (await getTemporaryDirectory()).path, 'drawing_${DateTime.now().millisecondsSinceEpoch}.png'));
    await tmp.writeAsBytes(bytes!.buffer.asUint8List());
    return MediaStorage.persist(tmp);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => setState(() {
          _current = [d.localPosition];
          _strokes.add(_current!);
        }),
        onPanUpdate: (d) => setState(() => _current!.add(d.localPosition)),
        onPanEnd: (_) => setState(() => _current = null),
        child: CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _StrokePainter(_strokes, widget.color, widget.strokeWidth),
        ),
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes, this.color, this.strokeWidth);
  final List<List<Offset>> strokes;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final pt in stroke.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}

/// 全屏手绘编辑器：完成后返回持久化的 PNG 路径（取消返回 null）。
class DrawingScreen extends StatefulWidget {
  const DrawingScreen({super.key});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  final _boundaryKey = GlobalKey();
  final _canvasKey = GlobalKey<DrawingCanvasState>();
  bool _saving = false;

  DrawingCanvasState get _canvas => _canvasKey.currentState!;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final path = await _canvas.saveAsPng(_boundaryKey);
      if (mounted) Navigator.of(context).pop(path);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('手绘'),
        actions: [
          IconButton(
            tooltip: '撤销',
            icon: const Icon(Icons.undo),
            onPressed: _canvas.isEmpty ? null : _canvas.undo,
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.layers_clear),
            onPressed: _canvas.isEmpty ? null : _canvas.clear,
          ),
          IconButton(
            tooltip: '保存',
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: RepaintBoundary(
            key: _boundaryKey,
            child: ColoredBox(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF1E1E1E)
                  : Colors.white,
              child: DrawingCanvas(key: _canvasKey),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '用手指绘制，右上角保存',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
      ),
    );
  }
}
