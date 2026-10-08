import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:planerka/features/shifts/shift_models.dart';
import 'package:planerka/features/shifts/shift_repository.dart';
import 'package:planerka/features/widget/widget_snapshot.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  late PlanningRepository planning;
  late ShiftRepository shifts;
  final now = DateTime(2026, 10, 8, 10);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_widget_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    planning = PlanningRepository(database, now: () => now);
    shifts = ShiftRepository(database, now: () => now);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('empty goal and task list produce a safe empty snapshot', () async {
    final snapshot = await PlannerWidgetSnapshot.fromRepositories(
      planning: planning,
      shifts: shifts,
      now: now,
    );

    expect(snapshot.goalTitle, 'Добавь цель');
    expect(snapshot.goalPercent, 0);
    expect(snapshot.tasks, isEmpty);
    expect(snapshot.nextShift, isNull);
  });

  test(
    'shows up to three tasks with overdue marker and keeps Russian text',
    () async {
      await database.database.insert('goals', {
        'id': 'goal',
        'title': 'Прочитать книгу',
        'progress': 2,
        'target': 4,
        'unit': 'главы',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await planning.setPrimaryGoals({'goal'});
      for (var i = 1; i <= 5; i++) {
        await database.database.insert('tasks', {
          'id': 'task-$i',
          'title': 'Задача $i',
          'status': 'planned',
          'due_at': i == 1
              ? now.subtract(const Duration(days: 1)).toUtc().toIso8601String()
              : null,
          'scheduled_date': '2026-10-08',
          'created_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
        });
      }

      final snapshot = await PlannerWidgetSnapshot.fromRepositories(
        planning: planning,
        shifts: shifts,
        now: now,
      );

      expect(snapshot.goalTitle, 'Прочитать книгу');
      expect(snapshot.goalPercent, 50);
      expect(snapshot.tasks, hasLength(3));
      expect(snapshot.tasks.first.isOverdue, isTrue);
      expect(snapshot.tasks.map((task) => task.title), contains('Задача 1'));
    },
  );

  test(
    'uses linked task completion when the goal has no numeric target',
    () async {
      await database.database.insert('goals', {
        'id': 'goal',
        'title': 'Портфолио',
        'progress': 0,
        'target': null,
        'unit': '',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await planning.setPrimaryGoals({'goal'});
      await database.database.insert('tasks', {
        'id': 'done',
        'title': 'Первый проект',
        'status': 'completed',
        'created_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      });
      await planning.setTaskGoalLinks('done', {'goal'});
      await database.database.insert('tasks', {
        'id': 'active',
        'title': 'Второй проект',
        'status': 'planned',
        'created_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      });
      await planning.setTaskGoalLinks('active', {'goal'});

      final snapshot = await PlannerWidgetSnapshot.fromRepositories(
        planning: planning,
        shifts: shifts,
        now: now,
      );

      expect(snapshot.goalPercent, 50);
    },
  );

  test(
    'shows the nearest selected active shift and omits unselected teams',
    () async {
      await shifts.saveSchedule(
        ShiftSettings(anchorDate: DateTime(2026, 10, 8)),
        [
          _team('selected', 0, attends: true),
          _team('not-selected', 2, attends: false),
          _team('third', 4, attends: false),
          _team('fourth', 6, attends: false),
        ],
      );

      final snapshot = await PlannerWidgetSnapshot.fromRepositories(
        planning: planning,
        shifts: shifts,
        now: now,
      );

      expect(snapshot.nextShift, isNotNull);
      expect(snapshot.nextShift!.teamId, 'selected');
    },
  );
}

ShiftTeam _team(String id, int offset, {required bool attends}) => ShiftTeam(
  id: id,
  name: 'Смена $id',
  leaderName: 'Руководитель',
  colorValue: 0xFF42D8B2,
  phaseOffsetDays: offset,
  attends: attends,
);
