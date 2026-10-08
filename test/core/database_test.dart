import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('new database stores an inbox entry across reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'planerka_db_test_',
    );
    final path = p.join(directory.path, 'planerka.db');
    addTearDown(() => directory.delete(recursive: true));

    final first = await AppDatabase.open(path, factory: databaseFactoryFfi);
    await first.database.insert('tasks', {
      'id': 'entry-1',
      'title': 'Купить корм',
      'status': 'inbox',
      'created_at': '2026-10-07T12:00:00.000Z',
      'updated_at': '2026-10-07T12:00:00.000Z',
    });
    await first.close();

    final second = await AppDatabase.open(path, factory: databaseFactoryFfi);
    final rows = await second.database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: ['entry-1'],
    );
    expect(rows.single['title'], 'Купить корм');
    expect(rows.single['status'], 'inbox');
    await second.close();
  });

  test('new database creates all v1 data tables', () async {
    final directory = await Directory.systemTemp.createTemp(
      'planerka_schema_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final db = await AppDatabase.open(
      p.join(directory.path, 'planerka.db'),
      factory: databaseFactoryFfi,
    );

    final tables = await db.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final names = tables.map((row) => row['name']).toSet();
    expect(
      names,
      containsAll([
        'tasks',
        'projects',
        'goals',
        'habits',
        'habit_logs',
        'journal_entries',
        'timer_sessions',
        'task_goal_links',
        'shift_teams',
        'shift_settings',
        'shift_overrides',
        'shift_adjustments',
        'shift_attendance',
      ]),
    );
    await db.close();
  });

  test(
    'opening a v1 database adds timer state without losing sessions',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'planerka_upgrade_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'legacy.db');
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => db.execute('''
          CREATE TABLE timer_sessions (
            id TEXT PRIMARY KEY, kind TEXT NOT NULL, task_id TEXT,
            duration_seconds INTEGER NOT NULL, started_at TEXT NOT NULL,
            ended_at TEXT, status TEXT NOT NULL, outcome TEXT
          )
        '''),
        ),
      );
      await legacy.insert('timer_sessions', {
        'id': 'old-session',
        'kind': 'focus',
        'duration_seconds': 2700,
        'started_at': '2026-10-07T12:00:00.000Z',
        'status': 'completed',
      });
      await legacy.close();

      final upgraded = await AppDatabase.open(
        path,
        factory: databaseFactoryFfi,
      );
      addTearDown(upgraded.close);
      final columns = await upgraded.database.rawQuery(
        'PRAGMA table_info(timer_sessions)',
      );
      expect(
        columns.map((column) => column['name']),
        containsAll(['deadline_at', 'remaining_seconds']),
      );
      expect(
        (await upgraded.database.query('timer_sessions')).single['id'],
        'old-session',
      );
      expect(
        await upgraded.database.rawQuery('PRAGMA table_info(app_metadata)'),
        isNotEmpty,
      );
    },
  );

  test('v6 to v7 migration preserves planner, diary and XP rows', () async {
    final directory = await Directory.systemTemp.createTemp(
      'planerka_v6_shift_upgrade_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = p.join(directory.path, 'legacy-v6.db');
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE goals (id TEXT PRIMARY KEY, title TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE journal_entries (id TEXT PRIMARY KEY, text TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE xp_events (event_id TEXT PRIMARY KEY, points INTEGER NOT NULL)',
          );
        },
      ),
    );
    await legacy.insert('tasks', {'id': 'task-v6', 'title': 'Старая задача'});
    await legacy.insert('goals', {'id': 'goal-v6', 'title': 'Старая цель'});
    await legacy.insert('journal_entries', {
      'id': 'mood-v6',
      'text': 'Старая запись',
    });
    await legacy.insert('xp_events', {'event_id': 'xp-v6', 'points': 10});
    await legacy.close();

    final upgraded = await AppDatabase.open(path, factory: databaseFactoryFfi);
    addTearDown(upgraded.close);

    expect((await upgraded.database.query('tasks')).single['id'], 'task-v6');
    expect((await upgraded.database.query('goals')).single['id'], 'goal-v6');
    expect(
      (await upgraded.database.query('journal_entries')).single['id'],
      'mood-v6',
    );
    expect(
      (await upgraded.database.query('xp_events')).single['event_id'],
      'xp-v6',
    );
    expect(await upgraded.database.query('shift_teams'), isEmpty);
    expect(
      (await upgraded.database.rawQuery('PRAGMA user_version'))
          .single['user_version'],
      7,
    );
  });
}
