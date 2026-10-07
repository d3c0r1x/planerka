import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/app.dart';
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
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

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
    expect(find.text('Разобрать шкаф'), findsOneWidget);
    await tester.tap(find.byTooltip('На сегодня'));
    await tester.pumpAndSettle();
    final rows = await database.database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [task.id],
    );
    expect(rows.single['scheduled_date'], isNotNull);

    await tester.tap(find.byTooltip('Завершить'));
    await tester.pumpAndSettle();
    expect(find.text('Разобрать шкаф'), findsNothing);
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
    await tester.tap(find.text('Неделя'));
    await tester.pumpAndSettle();
    expect(find.text('Отметки привычек'), findsOneWidget);
    expect(find.textContaining(' — '), findsOneWidget);
  });

  testWidgets('calendar is reachable from Today', (tester) async {
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.tap(find.byTooltip('Календарь'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);
  });

  testWidgets('project screen adds a concrete action', (tester) async {
    final inbox = InboxRepository(database);
    final source = await inbox.add('Большой проект');
    await inbox.triage(source.id, TaskDisposition.project);

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.tap(find.byTooltip('Проекты'));
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
    await tester.tap(find.byTooltip('Цели'));
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

    await tester.tap(find.byTooltip('Обновить прогресс'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '25');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('25 / 100'), findsOneWidget);
  });
}
