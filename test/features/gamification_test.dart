import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/gamification/gamification_service.dart';
import 'package:planerka/features/backup/backup_service.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:planerka/features/timers/timer_engine.dart';
import 'package:planerka/features/timers/timer_repository.dart';
import 'package:planerka/features/wellbeing/wellbeing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_gamification_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('database creates local game state tables and latest schema', () async {
    final tables = await database.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = tables.map((row) => row['name']).toSet();

    expect(names, contains('xp_events'));
    expect(names, contains('game_quests'));
    expect(names, contains('game_achievements'));
    expect(names, contains('custom_rewards'));
    expect(await database.database.rawQuery('PRAGMA user_version'), [
      {'user_version': 9},
    ]);
  });

  test('v3 upgrade adds game tables and keeps existing task data', () async {
    final path = p.join(directory.path, 'app.db');
    await database.database.insert('tasks', {
      'id': 'kept',
      'title': 'Сохранённая запись',
      'status': 'inbox',
      'created_at': '2026-10-08T00:00:00.000Z',
      'updated_at': '2026-10-08T00:00:00.000Z',
    });
    for (final table in [
      'custom_rewards',
      'game_achievements',
      'game_quests',
      'xp_events',
    ]) {
      await database.database.execute('DROP TABLE $table');
    }
    await database.database.execute('DROP TABLE task_goal_links');
    await database.database.execute('DROP INDEX tasks_parent_idx');
    await database.database.execute(
      'ALTER TABLE tasks DROP COLUMN parent_task_id',
    );
    await database.database.execute(
      'ALTER TABLE tasks DROP COLUMN estimated_minutes',
    );
    await database.database.execute(
      'ALTER TABLE tasks DROP COLUMN scheduled_at',
    );
    for (final table in [
      'shift_overrides',
      'shift_adjustments',
      'shift_attendance',
      'shift_settings',
      'shift_teams',
    ]) {
      await database.database.execute('DROP TABLE $table');
    }
    await database.database.execute('PRAGMA user_version = 3');
    await database.close();

    database = await AppDatabase.open(path, factory: databaseFactoryFfi);

    final task = await database.database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: ['kept'],
    );
    final xpTable = await database.database.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: ['table', 'xp_events'],
    );
    expect(task.single['title'], 'Сохранённая запись');
    expect(xpTable, hasLength(1));
  });

  test('XP awards are idempotent and levels use 100 point steps', () async {
    final game = GamificationService(database);
    await game.awardTask('same-task');
    await game.awardTask('same-task');
    for (var index = 0; index < 9; index++) {
      await game.awardTask('task-$index');
    }

    final progress = await game.progress();
    expect(progress.totalXp, 100);
    expect(progress.level, 2);
    expect(progress.xpInLevel, 0);
    expect(progress.xpToNextLevel, 100);
    expect(await database.database.query('xp_events'), hasLength(10));
  });

  test('weekly review grants one reward for the selected week', () async {
    final game = GamificationService(database);
    final thursday = DateTime(2026, 10, 8);
    await game.awardWeeklyReview(thursday);
    await game.awardWeeklyReview(thursday.add(const Duration(days: 2)));

    expect((await game.progress()).totalXp, 25);
    expect(await game.weeklyReviewAwarded(thursday), isTrue);
    expect(await database.database.query('xp_events'), hasLength(1));
  });

  test('daily and weekly quests track actions and award bonus once', () async {
    final now = DateTime(2026, 10, 8, 12);
    final game = GamificationService(database, now: () => now);
    expect(await game.dailyQuests(now), hasLength(3));
    expect(await game.weeklyQuests(now), hasLength(1));

    await game.awardTask('task-1', occurredAt: now);
    await game.awardFocusSession('focus-1', occurredAt: now);
    await game.awardHabitCheckIn('habit-1', now, occurredAt: now);

    final daily = await game.dailyQuests(now);
    expect(daily.every((quest) => quest.completed), isTrue);
    expect(daily.map((quest) => quest.progress), [1, 1, 1]);
    final week = (await game.weeklyQuests(now)).single;
    expect(week.progress, 1);
    expect(week.completed, isFalse);
    expect((await game.progress()).totalXp, 45);
    await game.dailyQuests(now);
    expect((await game.progress()).totalXp, 45);
  });

  test(
    'mood entries do not grant XP; achievements and custom rewards persist',
    () async {
      final game = GamificationService(database);
      final wellbeing = WellbeingRepository(database);
      await wellbeing.addJournal('Заметка', mood: 5);
      expect((await game.progress()).totalXp, 0);

      await game.awardTask('first-task');
      expect(
        (await game.achievements()).map((item) => item.key),
        contains('first_task'),
      );
      final reward = await game.addReward('Вечер кино');
      expect((await game.rewards()).single.title, 'Вечер кино');
      await game.redeemReward(reward.id);
      expect((await game.rewards()).single.redeemedAt, isNotNull);
      expect((await game.progress()).totalXp, 10);
    },
  );

  test(
    'task, focus, and habit actions award XP from their real repositories',
    () async {
      final now = DateTime(2026, 10, 8, 12);
      final inbox = InboxRepository(database, now: () => now);
      final entry = await inbox.add('Дело');
      await inbox.triage(entry.id, TaskDisposition.planned);
      final planning = PlanningRepository(database, now: () => now);
      await planning.complete(entry.id);
      await planning.complete(entry.id);

      final timers = TimerRepository(database);
      final engine = TimerEngine(timers, now: () => now);
      await engine.start(
        TimerKind.focus,
        const Duration(minutes: 45),
        taskId: entry.id,
      );
      await engine.finish();

      final wellbeing = WellbeingRepository(database, now: () => now);
      final habit = await wellbeing.addHabit('Прогулка');
      await wellbeing.checkIn(habit.id, now);
      await wellbeing.checkIn(habit.id, now);

      expect((await GamificationService(database).progress()).totalXp, 30);
      expect(await database.database.query('xp_events'), hasLength(3));
    },
  );

  test('v2 backup retains game data and imports legacy v1 backups', () async {
    final game = GamificationService(
      database,
      now: () => DateTime(2026, 10, 8, 12),
    );
    await game.awardTask('task');
    await game.dailyQuests(DateTime(2026, 10, 8));
    await game.addReward('Пауза');

    final backup = BackupService(database);
    final exported =
        jsonDecode(await backup.exportJson()) as Map<String, dynamic>;
    expect(exported['version'], 2);
    final destination = await AppDatabase.open(
      p.join(directory.path, 'destination.db'),
      factory: databaseFactoryFfi,
    );
    addTearDown(destination.close);
    await BackupService(destination)
        .importJson(jsonEncode(exported), mode: ImportMode.replace);
    expect((await GamificationService(destination).progress()).totalXp, 15);
    expect(await destination.database.query('game_quests'), hasLength(3));
    expect(
      (await GamificationService(destination).rewards()).single.title,
      'Пауза',
    );

    final legacy = jsonEncode({
      'version': 1,
      'tables': {
        for (final table in BackupService.legacyUserTables) table: <Object>[],
      },
    });
    await BackupService(destination)
        .importJson(legacy, mode: ImportMode.replace);
    expect((await GamificationService(destination).progress()).totalXp, 0);
    expect(await destination.database.query('game_quests'), isEmpty);
  });
}
