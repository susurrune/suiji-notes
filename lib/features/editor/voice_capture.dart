import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/data/media/media_storage.dart';

/// 语音录制结果。
class VoiceCaptureResult {
  const VoiceCaptureResult({
    required this.audioPath,
    required this.durationMs,
    required this.transcript,
  });
  final String audioPath;
  final int durationMs;
  final String transcript;
}

/// 语音笔记录制：优先 ASR 实时转写（转写文本可搜索）；
/// ASR 不可用时降级为仅录音文件。
/// 通过 `showModalBottomSheet<VoiceCaptureResult>` 返回结果。
Future<VoiceCaptureResult?> showVoiceCapture(BuildContext context) {
  return showModalBottomSheet<VoiceCaptureResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const VoiceCaptureSheet(),
  );
}

class VoiceCaptureSheet extends StatefulWidget {
  const VoiceCaptureSheet({super.key});

  @override
  State<VoiceCaptureSheet> createState() => _VoiceCaptureSheetState();
}

class _VoiceCaptureSheetState extends State<VoiceCaptureSheet> {
  AudioRecorder? _recorder;
  String? _audioPath;
  bool _recording = false;
  bool _processing = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  String _transcript = '';

  SpeechToText? _stt;
  bool _sttReady = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _stt?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要麦克风权限才能录音')));
      }
      return;
    }

    final path = p.join(
      (await getTemporaryDirectory()).path,
      'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );

    // ASR：先初始化，若可用则与录音并行实时转写
    final stt = SpeechToText();
    final sttReady = await stt.initialize();
    if (sttReady) {
      await stt.listen(
        onResult: (r) => setState(() => _transcript = r.recognizedWords),
        listenOptions: SpeechListenOptions(localeId: 'zh_CN'),
      );
    }

    await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path);

    if (!mounted) return;
    setState(() {
      _recorder = recorder;
      _audioPath = path;
      _recording = true;
      _stt = stt;
      _sttReady = sttReady;
      _elapsed = Duration.zero;
      _transcript = '';
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _stopAndFinish() async {
    setState(() {
      _recording = false;
      _processing = true;
    });
    _ticker?.cancel();
    final path = _audioPath;
    final duration = _elapsed.inMilliseconds;
    final transcript = _transcript;

    try {
      await _recorder?.stop();
    } catch (_) {}
    if (_sttReady) {
      try {
        await _stt?.stop();
      } catch (_) {}
    }

    if (path == null || !File(path).existsSync()) {
      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('录音失败，请重试')));
      }
      return;
    }
    final saved = await MediaStorage.persist(File(path));
    if (mounted) {
      Navigator.of(context).pop(VoiceCaptureResult(
        audioPath: saved,
        durationMs: duration,
        transcript: transcript,
      ));
    }
  }

  String get _clock {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _processing
                  ? '正在保存…'
                  : _recording
                      ? '录音中 $_clock'
                      : '点击开始录音',
              style: theme.textTheme.titleMedium,
            ),
            if (_transcript.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '转写：$_transcript',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _recording ? _stopAndFinish : _start,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _recording ? 74 : 64,
                height: _recording ? 74 : 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _recording
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
                child: Icon(
                  _recording ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _recording ? '再次点击结束并保存' : '支持语音转文字，识别后可搜索',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
