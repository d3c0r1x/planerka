import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/app.dart';
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
}
