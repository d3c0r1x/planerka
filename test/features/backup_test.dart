import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/backup/backup_service.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/wellbeing/wellbeing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase source;
  late BackupService backup;

  Future<AppDatabase> open(String name) => AppDatabase.open(
    p.join(directory.path, name),
    factory: databaseFactoryFfi,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_backup_');
    source = await open('source.db');
    backup = BackupService(source);
  });

  tearDown(() async {
    await source.close();
    await directory.delete(recursive: true);
  });

  test('round trip retains all user tables', () async {
    final task = await InboxRepository(source).add('Вымышленная запись');
    final habit = await WellbeingRepository(source).addHabit('Прогулка');
    await WellbeingRepository(source).addJournal('Короткая заметка', mood: 3);
    await source.database.insert('habit_logs', {
      'id': 'log',
      'habit_id': habit.id,
      'date': '2026-10-08',
      'value': 1,
      'created_at': '2026-10-08T00:00:00.000Z',
    });
    await source.database.insert('timer_sessions', {
      'id': 'timer',
      'kind': 'focus',
      'task_id': task.id,
      'duration_seconds': 2700,
      'started_at': '2026-10-08T00:00:00.000Z',
      'status': 'completed',
      'elapsed_seconds': 1200,
    });
    await source.database.insert('timer_settings', {
      'key': 'focus_minutes',
      'value': 50,
    });
    await source.database.insert('goals', {
      'id': 'goal',
      'title': 'Цель',
      'unit': '',
      'progress': 2.0,
      'created_at': '2026-10-08T00:00:00.000Z',
      'updated_at': '2026-10-08T00:00:00.000Z',
    });
    await source.database.insert('projects', {
      'id': 'project',
      'title': 'Проект',
      'created_at': '2026-10-08T00:00:00.000Z',
    });
    await source.database.update(
      'tasks',
      {'project_id': 'project'},
      where: 'id = ?',
      whereArgs: [task.id],
    );

    final json = await backup.exportJson();
    final destination = await open('destination.db');
    addTearDown(destination.close);
    await BackupService(destination).importJson(json, mode: ImportMode.replace);
    expect(
      (await destination.database.query('tasks')).single['title'],
      'Вымышленная запись',
    );
    expect(await destination.database.query('habits'), hasLength(1));
    expect(await destination.database.query('habit_logs'), hasLength(1));
    expect(await destination.database.query('journal_entries'), hasLength(1));
    expect(await destination.database.query('goals'), hasLength(1));
    expect(await destination.database.query('projects'), hasLength(1));
    expect(await destination.database.query('timer_sessions'), hasLength(1));
    expect(await destination.database.query('timer_settings'), hasLength(1));
  });

  test('invalid backup is rejected before changing data', () async {
    await InboxRepository(source).add('Останется');
    await expectLater(
      backup.importJson('{bad json', mode: ImportMode.replace),
      throwsFormatException,
    );
    expect(
      (await InboxRepository(source).listUnsorted()).single.title,
      'Останется',
    );
  });

  test('merge import is idempotent and replace clears old rows', () async {
    await InboxRepository(source).add('Текущая');
    final json = await backup.exportJson();
    await backup.importJson(json, mode: ImportMode.merge);
    await backup.importJson(json, mode: ImportMode.merge);
    expect(await source.database.query('tasks'), hasLength(1));

    final empty = jsonEncode({
      'version': 1,
      'tables': {
        for (final table in BackupService.userTables) table: <Object>[],
      },
    });
    await backup.importJson(empty, mode: ImportMode.replace);
    expect(await source.database.query('tasks'), isEmpty);
  });

  test(
    'private seed imports Inbox titles only once and never triages them',
    () async {
      const seed = '{"version":1,"tasks":["Задача раз","Задача два"]}';
      expect(await backup.importPrivateSeed(seed), 2);
      expect(await backup.importPrivateSeed(seed), 0);
      final tasks = await InboxRepository(source).listUnsorted();
      expect(
        tasks.map((task) => task.title),
        containsAll(['Задача раз', 'Задача два']),
      );
      expect(
        tasks.every((task) => task.dueAt == null && task.status == 'inbox'),
        isTrue,
      );
      final empty = jsonEncode({
        'version': 1,
        'tables': {
          for (final table in BackupService.userTables) table: <Object>[],
        },
      });
      await backup.importJson(empty, mode: ImportMode.replace);
      expect(await backup.importPrivateSeed(seed), 0);
    },
  );
}
