import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:planerka/features/reminders/reminder_service.dart';
import 'package:planerka/features/timers/timer_engine.dart';
import 'package:planerka/features/timers/timer_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeNotifications implements NotificationPort {
  final scheduled = <int, DateTime>{};
  bool permission = true;

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<void> schedule(int id, String title, DateTime at) async {
    scheduled[id] = at;
  }

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
      expect(notifications.scheduled.values.toSet(), {
        DateTime.utc(2026, 10, 8, 14),
        DateTime.utc(2026, 10, 8, 16),
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
      });

      await PlanningRepository(database).complete(task.id);
      await later.rescheduleAll();
      expect(notifications.scheduled, isEmpty);
    },
  );

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
