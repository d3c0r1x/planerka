import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/app.dart';
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/gamification/gamification_screen.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:planerka/features/wellbeing/wellbeing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_home_entry_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'primary goal hero comes before the day summary without an AI claim',
    (tester) async {
      usePhoneViewport(tester);
      final planning = PlanningRepository(database);
      final goal = await planning.addGoal('Синтетическая главная цель');
      await planning.setPrimaryGoals({goal.id});

      await tester.pumpWidget(PlanerkaApp(database: database));
      await tester.pumpAndSettle();

      final hero = find.byKey(const Key('home-goal-hero'));
      expect(hero, findsOneWidget);
      expect(
        tester.getTopLeft(hero).dy,
        lessThan(tester.getTopLeft(find.text('Твой день, твой ритм')).dy),
        reason:
            'The main goal must lead the home screen before date/day summary.',
      );
      expect(
        tester.getTopLeft(hero).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('home-day-progress'))).dy,
        ),
      );
      expect(
        find.descendant(of: hero, matching: find.text('с ИИ')),
        findsNothing,
        reason: 'A saved goal alone does not prove AI planned its steps.',
      );
    },
  );

  testWidgets(
    'home AI plan shortcut opens model recovery when local model is absent',
    (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(PlanerkaApp(database: database));
      await tester.pumpAndSettle();

      final shortcut = find.byKey(const Key('home-ai-plan-shortcut'));
      expect(shortcut, findsOneWidget);
      await tester.tap(shortcut);
      for (var attempt = 0; attempt < 8; attempt++) {
        await tester.pump(const Duration(milliseconds: 250));
      }

      expect(find.text('Локальный ИИ'), findsOneWidget);
    },
  );

  testWidgets(
    'home game card shows real XP, level and habit streak, then opens rewards',
    (tester) async {
      usePhoneViewport(tester);
      final wellbeing = WellbeingRepository(database);
      final habit = await wellbeing.addHabit('Синтетическая привычка');
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      await wellbeing.checkIn(habit.id, yesterday);
      await wellbeing.checkIn(habit.id, today);

      await tester.pumpWidget(PlanerkaApp(database: database));
      await tester.pumpAndSettle();
      final gameCard = find.byKey(const Key('home-gamification-card'));
      expect(gameCard, findsOneWidget);
      await tester.scrollUntilVisible(
        gameCard,
        220,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('home-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Уровень 1'), findsOneWidget);
      expect(find.text('10 XP'), findsOneWidget);
      expect(find.textContaining('2 дня'), findsOneWidget);
      await tester.tap(gameCard);
      await tester.pumpAndSettle();

      expect(find.text('Игровой прогресс'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Мои награды'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(GamificationScreen),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            )
            .first,
      );
      expect(find.text('Мои награды'), findsOneWidget);
    },
  );
}
