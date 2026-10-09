import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/app.dart';
import 'package:planerka/core/app_database.dart';
import 'package:planerka/core/models.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:planerka/features/goals/goals_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RetryableGoalsRepository extends PlanningRepository {
  _RetryableGoalsRepository(
    super.database, {
    required this.goals,
    required this.primary,
    this.failFirstReadFor = const {},
  });

  final List<Goal> goals;
  final Set<String> primary;
  final Set<String> failFirstReadFor;
  final Map<String, int> progressReads = {};

  @override
  Future<List<Goal>> listGoals() async => goals;

  @override
  Future<List<Goal>> primaryGoals() async =>
      goals.where((goal) => primary.contains(goal.id)).toList();

  @override
  Future<({int completed, int total})> goalTaskProgress(String goalId) async {
    final reads = (progressReads[goalId] ?? 0) + 1;
    progressReads[goalId] = reads;
    if (failFirstReadFor.contains(goalId) && reads == 1) {
      throw StateError('synthetic read failure');
    }
    return (completed: 1, total: 2);
  }

  @override
  Future<String?> goalNextActionTitle(String goalId) async =>
      'Продолжить выбранный шаг';
}

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_goals_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('home opens goals with task progress and an empty state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final planning = PlanningRepository(database);
    final goal = await planning.addGoal('Выпустить приложение');
    await planning.setPrimaryGoals({goal.id});

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-primary-goal-progress')), findsOneWidget);
    await tester.tap(find.byTooltip('Цели'));
    await tester.pumpAndSettle();

    expect(find.text('Цели'), findsOneWidget);
    expect(find.byKey(const Key('goal-task-progress')), findsOneWidget);
    expect(find.byKey(const Key('goal-progress-summary')), findsOneWidget);
    expect(find.text('Добавьте шаг, чтобы видеть прогресс'), findsOneWidget);
    expect(find.text('0 из 0 шагов выполнено'), findsOneWidget);

    final projectId = await planning.ensureGoalProject(goal.id, goal.title);
    final step = await planning.addAction(projectId, 'Подготовить релиз');
    await planning.complete(step.id);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Цели'));
    await tester.pumpAndSettle();

    expect(find.text('1 из 1 шагов выполнено'), findsOneWidget);
    expect(find.text('Добавьте шаг, чтобы видеть прогресс'), findsNothing);
  });

  testWidgets('goal screen shows progress for multiple primary goals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final planning = PlanningRepository(database);
    final first = await planning.addGoal('Здоровье');
    final second = await planning.addGoal('Развитие');
    await planning.setPrimaryGoals({first.id, second.id});

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Цели'));
    await tester.pumpAndSettle();

    expect(find.text('Здоровье'), findsAtLeastNWidgets(1));
    expect(find.text('Развитие'), findsAtLeastNWidgets(1));
    expect(find.byKey(const Key('goal-task-progress')), findsNWidgets(2));
  });

  testWidgets('primary goal hero shows truthful percent and next open step', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final planning = PlanningRepository(database);
    final goal = await planning.addGoal('Собрать портфолио');
    await planning.setPrimaryGoals({goal.id});
    final projectId = await planning.ensureGoalProject(goal.id, goal.title);
    final done = await planning.addAction(projectId, 'Оформить профиль');
    await planning.addAction(projectId, 'Подготовить первый проект');
    await planning.complete(done.id);

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Цели'));
    await tester.pumpAndSettle();

    expect(find.text('50%'), findsOneWidget);
    expect(find.text('1 из 2 шагов выполнено'), findsOneWidget);
    expect(find.text('Следующий шаг'), findsOneWidget);
    expect(find.text('Подготовить первый проект'), findsOneWidget);
    expect(find.text('Собрать портфолио'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Inbox and goals fit a compact 360dp viewport', (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final planning = PlanningRepository(database);
    final goal = await planning.addGoal('Сделать полезное дело');
    await planning.setPrimaryGoals({goal.id});

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-inbox')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('nav-today')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Цели'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('main goal retry reloads progress after a read failure', (
    tester,
  ) async {
    const goal = Goal(
      id: 'synthetic-main',
      title: 'Цель для проверки',
      progress: 0,
    );
    final repository = _RetryableGoalsRepository(
      database,
      goals: const [goal],
      primary: const {'synthetic-main'},
      failFirstReadFor: const {'synthetic-main'},
    );
    await tester.pumpWidget(
      MaterialApp(home: GoalsScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить прогресс цели'), findsOneWidget);
    expect(repository.progressReads[goal.id], 1);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();

    expect(repository.progressReads[goal.id], 2);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets(
    'secondary primary goal retry does not show false zero progress',
    (tester) async {
      const first = Goal(
        id: 'synthetic-first',
        title: 'Первая цель',
        progress: 0,
      );
      const second = Goal(
        id: 'synthetic-second',
        title: 'Вторая цель',
        progress: 0,
      );
      final repository = _RetryableGoalsRepository(
        database,
        goals: const [first, second],
        primary: const {'synthetic-first', 'synthetic-second'},
        failFirstReadFor: const {'synthetic-second'},
      );
      await tester.pumpWidget(
        MaterialApp(home: GoalsScreen(repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Прогресс недоступен'), findsOneWidget);
      expect(find.text('0/0'), findsNothing);
      final retry = find.byKey(ValueKey('retry-primary-goal-${second.id}'));
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(repository.progressReads[second.id], 2);
      expect(find.text('Прогресс недоступен'), findsNothing);
      expect(find.text('1/2'), findsOneWidget);
    },
  );
}
