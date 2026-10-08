import 'package:flutter/material.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/app.dart';
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/wellbeing/wellbeing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_home_test_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('dark dashboard shows daily plan and fast actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = InboxRepository(database);
    final task = await repo.add('Подготовить день');
    await repo.triage(task.id, TaskDisposition.planned);
    final wellbeing = WellbeingRepository(database);
    final habit = await wellbeing.addHabit('Читать');
    await wellbeing.checkIn(habit.id, DateTime.now());

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(find.text('Твой день, твой ритм'), findsOneWidget);
    expect(find.byKey(const ValueKey('today-screen-true')), findsOneWidget);
    expect(find.byKey(const Key('home-day-progress')), findsOneWidget);
    expect(find.text('Inbox'), findsAtLeastNWidgets(1));
    expect(find.text('Таймер'), findsOneWidget);
    expect(find.text('Привычки'), findsOneWidget);
    expect(find.text('Дневник'), findsOneWidget);
  });
}
