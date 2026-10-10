import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/app.dart';
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_home_first_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('Home first viewport shows capture and today task', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final planning = PlanningRepository(database);
    final goal = await planning.addGoal('Синтетическая главная цель');
    await planning.setPrimaryGoals({goal.id});
    final inbox = InboxRepository(database);
    final task = await inbox.add('Синтетическая задача на сегодня');
    final now = DateTime.now();
    await inbox.triage(
      task.id,
      TaskDisposition.quick,
      remindAt: now.add(const Duration(hours: 2)),
    );

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-primary-goal-progress')), findsOneWidget);
    expect(find.byKey(const Key('home-inbox-input')), findsOneWidget);
    expect(find.byKey(const Key('home-today-section')), findsOneWidget);
    final taskRow = find.byKey(ValueKey('today-task-${task.id}'));
    expect(taskRow, findsOneWidget);
    expect(
      tester.getTopLeft(taskRow).dy,
      lessThan(720),
      reason: 'Today task must be visible without scrolling on a phone.',
    );
  });
}
