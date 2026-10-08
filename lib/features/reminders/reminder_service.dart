import '../../core/app_database.dart';
import '../planning/planning_repository.dart';
import '../shifts/shift_repository.dart';
import 'sleep_mode_service.dart';

abstract class NotificationPort {
  Future<bool> requestPermission();
  Future<void> schedule(
    int id,
    String title,
    DateTime at, {
    String? payload,
    List<NotificationAction> actions = const [],
  });
  void setResponseHandler(
    Future<void> Function(String actionId, String payload) handler,
  );
  Future<void> cancel(int id);
  Future<Set<int>> pendingIds();
}

class NotificationAction {
  const NotificationAction({required this.id, required this.label});
  final String id;
  final String label;
}

class ReminderService {
  ReminderService(
    this.database,
    this.notifications, {
    DateTime Function()? now,
    this.shifts,
    SleepModeService? sleepMode,
  }) : _now = now ?? DateTime.now,
       sleepMode = sleepMode ?? SleepModeService(database) {
    notifications.setResponseHandler(handleResponse);
  }

  final AppDatabase database;
  final NotificationPort notifications;
  final ShiftRepository? shifts;
  final SleepModeService sleepMode;
  final DateTime Function() _now;
  bool? _allowed;
  static const _taskActions = [
    NotificationAction(id: 'complete', label: 'Выполнено'),
    NotificationAction(id: 'postpone', label: 'Перенести на 2 часа'),
  ];

  Future<bool> enable() async {
    _allowed = await notifications.requestPermission();
    return _allowed!;
  }

  Future<void> handleResponse(String actionId, String taskId) async {
    if (actionId != 'complete' && actionId != 'postpone') return;
    final rows = await database.database.query(
      'tasks',
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty ||
        const {'completed', 'deleted', 'project'}.contains(rows.single['status'])) {
      return;
    }
    final planning = PlanningRepository(database);
    if (actionId == 'complete') {
      await planning.complete(taskId);
    } else {
      await planning.setReminder(taskId, _now().add(const Duration(hours: 2)));
    }
    await rescheduleAll();
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
    final desired = <int, _PlannedNotification>{};
    final now = _now();
    final sleeping = await sleepMode.isEnabled();
    if (_allowed! && !sleeping) {
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
          var next = reminder == null || reminder.isEmpty
              ? DateTime(day.year, day.month, day.day, 8)
              : DateTime.parse(reminder).toLocal();
          final wakeAt = await sleepMode.lastWakeAt();
          if (wakeAt != null && wakeAt.isAfter(next)) {
            next = wakeAt.add(const Duration(hours: 2));
          }
          if (!next.isAfter(now)) {
            final elapsed = now.difference(next).inMinutes;
            next = next.add(Duration(minutes: ((elapsed ~/ 120) + 1) * 120));
          }
          while (next.isBefore(end)) {
            final instant = next.toUtc();
            desired[_id('quick:$taskId:$instant.millisecondsSinceEpoch')] =
                _PlannedNotification(
                  'Пора сделать: $title',
                  instant,
                  payload: taskId,
                  actions: _taskActions,
                );
            next = next.add(const Duration(hours: 2));
          }
          continue;
        }
        if (row['due_at'] != null && row['status'] == 'planned') {
          final due = DateTime.parse(row['due_at'] as String).toUtc();
          if (due.isAfter(nowUtc)) {
            desired[_id('task:$taskId:deadline')] = _PlannedNotification(
              'Срок задачи: $title',
              due,
              payload: taskId,
              actions: _taskActions,
            );
          }
        }
        if (remind?.isNotEmpty ?? false) {
          final reminder = DateTime.parse(remind!).toUtc();
          if (reminder.isAfter(nowUtc)) {
            desired[_id('task:$taskId:reminder')] = _PlannedNotification(
              'Напоминание: $title',
              reminder,
              payload: taskId,
              actions: _taskActions,
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
          desired[_id('timer:${row['id']}')] = _PlannedNotification(title, due);
        }
      }
      await _scheduleShiftReminders(desired, now);
    }
    for (final id in previous) {
      if (!desired.containsKey(id)) await notifications.cancel(id);
    }
    for (final entry in desired.entries) {
      await notifications.schedule(
        entry.key,
        entry.value.title,
        entry.value.at,
        payload: entry.value.payload,
        actions: entry.value.actions,
      );
    }
  }

  Future<void> _scheduleShiftReminders(
    Map<int, _PlannedNotification> desired,
    DateTime now,
  ) async {
    final repository = shifts;
    if (repository == null) return;
    final settings = await repository.loadSettings();
    if (settings == null) return;
    final teams = await repository.listTeams();
    final end = DateTime(now.year, now.month, now.day + 8);
    final days = await repository.calendar(
      DateTime(now.year, now.month, now.day),
      end,
    );
    for (final day in days) {
      if (day.cancelled || day.workStart == null) continue;
      final team = teams.where((item) => item.id == day.teamId).firstOrNull;
      if (team == null || !team.attends) continue;
      if (await repository.attendanceFor(day.teamId, day.date) != null) continue;
      final commuteStart = day.blockStart ?? day.workStart!;
      final reminderAt = commuteStart.subtract(
        Duration(minutes: settings.reminderLeadMinutes),
      );
      if (!reminderAt.isAfter(now)) continue;
      final instant = reminderAt.toUtc();
      desired[_id('shift:${day.teamId}:${_day(day.date)}')] = _PlannedNotification(
        'Смена ${team.name} скоро начнётся',
        instant,
      );
    }
  }

  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _PlannedNotification {
  const _PlannedNotification(
    this.title,
    this.at, {
    this.payload,
    this.actions = const [],
  });

  final String title;
  final DateTime at;
  final String? payload;
  final List<NotificationAction> actions;
}
