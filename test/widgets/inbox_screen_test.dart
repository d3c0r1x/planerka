import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/app.dart';
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/inbox/inbox_screen.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
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

  testWidgets('Inbox entry is compact, clear, and keeps accessible actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final entry = await InboxRepository(database).add('Подготовить портфолио');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: InboxScreen(repository: InboxRepository(database)),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byKey(ValueKey('inbox-entry-${entry.id}'));
    expect(card, findsOneWidget);
    expect(tester.getSize(card).height, lessThanOrEqualTo(230));
    expect(find.byKey(const Key('inbox-entry-type')), findsOneWidget);
    expect(find.byKey(const Key('inbox-empty-triage-guide')), findsNothing);
    expect(find.byKey(const Key('inbox-entry-priority')), findsOneWidget);
    expect(find.text('На разборе'), findsOneWidget);
    expect(find.text('Без приоритета'), findsOneWidget);
    expect(find.byTooltip('Приоритет не задан'), findsOneWidget);
    expect(find.text('Выбери, что делать дальше'), findsNothing);

    final semanticsHandle = tester.ensureSemantics();
    for (final (key, tooltip) in [
      (const Key('inbox-triage-quick'), 'Сделать быстро'),
      (const Key('inbox-triage-planned'), 'Запланировать'),
      (const Key('inbox-triage-project'), 'Большой проект'),
    ]) {
      final action = find.descendant(of: card, matching: find.byKey(key));
      expect(action, findsOneWidget);
      expect(find.byTooltip(tooltip), findsOneWidget);
      expect(
        tester
            .getSemantics(action)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
    }
    semanticsHandle.dispose();
    expect(find.byTooltip('Связать с целью'), findsOneWidget);
    expect(find.byTooltip('Изменить'), findsOneWidget);
    expect(find.byTooltip('Другие действия'), findsOneWidget);
  });

  testWidgets('empty Inbox explains the three next-step routes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-inbox')));
    await tester.pumpAndSettle();

    expect(find.text('Входящие'), findsAtLeastNWidgets(1));
    expect(find.byKey(const Key('inbox-empty-triage-guide')), findsOneWidget);
    expect(find.text('Быстро'), findsOneWidget);
    expect(find.text('Срок'), findsOneWidget);
    expect(find.text('Проект'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('inbox-empty-triage-guide'))).height,
      lessThanOrEqualTo(180),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('add and triage an Inbox entry from the app', (tester) async {
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.tap(find.byKey(const Key('center-action-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quick-capture-input')),
      'Купить корм',
    );
    await tester.tap(find.byKey(const Key('quick-capture-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-inbox')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inbox-hero')), findsOneWidget);
    expect(find.byKey(const Key('inbox-count')), findsOneWidget);
    expect(find.text('Купить корм'), findsOneWidget);
    await tester.tap(find.byKey(const Key('inbox-triage-quick')));
    await tester.pumpAndSettle();

    expect(find.text('Купить корм'), findsNothing);
    final rows = await database.database.query('tasks');
    expect(rows.single['status'], 'quick');
  });

  testWidgets('Inbox hero opens shared capture and refreshes the list', (
    tester,
  ) async {
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-inbox')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('inbox-capture')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quick-capture-input')),
      'Новая идея',
    );
    await tester.tap(find.byKey(const Key('quick-capture-save')));
    await tester.pumpAndSettle();

    final rows = await database.database.query('tasks');
    expect(rows, hasLength(1));
    expect(rows.single['title'], 'Новая идея');
    expect(rows.single['status'], 'inbox');
    expect(find.text('Новая идея'), findsOneWidget);
    expect(find.text('1 мысль'), findsOneWidget);
  });

  testWidgets('project triage is directly available and persists', (
    tester,
  ) async {
    final inbox = InboxRepository(database);
    final project = await inbox.add('Проверить новый маршрут');
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-inbox')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('inbox-entry-${project.id}')),
        matching: find.byKey(const Key('inbox-triage-project')),
      ),
    );
    await tester.pumpAndSettle();

    final rows = await database.database.query('tasks');
    expect(rows.single['status'], 'project');
  });

  testWidgets('delete action stays available in the entry menu', (
    tester,
  ) async {
    final discard = await InboxRepository(database).add('Черновик без дела');
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-inbox')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('inbox-more-${discard.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    final rows = await database.database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [discard.id],
    );
    expect(rows.single['status'], 'deleted');
  });

  testWidgets('planned triage asks for both date and time', (tester) async {
    final task = await InboxRepository(database).add('Отправить заявление');
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-inbox')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('inbox-entry-${task.id}')),
        matching: find.byKey(const Key('inbox-triage-planned')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('ОК').last);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('ОК').last);
    await tester.pumpAndSettle();

    final rows = await database.database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: [task.id],
    );
    expect(rows.single['status'], 'planned');
    expect(rows.single['due_at'], isNotNull);
  });

  testWidgets('blank Inbox entry is not saved', (tester) async {
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.tap(find.byKey(const Key('center-action-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quick-capture-save')));
    await tester.pumpAndSettle();

    expect(await database.database.query('tasks'), isEmpty);
    expect(find.byKey(const Key('quick-capture-input')), findsOneWidget);
  });

  testWidgets('app keeps the Inbox AI control accessible', (tester) async {
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-inbox')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-navigation-dock')), findsOneWidget);
  });
}
