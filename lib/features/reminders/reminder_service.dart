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
    final now = _now();
    if (_allowed!) {
      final today = _day(now);
      await database.database.update(
        'tasks',
        {'scheduled_date': today, 'remind_at': now.toUtc().toIso8601String()},
        where: "status = 'quick' AND scheduled_date < ?",
        whereArgs: [today],
      );
      final nowUtc = now.toUtc();
      final taskRows = await database.database.query(
        'tasks',
        where: "status NOT IN ('completed', 'deleted', 'project') AND (status = 'quick' OR due_at IS NOT NULL OR remind_at IS NOT NULL)",
      );
      for (final row in taskRows) {
        final remind = row['remind_at'] as String?;
        final taskId = row['id'] as String;
        final title = row['title'] as String;
        if (row['status'] == 'quick') {
          final reminder = row['remind_at'] as String?;
          final day = DateTime.parse('${row['scheduled_date']}T00:00:00');
          final end = DateTime(day.year, day.month, day.day + 1);
          final stop = DateTime(
            day.year,
            day.month,
            day.day + 1,
          ).subtract(const Duration(hours: 4));
          var next = reminder == null || reminder.isEmpty
              ? DateTime(day.year, day.month, day.day, 8)
              : DateTime.parse(reminder).toLocal();
          if (!next.isAfter(now)) {
            final elapsed = now.difference(next).inMinutes;
            next = next.add(Duration(minutes: ((elapsed ~/ 120) + 1) * 120));
          }
          while (next.isBefore(stop) && next.isBefore(end)) {
            final instant = next.toUtc();
            desired[_id('quick:$taskId:$instant.millisecondsSinceEpoch')] = (
              'Пора сделать: $title',
              instant,
            );
            next = next.add(const Duration(hours: 2));
          }
          continue;
        }
        if (row['due_at'] != null && row['status'] == 'planned') {
          final due = DateTime.parse(row['due_at'] as String).toUtc();
          if (due.isAfter(nowUtc)) {
            desired[_id('task:$taskId:deadline')] = (
              'Срок задачи: $title',
              due,
            );
          }
        }
        if (remind?.isNotEmpty ?? false) {
          final reminder = DateTime.parse(remind!).toUtc();
          if (reminder.isAfter(nowUtc)) {
            desired[_id('task:$taskId:reminder')] = (
              'Напоминание: $title',
              reminder,
            );
          }
        }
      }
      final timerRows = await database.database.query(
        'timer_sessions',
        where: "status = 'running' AND deadline_at IS NOT NULL",
      );
      for (final row in timerRows) {
        final due = DateTime.parse(row['deadline_at'] as String).toUtc();
        if (due.isAfter(nowUtc)) {
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

  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
