# 随记 · R8 / ProGuard 规则

# ML Kit 文字识别：保留识别器类（运行时反射初始化），
# 其余可选脚本（日/韩/梵文）未打包进 APK，R8 需忽略其缺失。
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
