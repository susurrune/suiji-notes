import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 端侧 OCR：识别图片文字（中文脚本模型首次使用自动下载）。
/// 识别结果以 `source=imageOcr` 的文本块写入笔记，参与全文检索。
class OcrService {
  OcrService._();

  static final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.chinese);

  /// 识别图片文件中的文字，失败返回空串。
  static Future<String> recognize(String imagePath) async {
    try {
      final input = InputImage.fromFilePath(imagePath);
      final result = await _recognizer.processImage(input);
      return result.text.trim();
    } catch (_) {
      return '';
    }
  }

  static void dispose() => _recognizer.close();
}
