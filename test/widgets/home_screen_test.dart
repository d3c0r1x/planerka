import 'package:flutter/material.dart';

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/app.dart';
import 'package:planerka/core/app_database.dart';
import 'package:planerka/core/app_theme.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/home/home_screen.dart';
import 'package:planerka/features/planning/planning_repository.dart';
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
    expect(find.byKey(const Key('home-goal-hero')), findsOneWidget);
    expect(find.byKey(const Key('home-today-section')), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('home-today-section'))).dy,
      lessThan(640),
    );
    expect(find.text('Inbox'), findsAtLeastNWidgets(1));
    expect(find.text('Таймер'), findsOneWidget);
    expect(find.text('Привычки'), findsOneWidget);
    expect(find.text('Дневник'), findsOneWidget);
  });

  test('dark surfaces use layered charcoal over a black canvas', () {
    final theme = AppTheme.dark();
    expect(theme.colorScheme.surface, const Color(0xFF000000));
    expect(theme.colorScheme.surfaceContainerLow, const Color(0xFF10131B));
    expect(theme.colorScheme.surfaceContainer, const Color(0xFF171C27));
  });

  testWidgets('home has one scroll and honest completion on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final inbox = InboxRepository(database);
    final planning = PlanningRepository(database);
    final done = await inbox.add('Готовый шаг');
    await inbox.triage(done.id, TaskDisposition.quick);
    await planning.complete(done.id);
    final pending = await inbox.add(
      'Подготовить подробный план следующей недели',
    );
    await inbox.triage(pending.id, TaskDisposition.quick);
    final backlog = await inbox.add('Идея на потом');
    await inbox.triage(backlog.id, TaskDisposition.planned);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: HomeScreen(
            planning: planning,
            wellbeing: WellbeingRepository(database),
            onInbox: () {},
            onFocus: () {},
            onHabits: () {},
            onJournal: () {},
            onQuickCapture: (_) async {},
            onModel: () {},
            onChooseGoal: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.byKey(const Key('home-goal-hero')),
        matching: find.byType(ListView),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
      findsOneWidget,
    );
    expect(find.text('1 из 2 выполнено'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byTooltip('Завершить').first,
      220,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.tap(find.byTooltip('Завершить').first);
    await tester.pumpAndSettle();
    expect(find.text('2 из 2 выполнено'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byTooltip('Действия задачи').first,
      220,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.tap(find.byTooltip('Действия задачи').first);
    await tester.pumpAndSettle();
    expect(find.text('Напомнить'), findsOneWidget);
    expect(find.text('Назначить срок'), findsOneWidget);
    expect(find.text('Запланировать время'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home keeps horizontal page swipes with one vertical scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(PlanerkaApp(database: database));
    await tester.pumpAndSettle();
    final page = tester.getRect(find.byKey(const Key('main-page-view')));
    final gesture = await tester.startGesture(
      Offset(page.right - 8, page.center.dy),
    );
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(Offset(-page.width * .2, 0));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });
}
