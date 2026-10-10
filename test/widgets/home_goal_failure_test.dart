import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/core/app_theme.dart';
import 'package:planerka/core/models.dart';
import 'package:planerka/features/gamification/gamification_service.dart';
import 'package:planerka/features/home/home_screen.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:planerka/features/wellbeing/wellbeing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_goal_error_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'goal progress read failure stays unavailable and retry loads real progress',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final planning = _FailOnceProgressRepository(database);
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
              onAiPlanning: () {},
              gamification: GamificationService(database),
              onGamification: () {},
              onModel: () {},
              onChooseGoal: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Цель для восстановления формы'), findsOneWidget);
      expect(
        find.byKey(const Key('home-goal-progress-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('home-goal-progress-retry')), findsOneWidget);
      expect(find.text('Добавь первый шаг к цели'), findsNothing);
      expect(find.text('0 из 0 шагов · 0%'), findsNothing);

      await tester.tap(find.byKey(const Key('home-goal-progress-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(
        find.byKey(const Key('home-goal-progress-unavailable')),
        findsNothing,
      );
      expect(find.text('2 из 5 шагов · 40%'), findsOneWidget);
      expect(planning.progressReads, 2);
    },
  );
}

class _FailOnceProgressRepository extends PlanningRepository {
  _FailOnceProgressRepository(super.database);

  static const goal = Goal(
    id: 'synthetic-primary-goal',
    title: 'Цель для восстановления формы',
    progress: 0,
  );

  int progressReads = 0;

  @override
  Future<List<Goal>> primaryGoals() async => [goal];

  @override
  Future<({int completed, int total})> goalTaskProgress(String goalId) async {
    progressReads++;
    if (progressReads == 1) {
      throw StateError('Synthetic progress read failure');
    }
    return (completed: 2, total: 5);
  }
}
