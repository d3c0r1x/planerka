import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test(
    'schedule block stays separate from deadline and can be cleared',
    () async {
      final dir = await Directory.systemTemp.createTemp('planner_block_');
      addTearDown(() => dir.delete(recursive: true));
      final db = await AppDatabase.open(
        p.join(dir.path, 'app.db'),
        factory: databaseFactoryFfi,
      );
      addTearDown(db.close);
      await db.database.insert('tasks', {
        'id': 't1',
        'title': 'Task',
        'status': 'planned',
        'due_at': '2026-10-10T17:00:00.000Z',
        'created_at': '2026-10-08T09:00:00.000Z',
        'updated_at': '2026-10-08T09:00:00.000Z',
      });
      final repo = PlanningRepository(db);
      await repo.setScheduleBlock('t1', DateTime(2026, 10, 9, 10), 45);
      var row = (await db.database.query('tasks')).single;
      expect(row['scheduled_at'], isNotNull);
      expect(row['estimated_minutes'], 45);
      expect(row['due_at'], '2026-10-10T17:00:00.000Z');
      final dayTasks = await repo.listForDay(DateTime(2026, 10, 9));
      expect(dayTasks.single.scheduledAt, DateTime(2026, 10, 9, 10).toUtc());
      await repo.clearScheduleBlock('t1');
      row = (await db.database.query('tasks')).single;
      expect(row['scheduled_at'], isNull);
      expect(row['estimated_minutes'], isNull);
      expect(row['due_at'], '2026-10-10T17:00:00.000Z');
      await expectLater(
        repo.setScheduleBlock('t1', DateTime(2026, 10, 9), 0),
        throwsArgumentError,
      );
    },
  );
}
