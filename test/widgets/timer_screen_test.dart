import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/app.dart';
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:planerka/features/timers/focus_screen.dart';
import 'package:planerka/features/timers/timer_engine.dart';
import 'package:planerka/features/timers/timer_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_timer_widget_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('focus selects one task and can pause and finish', (
    tester,
  ) async {
    final inbox = InboxRepository(database);
    final task = await inbox.add('Подготовить пакет');
    await inbox.triage(task.id, TaskDisposition.quick);

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.tap(find.text('Прогресс'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Фокус').last);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('focus-timer-hero')),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('focusTaskPicker')));
    await tester.tap(find.byKey(const Key('focusTaskPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подготовить пакет').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Начать фокус'));
    await tester.pumpAndSettle();
    expect(find.text('45:00'), findsOneWidget);
    await tester.tap(find.text('Пауза'));
    await tester.pumpAndSettle();
    expect(find.text('Продолжить'), findsOneWidget);
    await tester.ensureVisible(find.text('Завершить'));
    await tester.tap(find.text('Завершить'));
    await tester.pumpAndSettle();
    expect(
      (await database.database.query('timer_sessions')).single['status'],
      'completed',
    );
    expect(find.text('Начать восстановление'), findsOneWidget);
  });

  testWidgets('delay records its outcome', (tester) async {
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.tap(find.text('Прогресс'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Фокус').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отсрочка'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Начать отсрочку'));
    await tester.pumpAndSettle();
    expect(find.text('10:00'), findsOneWidget);
    await tester.dragFrom(const Offset(400, 400), const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Завершить'));
    await tester.tap(find.text('Завершить'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Импульс прошёл');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(
      (await database.database.query('timer_sessions')).single['outcome'],
      'Импульс прошёл',
    );
  });

  testWidgets('focus has a radial hero and keeps the chosen task visible', (
    tester,
  ) async {
    final inbox = InboxRepository(database);
    final task = await inbox.add('Подготовить релиз');
    await inbox.triage(task.id, TaskDisposition.quick);
    await PlanningRepository(database).setToday(task.id, DateTime.now());

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: FocusScreen(
            engine: TimerEngine(TimerRepository(database)),
            planning: PlanningRepository(database),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('focusTaskPicker')));
    await tester.tap(find.byKey(const Key('focusTaskPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подготовить релиз').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('focus-timer-ring')), findsOneWidget);
    expect(find.byKey(const Key('focus-selected-task')), findsOneWidget);
    expect(find.text('Подготовить релиз'), findsWidgets);
    expect(find.byKey(const Key('focus-primary-action')), findsOneWidget);
  });

  testWidgets('resumed focus keeps title of a task scheduled for another day', (
    tester,
  ) async {
    final inbox = InboxRepository(database);
    final task = await inbox.add('Подготовить отчёт');
    await inbox.triage(task.id, TaskDisposition.planned);
    await PlanningRepository(database).setToday(
      task.id,
      DateTime.now().add(const Duration(days: 1)),
    );
    final engine = TimerEngine(TimerRepository(database));
    await engine.start(
      TimerKind.focus,
      const Duration(minutes: 45),
      taskId: task.id,
    );
    await engine.pause();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: FocusScreen(
            engine: engine,
            planning: PlanningRepository(database),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('focus-selected-task')), findsOneWidget);
    expect(find.text('Подготовить отчёт'), findsOneWidget);
  });

  testWidgets('resumed focus keeps title of a completed task', (tester) async {
    final inbox = InboxRepository(database);
    final task = await inbox.add('Закрыть задачу');
    await inbox.triage(task.id, TaskDisposition.quick);
    final engine = TimerEngine(TimerRepository(database));
    await engine.start(
      TimerKind.focus,
      const Duration(minutes: 45),
      taskId: task.id,
    );
    await engine.pause();
    await PlanningRepository(database).complete(task.id);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: FocusScreen(
            engine: engine,
            planning: PlanningRepository(database),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('focus-selected-task')), findsOneWidget);
    expect(find.text('Закрыть задачу'), findsOneWidget);
  });

  testWidgets('recovery mode gives breathing its own secondary card', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: FocusScreen(
            engine: TimerEngine(TimerRepository(database)),
            planning: PlanningRepository(database),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Восстановление'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recovery-breathing-card')), findsOneWidget);
    expect(find.text('Дыхание 4–6–8'), findsOneWidget);
    await tester.dragFrom(const Offset(400, 450), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дыхание 4–6–8'));
    await tester.pumpAndSettle();
    expect(find.text('Вдох'), findsOneWidget);
  });

  testWidgets('focus screen fits 360dp with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.35)),
          child: Scaffold(
            body: FocusScreen(
              engine: TimerEngine(TimerRepository(database)),
              planning: PlanningRepository(database),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
