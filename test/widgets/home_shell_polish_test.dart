import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/app.dart';
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/ai/model/model_screen.dart';
import 'package:planerka/features/goals/goals_screen.dart';
import 'package:planerka/features/planning/calendar_screen.dart';
import 'package:planerka/features/planning/projects_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_shell_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<void> openHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Ещё'));
    await tester.pumpAndSettle();
  }

  testWidgets('home title stays readable with two actions at 360dp', (
    tester,
  ) async {
    await openHome(tester);

    final bar = find.byType(AppBar);
    final title = find.descendant(of: bar, matching: find.text('Ритм дня'));
    final paragraph = tester.renderObject<RenderParagraph>(title);
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(tester.widget<AppBar>(bar).actions, hasLength(2));
    expect(find.byTooltip('Календарь'), findsOneWidget);
    expect(find.byTooltip('Ещё'), findsOneWidget);
    for (final tooltip in ['Цели', 'Проекты', 'Цветовая тема']) {
      expect(
        find.descendant(of: bar, matching: find.byTooltip(tooltip)),
        findsNothing,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('home overflow keeps secondary destinations discoverable', (
    tester,
  ) async {
    await openHome(tester);
    await openMenu(tester);

    expect(find.byKey(const Key('home-secondary-menu-sheet')), findsOneWidget);
    expect(find.byKey(const Key('secondary-menu-goals')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('secondary-menu-goals')),
        matching: find.byIcon(Icons.flag_rounded),
      ),
      findsOneWidget,
    );

    for (final label in [
      'Цели',
      'Проекты',
      'Тема',
      'ИИ',
      'Сон',
      'Привычки',
      'Дневник',
      'Данные',
    ]) {
      expect(find.text(label), findsAtLeastNWidgets(1));
    }
    final backupTile = find.byKey(const Key('secondary-menu-backup'));
    final backupTitle = tester.renderObject<RenderParagraph>(
      find.descendant(of: backupTile, matching: find.text('Данные')),
    );
    expect(backupTitle.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('branded menu tiles keep comfortable targets at 360dp', (
    tester,
  ) async {
    await openHome(tester);
    await openMenu(tester);

    final goalsTile = find.byKey(const Key('secondary-menu-goals'));
    expect(tester.getSize(goalsTile).shortestSide, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dock aligns labels and icons around a separate capture slot', (
    tester,
  ) async {
    await openHome(tester);
    final capture = tester.getRect(
      find.byKey(const Key('center-action-button')),
    );
    final destinations = <String, (String, IconData)>{
      'nav-today': ('Сегодня', Icons.wb_sunny_rounded),
      'nav-inbox': ('Входящие', Icons.inbox_rounded),
      'nav-focus': ('Фокус', Icons.bolt_rounded),
      'nav-progress': ('Прогресс', Icons.auto_graph_rounded),
    };
    for (final destination in destinations.entries) {
      final slot = find.byKey(Key(destination.key));
      final icon = find.descendant(
        of: slot,
        matching: find.byIcon(destination.value.$2),
      );
      final label = find.descendant(
        of: slot,
        matching: find.text(destination.value.$1),
      );
      expect(tester.getCenter(icon).dx, closeTo(tester.getCenter(label).dx, 1));
      expect(tester.getRect(slot).overlaps(capture), isFalse);
      expect(tester.getSize(slot).shortestSide, greaterThanOrEqualTo(48));
    }
    await tester.tap(find.byKey(const Key('nav-inbox')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Semantics>(find.byKey(const Key('nav-inbox')))
          .properties
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<Semantics>(find.byKey(const Key('nav-today')))
          .properties
          .selected,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  for (final destination in <String, Type>{
    'Цели': GoalsScreen,
    'Проекты': ProjectsScreen,
    'ИИ': ModelScreen,
  }.entries) {
    testWidgets('home overflow opens ${destination.key}', (tester) async {
      await openHome(tester);
      await openMenu(tester);
      await tester.tap(find.text(destination.key).last);
      // Model verification can keep an indeterminate progress indicator alive.
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 250));
      }

      expect(find.byType(destination.value), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('calendar remains a direct home action', (tester) async {
    await openHome(tester);
    await tester.tap(find.byTooltip('Календарь'));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme can still be changed from home overflow', (tester) async {
    await openHome(tester);
    await openMenu(tester);
    await tester.tap(find.byKey(const Key('secondary-menu-theme')));
    await tester.pumpAndSettle();

    expect(find.text('Светлая тема'), findsOneWidget);
    expect(find.text('Тёмная тема'), findsOneWidget);
    await tester.tap(find.text('Светлая тема'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(tester.takeException(), isNull);
  });
}
