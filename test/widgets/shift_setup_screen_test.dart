import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/shifts/shift_repository.dart';
import 'package:planerka/features/shifts/shift_setup_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  late ShiftRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_shift_setup_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
    repository = ShiftRepository(database);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('setup creates four named teams with leaders and anchor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ShiftSetupScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    for (var index = 0; index < 4; index++) {
      await tester.enterText(
        find.byKey(ValueKey('team-name-$index')),
        'Смена ${String.fromCharCode(65 + index)}',
      );
      await tester.enterText(
        find.byKey(ValueKey('team-leader-$index')),
        'Руководитель ${String.fromCharCode(65 + index)}',
      );
    }
    await tester.drag(find.byType(ListView).first, const Offset(0, -800));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('anchor-team-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Смена B').last);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -5000));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-shift-schedule')));
    await tester.pumpAndSettle();

    final teams = await repository.listTeams();
    expect(teams, hasLength(4));
    expect(teams.map((team) => team.leaderName), [
      'Руководитель B',
      'Руководитель C',
      'Руководитель D',
      'Руководитель A',
    ]);
    expect(teams.map((team) => team.phaseOffsetDays), [0, 2, 4, 6]);
    expect((await repository.loadSettings())?.anchorDate, isNotNull);
  });

  testWidgets('setup preview shows teams at two day offsets', (tester) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: ShiftSetupScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -5000));
    await tester.pumpAndSettle();

    expect(find.textContaining('Смена 1 · Дневная'), findsWidgets);
    expect(find.textContaining('Смена 2 · Отдых перед ночью'), findsWidgets);
    expect(find.textContaining('Смена 3 · Ночная'), findsWidgets);
    expect(find.textContaining('Смена 4 · Выходной'), findsWidgets);
  });

  testWidgets('team colors can be changed from the automatic palette', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: ShiftSetupScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    final colorButton = find.byKey(const Key('team-color-0'));
    await tester.ensureVisible(colorButton);
    await tester.tap(colorButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('color-choice-ff62c9ff')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('team-color-0')), findsOneWidget);
  });
}
