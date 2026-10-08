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
    directory = await Directory.systemTemp.createTemp('planerka_flagship_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('default theme keeps the day canvas black', (tester) async {
    await tester.pumpWidget(const PlanerkaApp());
    await tester.pumpAndSettle();

    final scaffold = tester.element(find.byType(Scaffold).last);
    expect(Theme.of(scaffold).brightness, Brightness.dark);
    expect(Theme.of(scaffold).scaffoldBackgroundColor, Colors.black);
  });

  testWidgets('capture explains its destination on a narrow accessible dock', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const PlanerkaApp());
    await tester.pumpAndSettle();

    final capture = find.byKey(const Key('center-action-button'));
    expect(tester.getSemantics(capture).label, 'Записать задачу в Inbox');
    expect(tester.getSize(capture).shortestSide, greaterThanOrEqualTo(48));
    for (final icon in [Icons.inbox_rounded, Icons.bolt_rounded]) {
      expect(
        tester
            .getRect(find.byIcon(icon).first)
            .overlaps(tester.getRect(capture)),
        isFalse,
        reason:
            'Capture ${tester.getRect(capture)} must leave navigation ${tester.getRect(find.byIcon(icon).first)} visible and tappable',
      );
    }
    await tester.tap(find.byIcon(Icons.inbox_rounded).first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await tester.tap(find.byIcon(Icons.bolt_rounded).first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    await tester.tap(capture);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick-capture-input')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('home quick capture saves directly to Inbox', (tester) async {
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Цветовая тема'), findsOneWidget);
    expect(find.byTooltip('Календарь'), findsOneWidget);
    expect(find.byTooltip('Проекты'), findsOneWidget);
    expect(find.byTooltip('Цели'), findsOneWidget);
    expect(find.byTooltip('Ещё'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('home-inbox-input')), 'Идея');
    await tester.tap(find.byKey(const Key('home-inbox-submit')));
    await tester.pumpAndSettle();

    final rows = await database.database.query('tasks');
    expect(rows, hasLength(1));
    expect(rows.single['title'], 'Идея');
    expect(rows.single['status'], 'inbox');
    expect(find.text('Идея'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      (tester.widget<NavigationBar>(find.byType(NavigationBar))).selectedIndex,
      0,
    );
  });

  testWidgets('center action opens quick capture and saves to Inbox', (
    tester,
  ) async {
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('center-action-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('center-action-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick-capture-input')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('quick-capture-input')),
      'Добавить шаг к цели',
    );
    await tester.tap(find.byKey(const Key('quick-capture-save')));
    await tester.pumpAndSettle();

    final rows = await database.database.query('tasks');
    expect(rows, hasLength(1));
    expect(rows.single['title'], 'Добавить шаг к цели');
    expect(rows.single['status'], 'inbox');
  });

  testWidgets('horizontal swipe changes page and selected navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nav-today')), findsOneWidget);
    final page = tester.getRect(find.byKey(const Key('main-page-view')));
    final gesture = await tester.startGesture(
      Offset(page.right - 8, page.center.dy),
    );
    await gesture.moveBy(Offset(-page.width * .7, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      (tester.widget<NavigationBar>(find.byType(NavigationBar))).selectedIndex,
      1,
    );
    expect(find.byKey(const Key('inbox-hero')), findsOneWidget);
  });

  testWidgets('sleep mode is available in the home quick menu', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ещё'));
    await tester.pumpAndSettle();
    expect(find.text('Режим сна'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sleep-mode-menu-item')));
    await tester.pumpAndSettle();

    final rows = await database.database.query(
      'app_metadata',
      where: 'key = ?',
      whereArgs: ['sleep_mode_enabled'],
    );
    expect(rows.single['value'], 'true');
  });

  testWidgets('progress tab opens the accountability screen', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('nav-progress')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Игровой прогресс'));
    await tester.pumpAndSettle();

    expect(find.text('Надёжность недели'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
  });
}
