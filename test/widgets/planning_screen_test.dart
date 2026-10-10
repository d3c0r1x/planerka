import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/app.dart';
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:planerka/features/review/review_service.dart';
import 'package:planerka/features/review/progress_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_plan_widget_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('unscheduled task can be selected for today and completed', (
    tester,
  ) async {
    final inbox = InboxRepository(database);
    final task = await inbox.add('Разобрать шкаф');
    await inbox.triage(task.id, TaskDisposition.planned);
    final planning = PlanningRepository(database);
    await planning.setToday(task.id, DateTime.now());
    expect((await planning.listForDay(DateTime.now())).single.id, task.id);
    await planning.complete(task.id);
    expect(await planning.listForDay(DateTime.now()), isEmpty);
    final rows = await database.database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [task.id],
    );
    expect(rows.single['scheduled_date'], isNotNull);
    final completed = await database.database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [task.id],
    );
    expect(completed.single['status'], 'completed');
  });

  testWidgets('progress screen switches between day and week', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProgressScreen(service: ReviewService(database))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Выполнено задач'), findsOneWidget);
    expect(find.byKey(const Key('progress-metric-completed')), findsOneWidget);
    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();
    expect(find.text('Отметки привычек'), findsOneWidget);
    expect(find.textContaining(' — '), findsOneWidget);
  });

  testWidgets('progress compares the selected day with real prior data', (
    tester,
  ) async {
    final now = DateTime.now();
    final currentAt = DateTime(
      now.year,
      now.month,
      now.day,
      12,
    ).toUtc().toIso8601String();
    final previousAt = DateTime(
      now.year,
      now.month,
      now.day - 1,
      12,
    ).toUtc().toIso8601String();
    Future<void> addCompleted(String id, String completedAt) async {
      await database.database.insert('tasks', {
        'id': id,
        'title': 'Фикстура $id',
        'status': 'completed',
        'completed_at': completedAt,
        'created_at': completedAt,
        'updated_at': completedAt,
      });
    }

    await addCompleted('current-a', currentAt);
    await addCompleted('current-b', currentAt);
    await addCompleted('previous-a', previousAt);
    await database.database.insert('journal_entries', {
      'id': 'current-mood',
      'text': 'Current fixture',
      'mood': 4,
      'created_at': currentAt,
    });
    await database.database.insert('journal_entries', {
      'id': 'previous-mood',
      'text': 'Previous fixture',
      'mood': 3,
      'created_at': previousAt,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProgressScreen(service: ReviewService(database))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('progress-period-comparison')), findsOneWidget);
    expect(find.text('Сравнение со вчера'), findsOneWidget);
    expect(find.text('Задачи +1'), findsOneWidget);
    expect(find.text('Настроение +1,0'), findsOneWidget);

    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();
    expect(find.text('Сравнение с прошлой неделей'), findsOneWidget);
  });

  testWidgets('progress shows mood ratings without diary text', (tester) async {
    final now = DateTime.now();
    await database.database.insert('journal_entries', {
      'id': 'synthetic-mood-entry',
      'text': 'Приватный синтетический текст',
      'mood': 4,
      'created_at': DateTime(
        now.year,
        now.month,
        now.day,
        10,
      ).toUtc().toIso8601String(),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProgressScreen(service: ReviewService(database))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('progress-mood-card')), findsOneWidget);
    expect(find.text('4,0 из 5'), findsOneWidget);
    expect(find.text('1 отметка'), findsOneWidget);
    expect(find.text('Приватный синтетический текст'), findsNothing);
  });

  testWidgets('progress screen fits 360dp with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.35)),
          child: Scaffold(
            body: ProgressScreen(service: ReviewService(database)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar is reachable from Today', (tester) async {
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.tap(find.byTooltip('Календарь'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-month-grid')), findsOneWidget);
    expect(find.byKey(const Key('calendar-day-summary')), findsOneWidget);
  });

  testWidgets('project screen adds a concrete action', (tester) async {
    final inbox = InboxRepository(database);
    final source = await inbox.add('Большой проект');
    await inbox.triage(source.id, TaskDisposition.project);

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.tap(find.byTooltip('Ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Проекты').last);
    await tester.pumpAndSettle();
    expect(find.text('Большой проект'), findsOneWidget);
    await tester.tap(find.byTooltip('Добавить шаг'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Первый шаг');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Первый шаг'), findsOneWidget);
  });

  testWidgets('goal screen creates a goal and updates progress', (
    tester,
  ) async {
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.tap(find.byTooltip('Ещё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Цели').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Добавить цель'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      'Выпустить приложение',
    );
    await tester.enterText(find.byType(TextField).at(1), '100');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('Выпустить приложение'), findsOneWidget);
    await tester.tap(find.text('Сделать главной'));
    await tester.pumpAndSettle();
    final selected = await PlanningRepository(database).primaryGoal();
    expect(selected?.title, 'Выпустить приложение');
    final counts = await PlanningRepository(database)
        .goalTaskCounts(selected!.id);
    expect(counts.completed + counts.active, 0);
    expect(await database.database.query('tasks'), isEmpty);
  });
}
