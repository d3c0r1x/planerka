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

  testWidgets('home quick capture saves directly to Inbox', (tester) async {
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();

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

  testWidgets('horizontal swipe changes page and selected navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();

    await tester.fling(
      find.byKey(const Key('main-page-view')),
      const Offset(-180, 0),
      700,
    );
    await tester.pumpAndSettle();

    expect(
      (tester.widget<NavigationBar>(find.byType(NavigationBar))).selectedIndex,
      1,
    );
    expect(find.text('Inbox пуст. Добавьте любую мысль.'), findsOneWidget);
  });
}
