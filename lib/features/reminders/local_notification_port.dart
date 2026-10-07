import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_service.dart';

class LocalNotificationPort implements NotificationPort {
  LocalNotificationPort() {
    timezone_data.initializeTimeZones();
  }

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _initialize() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> schedule(int id, String title, DateTime at) async {
    await _initialize();
    Future<void> submit(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: id,
      title: title,
      body: 'Откройте Планерку',
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'planerka_reminders',
          'Напоминания',
          channelDescription: 'Задачи и таймеры',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: mode,
    );
    try {
      await submit(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException {
      await submit(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  @override
  Future<void> cancel(int id) async {
    await _initialize();
    await _plugin.cancel(id: id);
  }

  @override
  Future<Set<int>> pendingIds() async {
    await _initialize();
    final pending = await _plugin.pendingNotificationRequests();
    return pending.map((request) => request.id).toSet();
  }
}
