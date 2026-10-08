import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late AppDatabase database;
  late InboxRepository inbox;
  late PlanningRepository planning;
  var id = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_planning_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    id = 0;
    String nextId() => 'id-${++id}';
    DateTime now() => DateTime.utc(2026, 10, 8, 12);
    inbox = InboxRepository(database, now: now, newId: nextId);
    planning = PlanningRepository(database, now: now, newId: nextId);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('schedule shows task on due day and overdue until completion', () async {
    final task = await inbox.add('Сходить к стоматологу');
    await inbox.triage(task.id, TaskDisposition.planned);
    await planning.schedule(task.id, DateTime.utc(2026, 10, 10, 9));

    expect(
      (await planning.listForDay(DateTime.utc(2026, 10, 10))).single.id,
      task.id,
    );
    expect(await planning.listForDay(DateTime.utc(2026, 10, 9)), isEmpty);
    expect(
      await planning.listOverdue(DateTime.utc(2026, 10, 11)),
      hasLength(1),
    );

    await planning.complete(task.id);
    expect(await planning.listOverdue(DateTime.utc(2026, 10, 11)), isEmpty);
    expect(await planning.listForDay(DateTime.utc(2026, 10, 10)), isEmpty);
  });

  test('selected day and unscheduled backlog stay separate', () async {
    final quick = await inbox.add('Поставить стойку');
    final planned = await inbox.add('Разобрать шкаф');
    await inbox.triage(quick.id, TaskDisposition.quick);
    await inbox.triage(planned.id, TaskDisposition.planned);

    expect((await planning.listForDay(DateTime.utc(2026, 10, 8))).single.id,
        quick.id);
    expect((await planning.listUnscheduled()).single.id, planned.id);
    await planning.setToday(planned.id, DateTime.utc(2026, 10, 9));
    expect(
      (await planning.listForDay(DateTime.utc(2026, 10, 9))).single.id,
      planned.id,
    );
    expect(await planning.listUnscheduled(), isEmpty);
  });

  test('project action and linked goal persist with manual progress', () async {
    final source = await inbox.add('Закончить приложение');
    await inbox.triage(source.id, TaskDisposition.project);
    final project = (await planning.listProjects()).single;
    final action = await planning.addAction(project.id, 'Сделать экран задач');
    expect(
      (await planning.listProjectActions(project.id)).single.id,
      action.id,
    );

    final goal = await planning.addGoal(
      'Выпустить приложение',
      target: 100,
      unit: '%',
    );
    await planning.linkProjectToGoal(project.id, goal.id);
    await planning.updateGoalProgress(goal.id, 25);

    expect((await planning.listProjects()).single.goalId, goal.id);
    expect((await planning.listGoals()).single.progress, 25);
    expect((await planning.listGoals()).single.target, 100);
    expect((await planning.listGoals()).single.unit, '%');
  });

  test('task can help multiple goals and counts once for each goal', () async {
    final task = await inbox.add('Подготовить запуск');
    await inbox.triage(task.id, TaskDisposition.quick);
    final goalA = await planning.addGoal('Запустить продукт');
    final goalB = await planning.addGoal('Развить портфолио');
    await planning.setTaskGoalLinks(task.id, {goalA.id, goalB.id});

    expect(await planning.listTaskGoalLinks(task.id), {goalA.id, goalB.id});
    expect((await planning.goalTaskCounts(goalA.id)).active, 1);
    expect((await planning.goalTaskCounts(goalB.id)).active, 1);

    await planning.setTaskGoalLinks(task.id, {goalB.id}, source: 'ai');
    expect(await planning.listTaskGoalLinks(task.id), {goalB.id});
  });

  test('large project task contains selectable child tasks', () async {
    final source = await inbox.add('Разработать приложение');
    await inbox.triage(source.id, TaskDisposition.project);
    final children = await planning.addTaskChild(source.id, 'Собрать экран');
    expect(children.parentTaskId, source.id);
    expect((await planning.listTaskChildren(source.id)).single.id, children.id);
  });
}
