import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/app.dart';
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
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
    final task = await inbox.add('Учить Go');
    await inbox.triage(task.id, TaskDisposition.quick);

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.tap(find.text('Прогресс'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Фокус').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('focusTaskPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Учить Go').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Начать фокус'));
    await tester.pumpAndSettle();
    expect(find.text('45:00'), findsOneWidget);
    await tester.tap(find.text('Пауза'));
    await tester.pumpAndSettle();
    expect(find.text('Продолжить'), findsOneWidget);
    await tester.tap(find.text('Завершить'));
    await tester.pumpAndSettle();
    expect(
      (await database.database.query('timer_sessions')).single['status'],
      'completed',
    );
    expect(find.text('Начать восстановление'), findsOneWidget);
  });

  testWidgets('delay records outcome and breathing opens', (tester) async {
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
    await tester.tap(find.text('Завершить'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Импульс прошёл');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(
      (await database.database.query('timer_sessions')).single['outcome'],
      'Импульс прошёл',
    );

    await tester.tap(find.text('Восстановление'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Дыхание 4–6–8'));
    await tester.pumpAndSettle();
    expect(find.text('Вдох'), findsOneWidget);
  });
}
