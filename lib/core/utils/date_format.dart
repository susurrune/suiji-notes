/// 日期格式化工具（中文风格，始终含年份，便于确定创建时间）。
library;

/// "2026年8月1日"
String formatFullDate(DateTime t) => '${t.year}年${t.month}月${t.day}日';

/// "2026年8月1日 · 星期六"
String formatFullDateWithWeekday(DateTime t) {
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  return '${formatFullDate(t)} · 星期${weekdays[t.weekday - 1]}';
}

/// "13:05"
String formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
