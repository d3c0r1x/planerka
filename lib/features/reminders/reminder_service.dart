import '../../core/app_database.dart';

abstract class NotificationPort {
  Future<bool> requestPermission();
  Future<void> schedule(int id, String title, DateTime at);
  Future<void> cancel(int id);
  Future<Set<int>> pendingIds();
}

class ReminderService {
  ReminderService(this.database, this.notifications, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase database;
  final NotificationPort notifications;
  final DateTime Function() _now;
  bool? _allowed;

  Future<bool> enable() async {
    _allowed = await notifications.requestPermission();
    return _allowed!;
  }

  int _id(String key) {
    // Stable positive 31-bit FNV-1a ID across app restarts.
    var hash = 0x811c9dc5;
    for (final code in key.codeUnits) {
      hash = ((hash ^ code) * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  Future<void> rescheduleAll() async {
    _allowed ??= await notifications.requestPermission();
    final previous = await notifications.pendingIds();
    final desired = <int, (String, DateTime)>{};
    if (_allowed!) {
      final now = _now().toUtc();
      final taskRows = await database.database.query(
        'tasks',
        where: "due_at IS NOT NULL AND status NOT IN ('completed', 'deleted', 'project')",
      );
      for (final row in taskRows) {
        final due = DateTime.parse(row['due_at'] as String).toUtc();
        if (due.isAfter(now)) {
          desired[_id('task:${row['id']}')] = (row['title'] as String, due);
        }
      }
      final timerRows = await database.database.query(
        'timer_sessions',
        where: "status = 'running' AND deadline_at IS NOT NULL",
      );
      for (final row in timerRows) {
        final due = DateTime.parse(row['deadline_at'] as String).toUtc();
        if (due.isAfter(now)) {
          final kind = row['kind'] as String;
          final title = switch (kind) {
            'focus' => 'Фокус завершён',
            'recovery' => 'Восстановление завершено',
            _ => 'Отсрочка завершена',
          };
          desired[_id('timer:${row['id']}')] = (title, due);
        }
      }
    }
    for (final id in previous) {
      if (!desired.containsKey(id)) await notifications.cancel(id);
    }
    for (final entry in desired.entries) {
      await notifications.schedule(entry.key, entry.value.$1, entry.value.$2);
    }
  }
}
