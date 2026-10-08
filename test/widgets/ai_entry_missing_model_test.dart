import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/ai/model/local_ai_engine.dart';
import 'package:planerka/features/ai/planning/ai_recommendation_service.dart';
import 'package:planerka/features/goals/goals_screen.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/inbox/inbox_screen.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MissingModel implements AiTextGenerator {
  @override
  Future<String> generate(String prompt, {int maxTokens = 256}) =>
      Future.error(StateError('Verified local model is not installed'));
}

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_ai_entry_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('Inbox AI opens model recovery when the local model is missing', (
    tester,
  ) async {
    await InboxRepository(database).add('Синтетическая задача');
    var openedModel = false;
    await tester.pumpWidget(
      MaterialApp(
        home: InboxScreen(
          repository: InboxRepository(database),
          ai: AiRecommendationService(database, _MissingModel()),
          onModelRequired: () => openedModel = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-inbox-triage')));
    await tester.pumpAndSettle();

    expect(openedModel, isTrue);
    expect(find.textContaining('Verified local model'), findsNothing);
    expect((await database.database.query('tasks')).single['status'], 'inbox');
  });

  testWidgets('goal AI opens model recovery when the local model is missing', (
    tester,
  ) async {
    final planning = PlanningRepository(database);
    final goal = await planning.addGoal('Синтетическая цель');
    var openedModel = false;
    await tester.pumpWidget(
      MaterialApp(
        home: GoalsScreen(
          repository: planning,
          ai: AiRecommendationService(database, _MissingModel()),
          onModelRequired: () => openedModel = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('goal-ai-steps-${goal.id}')));
    await tester.pumpAndSettle();

    expect(openedModel, isTrue);
    expect(find.textContaining('Verified local model'), findsNothing);
    expect(await planning.goalTaskProgress(goal.id), (completed: 0, total: 0));
  });
}
