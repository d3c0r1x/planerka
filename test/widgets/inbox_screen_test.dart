import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/app.dart';
import 'package:planerka/core/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_widget_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('add and triage an Inbox entry from the app', (tester) async {
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.tap(find.byTooltip('Добавить'));
    await tester.pumpAndSettle();
    final dialogInput = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(dialogInput, findsOneWidget);
    await tester.enterText(dialogInput, 'Купить корм');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(find.text('Купить корм'), findsOneWidget);
    await tester.tap(find.byTooltip('Разобрать'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сделать быстро').last);
    await tester.pumpAndSettle();

    expect(find.text('Купить корм'), findsNothing);
    final rows = await database.database.query('tasks');
    expect(rows.single['status'], 'quick');
  });

  testWidgets('blank Inbox entry is not saved', (tester) async {
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.tap(find.byTooltip('Добавить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(await database.database.query('tasks'), isEmpty);
    expect(find.text('Введите задачу'), findsOneWidget);
  });
}
