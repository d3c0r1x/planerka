import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/wellbeing/habits_screen.dart';
import 'package:planerka/features/wellbeing/journal_screen.dart';
import 'package:planerka/features/wellbeing/wellbeing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  late WellbeingRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_wellbeing_ui_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
    repository = WellbeingRepository(database);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('habit can be created and marked today', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HabitsScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Привычка'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Читать');
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    expect(find.text('Читать'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(
      (await repository.summary(
        (await repository.listHabits()).single.id,
        DateTime.now(),
      )).todayDone,
      isTrue,
    );
  });

  testWidgets('journal entry can be created and edited', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: JournalScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Запись'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Сегодня спокойно');
    await tester.tap(find.text('4'));
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect((await repository.listJournal()).single.mood, 4);
    await tester.tap(find.text('Сегодня спокойно'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Исправлено');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect((await repository.listJournal()).single.text, 'Исправлено');
  });
}
