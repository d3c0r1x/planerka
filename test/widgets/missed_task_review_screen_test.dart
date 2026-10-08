import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/ai/model/local_ai_engine.dart';
import 'package:planerka/features/ai/review/missed_task_review_screen.dart';
import 'package:planerka/features/ai/review/missed_task_review_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  late _FakeGenerator generator;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('missed_review_widget_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    await database.database.insert('tasks', {
      'id': 'missed-1',
      'title': 'Отправить документы',
      'notes': '',
      'status': 'planned',
      'due_at': '2026-10-07T12:00:00.000Z',
      'created_at': '2026-10-06T10:00:00.000Z',
      'updated_at': '2026-10-06T10:00:00.000Z',
    });
    generator = _FakeGenerator();
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('missing local model opens the recovery action', (tester) async {
    generator.failure = StateError('Verified local model is not installed');
    var openedModel = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MissedTaskReviewScreen(
                    service: MissedTaskReviewService(
                      database,
                      generator,
                      now: () => DateTime(2026, 10, 8, 12),
                    ),
                    taskId: 'missed-1',
                    onModelRequired: () => openedModel = true,
                  ),
                ),
              ),
              child: const Text('Главная'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Главная'));
    await _pumpLoaded(tester);
    expect(
      find.text('Для интервью нужен установленный локальный ИИ.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Установить модель'));
    expect(openedModel, isTrue);
  });

  testWidgets(
    'only confirmed user-selected avoidable cause enters penalty flow',
    (tester) async {
      final confirmedCauses = <String>[];
      await _openReview(
        tester,
        _FakeReviewFlow(MissedTaskCause.externalObstacle),
        onConfirmPenalty: (taskId, cause) async {
          confirmedCauses.add('$taskId:${cause.name}');
        },
      );
      await _answerQuestions(tester);
      await tester.ensureVisible(
        find.byKey(const Key('missed-cause-avoidableDelay')),
      );
      await tester.tap(find.byKey(const Key('missed-cause-avoidableDelay')));
      await tester.ensureVisible(find.byKey(const Key('missed-review-apply')));
      await tester.tap(find.byKey(const Key('missed-review-apply')));
      await _pumpLoaded(tester);
      expect(find.text('Подтвердить ответственность?'), findsOneWidget);
      expect(confirmedCauses, isEmpty);

      await tester.tap(find.text('Подтвердить штраф'));
      await _pumpLoaded(tester);
      expect(confirmedCauses, ['missed-1:avoidableDelay']);
      expect(find.text('Начать'), findsOneWidget);
    },
  );

  testWidgets('AI cause alone cannot create a penalty', (tester) async {
    final confirmedCauses = <String>[];
    await _openReview(
      tester,
      _FakeReviewFlow(MissedTaskCause.avoidableDelay),
      onConfirmPenalty: (taskId, cause) async {
        confirmedCauses.add('$taskId:${cause.name}');
      },
    );
    await _answerQuestions(tester);

    await tester.ensureVisible(
      find.byKey(const Key('missed-cause-externalObstacle')),
    );
    await tester.tap(find.byKey(const Key('missed-cause-externalObstacle')));
    await tester.ensureVisible(find.byKey(const Key('missed-review-apply')));
    await tester.tap(find.byKey(const Key('missed-review-apply')));
    await _pumpLoaded(tester);

    expect(find.text('Подтвердить ответственность?'), findsNothing);
    expect(confirmedCauses, isEmpty);
    expect(find.text('Разбор пропуска'), findsNothing);
  });
}

Future<void> _openReview(
  WidgetTester tester,
  MissedTaskReviewFlow flow, {
  Future<void> Function(String taskId, MissedTaskCause cause)? onConfirmPenalty,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => MissedTaskReviewScreen(
                  service: flow,
                  taskId: 'missed-1',
                  onConfirmPenalty: onConfirmPenalty,
                ),
              ),
            ),
            child: const Text('Начать'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Начать'));
  await _pumpLoaded(tester);
}

class _FakeReviewFlow implements MissedTaskReviewFlow {
  _FakeReviewFlow(this.cause);

  final MissedTaskCause cause;

  @override
  Future<MissedTaskInterview> startInterview(String taskId) async =>
      const MissedTaskInterview(
        taskId: 'missed-1',
        taskTitle: 'Отправить документы',
        questions: ['Что помешало?', 'Что изменишь?'],
      );

  @override
  Future<MissedTaskProposal> analyzeAnswers(
    String taskId,
    List<MissedTaskAnswer> answers,
  ) async => MissedTaskProposal(
    id: 'proposal-1',
    taskId: taskId,
    cause: cause,
    explanation: 'Проверь предложенную причину.',
    actions: const [
      MissedTaskAction(
        type: MissedTaskActionType.discard,
        label: 'Убрать задачу',
      ),
    ],
  );

  @override
  Future<void> applyAction(
    MissedTaskProposal proposal,
    int actionIndex,
  ) async {}
}

Future<void> _answerQuestions(WidgetTester tester) async {
  for (var i = 0; i < 2; i++) {
    await tester.enterText(
      find.byKey(const Key('missed-review-answer')),
      'Ответ',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('missed-review-next')));
    await tester.tap(find.byKey(const Key('missed-review-next')));
    await _pumpLoaded(tester);
  }
}

Future<void> _pumpLoaded(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _FakeGenerator implements AiTextGenerator {
  final List<String> responses = [];
  Object? failure;
  @override
  Future<String> generate(String prompt, {int maxTokens = 256}) async {
    if (failure case final error?) throw error;
    return responses.removeAt(0);
  }
}
