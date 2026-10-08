import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/ai/model/local_ai_engine.dart';
import 'package:planerka/features/ai/planning/ai_recommendation_service.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:planerka/features/shifts/shift_models.dart';
import 'package:planerka/features/shifts/shift_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  Future<List<Map<String, Object?>>> taskRows() => database.database.query(
    'tasks',
    columns: ['id', 'scheduled_date'],
    where: "id IN ('t1', 't2')",
    orderBy: 'id',
  );
  final now = DateTime(2026, 10, 8, 12);
  final generator = _FakeGenerator();
  late AiRecommendationService service;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_ai_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    await database.database.insert('tasks', _task('t1', 'Прогулка'));
    await database.database.insert('tasks', _task('t2', 'Позвонить в вуз'));
    await database.database.insert('goals', {
      'id': 'g1',
      'title': 'Читать регулярно',
      'progress': 2,
      'target': 10,
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    });
    await database.database.insert('journal_entries', {
      'id': 'j1',
      'text': 'Сегодня устал, нужен спокойный темп',
      'mood': 2,
      'created_at': now.toUtc().toIso8601String(),
    });
    generator.response = jsonEncode({
      'summary': 'Сохрани спокойный темп',
      'recommendations': [
        {'taskId': 't1', 'day': '2026-10-08', 'reason': 'Короткая прогулка'},
        {'taskId': 't2', 'day': '2026-10-09', 'reason': 'Можно перенести'},
      ],
    });
    service = AiRecommendationService(database, generator, now: () => now);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('builds local task, goal and user-approved diary context', () async {
    final context = await service.buildContext();
    expect(context.tasks.map((task) => task.id), ['t1', 't2']);
    expect(context.goals.single.title, 'Читать регулярно');
    expect(context.diary, isEmpty);
    expect(await service.diaryEnabled(), isFalse);

    await service.setDiaryEnabled(true);
    final withDiary = await service.buildContext();
    expect(withDiary.diary.single.note, 'Сегодня устал, нужен спокойный темп');
    expect(await service.diaryEnabled(), isTrue);

    await service.setDiaryEnabled(false);
    final withoutDiary = await service.buildContext();
    expect(withoutDiary.diary, isEmpty);
    expect(await service.diaryEnabled(), isFalse);
  });

  test(
    'validates local goal steps and adds them only when explicitly applied',
    () async {
      generator.response = jsonEncode({
        'steps': ['Открыть книгу', 'Читать 10 минут', 'Записать вывод'],
      });
      final steps = await service.generateGoalSteps('Читать регулярно');
      expect(steps, hasLength(3));
      expect(await database.database.query('projects'), isEmpty);
      await service.applyGoalSteps('g1', steps.take(2).toList());
      final projects = await database.database.query(
        'projects',
        where: 'goal_id = ?',
        whereArgs: ['g1'],
      );
      expect(projects, hasLength(1));
      final tasks = await database.database.query(
        'tasks',
        where: 'project_id = ?',
        whereArgs: [projects.single['id']],
      );
      expect(tasks.map((row) => row['title']), [
        'Открыть книгу',
        'Читать 10 минут',
      ]);
    },
  );

  test(
    'primary goal progress derives from linked tasks, not manual progress',
    () async {
      final projectId = await PlanningRepository(database)
          .ensureGoalProject('g1', 'Читать регулярно');
      await database.database.insert('tasks', {
        ..._task('g-task-1', 'Первый шаг'),
        'project_id': projectId,
      });
      await database.database.insert('tasks', {
        ..._task('g-task-2', 'Второй шаг'),
        'project_id': projectId,
        'status': 'completed',
      });
      final counts = await PlanningRepository(database).goalTaskCounts('g1');
      expect(counts.completed, 1);
      expect(counts.active, 1);
      await PlanningRepository(database).setPrimaryGoal('g1');
      expect((await PlanningRepository(database).primaryGoal())?.id, 'g1');
    },
  );

  test('rejects malformed goal steps', () {
    expect(
      () => GoalStepValidator().parse('{"steps":["один"]}'),
      throwsFormatException,
    );
    expect(
      () => GoalStepValidator().parse('{"steps":["а","а","б"]}'),
      throwsFormatException,
    );
  });

  test('Inbox AI preview does not write until selected apply', () async {
    final entry = await InboxRepository(database).add('Купить корм');
    generator.response = jsonEncode({
      'items': [
        {
          'taskId': entry.id,
          'disposition': 'quick',
          'dueAt': null,
          'reason': 'быстро',
        },
      ],
    });
    final suggestion = await service.classifyInbox();
    expect(suggestion.items, hasLength(1));
    expect(
      (await database.database.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [entry.id],
      )).single['status'],
      'inbox',
    );
    await service.applyInboxSelected(suggestion, {entry.id});
    expect(
      (await database.database.query(
        'tasks',
        where: 'id = ?',
        whereArgs: [entry.id],
      )).single['status'],
      'quick',
    );
  });

  test('generates a local preview without changing task rows', () async {
    final suggestion = await service.generatePlan();
    expect(suggestion.recommendations, hasLength(2));
    expect(generator.lastPrompt, isNot(contains('Сегодня устал')));
    await service.setDiaryEnabled(true);
    await service.generatePlan();
    expect(generator.lastPrompt, contains('Сегодня устал'));
    expect(
      (await taskRows()).every((row) => row['scheduled_date'] == null),
      isTrue,
    );
  });

  test(
    'AI context includes commute blocks and already scheduled tasks',
    () async {
      await ShiftRepository(database)
          .saveSchedule(ShiftSettings(anchorDate: DateTime(2026, 10, 8)), [
            for (var i = 0; i < 4; i++)
              ShiftTeam(
                id: 'team-$i',
                name: 'Смена ${i + 1}',
                leaderName: 'Руководитель ${i + 1}',
                colorValue: 0xFF336699,
                phaseOffsetDays: i * 2,
                attends: i == 0,
              ),
          ]);
      await database.database.update(
        'tasks',
        {'scheduled_at': '2026-10-09T10:00:00.000Z', 'estimated_minutes': 45},
        where: 'id = ?',
        whereArgs: ['t2'],
      );
      final context = await service.buildContext();
      expect(context.busyBlocks.any((block) => block.label == 'Смена'), isTrue);
      final scheduled = context.busyBlocks.singleWhere(
        (block) => block.taskId == 't2',
      );
      expect(
        scheduled.end.difference(scheduled.start),
        const Duration(minutes: 45),
      );
    },
  );

  test('applies only explicitly selected proposals', () async {
    final suggestion = await service.generatePlan();
    await database.database.update(
      'tasks',
      {'due_at': '2026-10-10T17:00:00.000Z'},
      where: 'id = ?',
      whereArgs: ['t2'],
    );
    await service.applySelected(suggestion, {'t2'});
    final rows = await taskRows();
    expect(
      rows.singleWhere((row) => row['id'] == 't1')['scheduled_date'],
      isNull,
    );
    expect(
      rows.singleWhere((row) => row['id'] == 't2')['scheduled_date'],
      '2026-10-09',
    );
    final t2 = await database.database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: ['t2'],
    );
    expect(
      t2.single['scheduled_at'],
      DateTime(2026, 10, 9, 9).toUtc().toIso8601String(),
    );
    expect(t2.single['estimated_minutes'], 30);
    expect(t2.single['due_at'], '2026-10-10T17:00:00.000Z');
  });

  test('cancelled preview leaves database unchanged', () async {
    await service.generatePlan();
    final rows = await taskRows();
    expect(rows.every((row) => row['scheduled_date'] == null), isTrue);
  });

  test(
    'stale task aborts selected apply transaction without partial updates',
    () async {
      final suggestion = await service.generatePlan();
      await database.database.update(
        'tasks',
        {'status': 'completed'},
        where: 'id = ?',
        whereArgs: ['t2'],
      );
      await expectLater(
        service.applySelected(suggestion, {'t1', 't2'}),
        throwsStateError,
      );
      final rows = await taskRows();
      expect(
        rows.singleWhere((row) => row['id'] == 't1')['scheduled_date'],
        isNull,
      );
    },
  );
}

Map<String, Object?> _task(String id, String title) => {
  'id': id,
  'title': title,
  'notes': '',
  'status': 'planned',
  'created_at': '2026-10-08T09:00:00.000Z',
  'updated_at': '2026-10-08T09:00:00.000Z',
};

class _FakeGenerator implements AiTextGenerator {
  String response = '';
  String lastPrompt = '';

  @override
  Future<String> generate(String prompt, {int maxTokens = 256}) async {
    lastPrompt = prompt;
    return response;
  }
}
