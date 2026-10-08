import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:planerka/features/reminders/reminder_service.dart';
import 'package:planerka/features/reminders/sleep_mode_service.dart';
import 'package:planerka/features/shifts/shift_models.dart';
import 'package:planerka/features/shifts/shift_repository.dart';
import 'package:planerka/features/timers/timer_engine.dart';
import 'package:planerka/features/timers/timer_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeNotifications implements NotificationPort {
  final scheduled = <int, DateTime>{};
  final scheduledActions = <int, List<NotificationAction>>{};
  bool permission = true;
  Future<void> Function(String actionId, String payload)? responseHandler;

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<void> schedule(
    int id,
    String title,
    DateTime at, {
    String? payload,
    List<NotificationAction> actions = const [],
  }) async {
    scheduled[id] = at;
    scheduledActions[id] = actions;
  }

  @override
  void setResponseHandler(
    Future<void> Function(String actionId, String payload) handler,
  ) => responseHandler = handler;

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<Set<int>> pendingIds() async => scheduled.keys.toSet();
}

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  late FakeNotifications notifications;
  late ReminderService reminders;
  final now = DateTime.utc(2026, 10, 8, 12);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_reminders_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    notifications = FakeNotifications();
    reminders = ReminderService(database, notifications, now: () => now);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('schedule, move and complete task refreshes notification', () async {
    final task = await InboxRepository(database).add('Вымышленная задача');
    final planning = PlanningRepository(database);
    await planning.schedule(task.id, now.add(const Duration(hours: 1)));
    await reminders.rescheduleAll();
    expect(notifications.scheduled.length, 1);
    expect(
      notifications.scheduled.values.single,
      now.add(const Duration(hours: 1)),
    );

    await planning.schedule(task.id, now.add(const Duration(hours: 2)));
    await reminders.rescheduleAll();
    expect(notifications.scheduled.length, 1);
    expect(
      notifications.scheduled.values.single,
      now.add(const Duration(hours: 2)),
    );

    await planning.complete(task.id);
    await reminders.rescheduleAll();
    expect(notifications.scheduled, isEmpty);
  });

  test(
    'quick action reminders repeat every two hours and stop after completion',
    () async {
      final repo = InboxRepository(database, now: () => now);
      final task = await repo.add('Короткое дело');
      await repo.triage(task.id, TaskDisposition.quick);

      await reminders.rescheduleAll();
      expect(
        notifications.scheduledActions.values.first.map((action) => action.id),
        ['complete', 'postpone'],
      );
      expect(notifications.scheduled.values.toSet(), {
        DateTime.utc(2026, 10, 8, 14),
        DateTime.utc(2026, 10, 8, 16),
        DateTime.utc(2026, 10, 8, 18),
        DateTime.utc(2026, 10, 8, 20),
      });

      final afternoon = DateTime.utc(2026, 10, 8, 15);
      final later = ReminderService(
        database,
        notifications,
        now: () => afternoon,
      );
      await later.rescheduleAll();
      expect(notifications.scheduled.values.toSet(), {
        DateTime.utc(2026, 10, 8, 16),
        DateTime.utc(2026, 10, 8, 18),
        DateTime.utc(2026, 10, 8, 20),
      });

      await PlanningRepository(database).complete(task.id);
      await later.rescheduleAll();
      expect(notifications.scheduled, isEmpty);
    },
  );

  test('sleep cancels reminders and wake starts a fresh two hour interval', () async {
    final task = await InboxRepository(database, now: () => now).add('Короткое дело');
    await InboxRepository(database, now: () => now).triage(
      task.id,
      TaskDisposition.quick,
    );
    final sleep = SleepModeService(database, now: () => now);
    await reminders.rescheduleAll();
    expect(notifications.scheduled, isNotEmpty);

    await sleep.setEnabled(true);
    reminders = ReminderService(
      database,
      notifications,
      now: () => now,
      sleepMode: sleep,
    );
    await reminders.rescheduleAll();
    expect(notifications.scheduled, isEmpty);

    final wakeTime = now.add(const Duration(hours: 6));
    await sleep.setEnabled(false, at: wakeTime);
    reminders = ReminderService(
      database,
      notifications,
      now: () => wakeTime,
      sleepMode: sleep,
    );
    await reminders.rescheduleAll();
    expect(notifications.scheduled.values.first, wakeTime.add(const Duration(hours: 2)));
  });

  test('attended shift reminder is scheduled before commute starts', () async {
    final shiftRepository = ShiftRepository(database, now: () => now);
    await shiftRepository.saveSchedule(
      ShiftSettings(anchorDate: DateTime(2026, 10, 9)),
      [
        for (var index = 0; index < 4; index++)
          ShiftTeam(
            id: 'team-$index',
            name: 'Смена ${index + 1}',
            leaderName: 'Руководитель ${index + 1}',
            colorValue: 0xFF55D8C7,
            phaseOffsetDays: index * 2,
            attends: index == 0,
          ),
      ],
    );
    reminders = ReminderService(
      database,
      notifications,
      now: () => now,
      shifts: shiftRepository,
    );
    await reminders.rescheduleAll();

    expect(
      notifications.scheduled.values,
      contains(DateTime(2026, 10, 9, 6, 30).toUtc()),
    );
    expect(notifications.scheduled.values, hasLength(4));

    await shiftRepository.setAttendance(
      'team-0',
      DateTime(2026, 10, 9),
      ShiftAttendance.attended,
    );
    await reminders.rescheduleAll();
    expect(notifications.scheduled.values, hasLength(3));
    expect(
      notifications.scheduled.values,
      isNot(contains(DateTime(2026, 10, 9, 6, 30).toUtc())),
    );
  });

  test('notification actions complete or postpone only an active task', () async {
    final task = await InboxRepository(database, now: () => now).add('Короткое дело');
    await InboxRepository(database, now: () => now).triage(
      task.id,
      TaskDisposition.quick,
    );
    await reminders.rescheduleAll();
    expect(notifications.responseHandler, isNotNull);

    await notifications.responseHandler!('postpone', task.id);
    expect(notifications.scheduled.values.first, now.add(const Duration(hours: 2)));

    await notifications.responseHandler!('complete', task.id);
    expect((await database.database.query('tasks')).single['status'], 'completed');
    await notifications.responseHandler!('complete', task.id);
    await notifications.responseHandler!('unknown', task.id);
    expect((await database.database.query('tasks')).single['status'], 'completed');
  });

  test('unfinished quick task rolls into today after midnight', () async {
    final repo = InboxRepository(database, now: () => now);
    final task = await repo.add('Вычислительная задача');
    await repo.triage(task.id, TaskDisposition.quick);
    final tomorrow = DateTime.utc(2026, 10, 9, 1);
    final nextDay = ReminderService(database, notifications, now: () => tomorrow);
    await nextDay.rescheduleAll();
    final row = (await database.database.query('tasks')).single;
    expect(row['scheduled_date'], '2026-10-09');
      expect(notifications.scheduled.values, contains(DateTime.utc(2026, 10, 9, 3)));
  });

  test(
    'explicit task reminder is persisted and cancelled on completion',
    () async {
      final task = await InboxRepository(database).add('Позвонить');
      final at = now.add(const Duration(minutes: 30));
      final planning = PlanningRepository(database);
      await planning.setReminder(task.id, at);
      await reminders.rescheduleAll();
      expect(notifications.scheduled.values.single, at);
      await planning.complete(task.id);
      await reminders.rescheduleAll();
      expect(notifications.scheduled, isEmpty);
    },
  );

  test('running timer is restored; pause and finish cancel it', () async {
    final task = await InboxRepository(database).add('Вымышленная задача');
    final engine = TimerEngine(TimerRepository(database), now: () => now);
    await engine.start(
      TimerKind.focus,
      const Duration(minutes: 45),
      taskId: task.id,
    );
    await reminders.rescheduleAll();
    expect(notifications.scheduled.length, 1);

    await engine.pause();
    await reminders.rescheduleAll();
    expect(notifications.scheduled, isEmpty);
    await engine.resume();
    await reminders.rescheduleAll();
    expect(notifications.scheduled.length, 1);
    await engine.finish();
    await reminders.rescheduleAll();
    expect(notifications.scheduled, isEmpty);
  });

  test('denied permission keeps task intact', () async {
    notifications.permission = false;
    final task = await InboxRepository(database).add('Вымышленная задача');
    await PlanningRepository(database)
        .schedule(task.id, now.add(const Duration(minutes: 10)));
    expect(await reminders.enable(), isFalse);
    await reminders.rescheduleAll();
    expect(notifications.scheduled, isEmpty);
    expect((await database.database.query('tasks')).single['id'], task.id);
  });

  test(
    'repository changes reschedule immediately through database hook',
    () async {
      database.onRemindersChanged = reminders.rescheduleAll;
      final task = await InboxRepository(database).add('Вымышленная задача');
      await PlanningRepository(database)
          .schedule(task.id, now.add(const Duration(minutes: 30)));
      expect(notifications.scheduled.length, 1);
      await PlanningRepository(database).complete(task.id);
      expect(notifications.scheduled, isEmpty);
    },
  );
}
