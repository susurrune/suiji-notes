import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// 笔记定时提醒（本地通知）。
/// 通知 id 由 noteId 的 hashCode 派生，取消/重排按同一 id 处理。
class ReminderService {
  ReminderService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );
    _initialized = true;
  }

  static Future<void> _ensurePermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// 为笔记设置提醒；[at] 为空则取消既有提醒。
  static Future<void> schedule({
    required String noteId,
    required String title,
    required DateTime at,
  }) async {
    await init();
    await _ensurePermission();
    await _plugin.zonedSchedule(
      id: noteId.hashCode,
      title: '提醒 · $title',
      body: '该记点什么了',
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders',
          '笔记提醒',
          channelDescription: '笔记定时提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancel(String noteId) async {
    await init();
    await _plugin.cancel(id: noteId.hashCode);
  }
}
