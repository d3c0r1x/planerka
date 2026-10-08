import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/ai/model/local_ai_engine.dart';
import 'package:planerka/features/ai/review/missed_task_review_service.dart';
import 'package:planerka/features/shifts/shift_models.dart';
import 'package:planerka/features/shifts/shift_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  late _FakeGenerator generator;
  late MissedTaskReviewService service;
  final now = DateTime(2026, 10, 8, 12);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('missed_review_');
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
    service = MissedTaskReviewService(database, generator, now: () => now);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  Future<void> insertScheduledTask(String id) async {
    await database.database.insert('tasks', {
      'id': id,
      'title': 'Занятый слот',
      'notes': '',
      'status': 'planned',
      'scheduled_at': DateTime(2026, 10, 9, 10, 15).toUtc().toIso8601String(),
      'estimated_minutes': 60,
      'created_at': '2026-10-06T10:00:00.000Z',
      'updated_at': '2026-10-06T10:00:00.000Z',
    });
  }

  test('rejects unknown, completed and not-yet-missed tasks', () async {
    await expectLater(service.startInterview('unknown'), throwsStateError);
    await database.database.update(
      'tasks',
      {'status': 'completed'},
      where: 'id = ?',
      whereArgs: ['missed-1'],
    );
    await expectLater(service.startInterview('missed-1'), throwsStateError);
    await database.database.update(
      'tasks',
      {'status': 'planned', 'due_at': '2026-10-09T12:00:00.000Z'},
      where: 'id = ?',
      whereArgs: ['missed-1'],
    );
    await expectLater(service.startInterview('missed-1'), throwsStateError);
  });

  test('validates two to four interview questions', () async {
    generator.response = jsonEncode({
      'questions': ['Что помешало?', 'Какой следующий шаг?'],
    });
    expect((await service.startInterview('missed-1')).questions, hasLength(2));
    generator.response = jsonEncode({
      'questions': ['один'],
    });
    await expectLater(
      service.startInterview('missed-1'),
      throwsFormatException,
    );
    generator.response = jsonEncode({'questions': List.filled(5, 'Вопрос?')});
    await expectLater(
      service.startInterview('missed-1'),
      throwsFormatException,
    );
  });

  test(
    'requires non-empty answers and validates typed proposal options',
    () async {
      await expectLater(
        service.analyzeAnswers('missed-1', const []),
        throwsArgumentError,
      );
      await expectLater(
        service.analyzeAnswers('missed-1', [
          const MissedTaskAnswer(question: 'Почему?', answer: ' '),
        ]),
        throwsArgumentError,
      );
      generator.response = jsonEncode({
        'cause': 'externalObstacle',
        'explanation': 'Возникла внешняя причина.',
        'actions': [
          {
            'type': 'reschedule',
            'label': 'Перенести',
            'scheduledAt': '2026-10-09T10:00:00',
            'durationMinutes': 30,
          },
          {
            'type': 'split',
            'label': 'Разделить',
            'followUpTitle': 'Подготовить один документ',
          },
          {
            'type': 'changeDeadline',
            'label': 'Новый срок',
            'dueAt': '2026-10-10T17:00:00',
          },
          {'type': 'discard', 'label': 'Убрать задачу'},
        ],
      });
      final proposal = await service.analyzeAnswers('missed-1', [
        const MissedTaskAnswer(question: 'Почему?', answer: 'Ждал справку'),
        const MissedTaskAnswer(
          question: 'Что дальше?',
          answer: 'Позвоню завтра',
        ),
      ]);
      expect(proposal.cause, MissedTaskCause.externalObstacle);
      expect(
        proposal.actions.map((action) => action.type),
        MissedTaskActionType.values,
      );
      expect(
        (await database.database.query(
          'tasks',
          where: 'id = ?',
          whereArgs: ['missed-1'],
        )).single['status'],
        'planned',
      );
    },
  );

  test('parses priority change and avoidable delay causes', () async {
    for (final cause in ['priorityChanged', 'avoidableDelay']) {
      generator.response = jsonEncode({
        'cause': cause,
        'explanation': 'Контекст изменился.',
        'actions': [
          {'type': 'discard', 'label': 'Убрать'},
        ],
      });
      expect(
        (await service.analyzeAnswers('missed-1', [
          const MissedTaskAnswer(question: 'Почему?', answer: 'Ответ'),
          const MissedTaskAnswer(question: 'Что дальше?', answer: 'Ответ'),
        ])).cause.name,
        cause,
      );
    }
  });

  test(
    'cancel leaves data unchanged and confirmed action applies once',
    () async {
      generator.response = jsonEncode({
        'cause': 'estimateWrong',
        'explanation': 'Нужен новый срок.',
        'actions': [
          {
            'type': 'changeDeadline',
            'label': 'Перенести срок',
            'dueAt': '2026-10-10T17:00:00',
          },
        ],
      });
      final proposal = await service.analyzeAnswers('missed-1', [
        const MissedTaskAnswer(question: 'Почему?', answer: 'Оценил неверно'),
        const MissedTaskAnswer(
          question: 'Что дальше?',
          answer: 'Возьму меньше',
        ),
      ]);
      final before = (await database.database.query(
        'tasks',
        where: 'id = ?',
        whereArgs: ['missed-1'],
      )).single['due_at'];
      expect(before, '2026-10-07T12:00:00.000Z');
      await service.applyAction(proposal, 0);
      final after = (await database.database.query(
        'tasks',
        where: 'id = ?',
        whereArgs: ['missed-1'],
      )).single['due_at'];
      expect(after, DateTime(2026, 10, 10, 17).toUtc().toIso8601String());
      await expectLater(service.applyAction(proposal, 0), throwsStateError);
    },
  );

  test('split clears the expired deadline and creates one follow-up', () async {
    generator.response = jsonEncode({
      'cause': 'estimateWrong',
      'explanation': 'Разбей на части.',
      'actions': [
        {
          'type': 'split',
          'label': 'Добавить шаг',
          'followUpTitle': 'Подготовить один документ',
        },
      ],
    });
    final proposal = await service.analyzeAnswers('missed-1', [
      const MissedTaskAnswer(question: 'Почему?', answer: 'Слишком много'),
      const MissedTaskAnswer(question: 'Что изменить?', answer: 'Разбить'),
    ]);
    await service.applyAction(proposal, 0);
    final parent = (await database.database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: ['missed-1'],
    )).single;
    expect(parent['due_at'], isNull);
    final child = await database.database.query(
      'tasks',
      where: 'parent_task_id = ?',
      whereArgs: ['missed-1'],
    );
    expect(child, hasLength(1));
    expect(child.single['title'], 'Подготовить один документ');
    await expectLater(service.applyAction(proposal, 0), throwsStateError);
    expect(
      await database.database.query(
        'tasks',
        where: 'parent_task_id = ?',
        whereArgs: ['missed-1'],
      ),
      hasLength(1),
    );
  });

  test('invalid proposal schema and expired dates are rejected', () async {
    generator.response = '{"cause":"madeUp","explanation":"x","actions":[]}';
    await expectLater(
      service.analyzeAnswers('missed-1', [
        const MissedTaskAnswer(question: 'Почему?', answer: 'Ответ'),
        const MissedTaskAnswer(question: 'Что дальше?', answer: 'Ответ'),
      ]),
      throwsFormatException,
    );
    generator.response = jsonEncode({
      'cause': 'externalObstacle',
      'explanation': 'Позже.',
      'actions': [
        {
          'type': 'reschedule',
          'label': 'Назначить',
          'scheduledAt': '2026-10-07T10:00:00',
          'durationMinutes': 30,
        },
      ],
    });
    await expectLater(
      service.analyzeAnswers('missed-1', [
        const MissedTaskAnswer(question: 'Почему?', answer: 'Ответ'),
        const MissedTaskAnswer(question: 'Что дальше?', answer: 'Ответ'),
      ]),
      throwsFormatException,
    );
  });

  test('rejects a reschedule overlapping another task block', () async {
    await insertScheduledTask('busy-task');
    _rescheduleResponse(generator);

    await expectLater(
      service.analyzeAnswers('missed-1', _answers),
      throwsStateError,
    );
  });

  test('rejects a reschedule overlapping an attended shift', () async {
    await ShiftRepository(database)
        .saveSchedule(ShiftSettings(anchorDate: DateTime(2026, 10, 9)), [
          _team('day', 0, true),
          _team('team-2', 2, false),
          _team('team-3', 4, false),
          _team('team-4', 6, false),
        ]);
    _rescheduleResponse(generator);

    await expectLater(
      service.analyzeAnswers('missed-1', _answers),
      throwsStateError,
    );
  });

  test(
    'rejects a reschedule that passes the current future deadline',
    () async {
      await database.database.update(
        'tasks',
        {'due_at': '2026-10-09T07:15:00.000Z'},
        where: 'id = ?',
        whereArgs: ['missed-1'],
      );
      _rescheduleResponse(generator);

      await expectLater(
        service.analyzeAnswers('missed-1', _answers),
        throwsStateError,
      );
    },
  );

  test('rejects stale proposal after schedule block changes', () async {
    _rescheduleResponse(generator);
    final proposal = await service.analyzeAnswers('missed-1', _answers);
    await database.database.update(
      'tasks',
      {
        'scheduled_at': '2026-10-09T15:00:00.000Z',
        'scheduled_date': '2026-10-09',
        'estimated_minutes': 90,
      },
      where: 'id = ?',
      whereArgs: ['missed-1'],
    );

    await expectLater(service.applyAction(proposal, 0), throwsStateError);
    final task = (await database.database.query(
      'tasks',
      where: 'id = ?',
      whereArgs: ['missed-1'],
    )).single;
    expect(task['scheduled_at'], '2026-10-09T15:00:00.000Z');
    expect(task['estimated_minutes'], 90);
  });

  test('rejects stale proposal after deadline changes', () async {
    _rescheduleResponse(generator);
    final proposal = await service.analyzeAnswers('missed-1', _answers);
    await database.database.update(
      'tasks',
      {'due_at': '2026-10-10T18:00:00.000Z'},
      where: 'id = ?',
      whereArgs: ['missed-1'],
    );

    await expectLater(service.applyAction(proposal, 0), throwsStateError);
    final task = (await database.database.query(
      'tasks',
      columns: ['due_at', 'scheduled_at'],
      where: 'id = ?',
      whereArgs: ['missed-1'],
    )).single;
    expect(task['due_at'], '2026-10-10T18:00:00.000Z');
    expect(task['scheduled_at'], isNull);
  });

  test('rechecks for a new conflicting task block when applying', () async {
    _rescheduleResponse(generator);
    final proposal = await service.analyzeAnswers('missed-1', _answers);
    await insertScheduledTask('new-busy-task');

    await expectLater(service.applyAction(proposal, 0), throwsStateError);
    final task = (await database.database.query(
      'tasks',
      columns: ['scheduled_at'],
      where: 'id = ?',
      whereArgs: ['missed-1'],
    )).single;
    expect(task['scheduled_at'], isNull);
  });
}

final _answers = [
  const MissedTaskAnswer(question: 'Почему?', answer: 'Не успел'),
  const MissedTaskAnswer(question: 'Что изменишь?', answer: 'Запланирую'),
];

void _rescheduleResponse(_FakeGenerator generator) {
  generator.response = jsonEncode({
    'cause': 'estimateWrong',
    'explanation': 'Найден свободный слот.',
    'actions': [
      {
        'type': 'reschedule',
        'label': 'Перенести',
        'scheduledAt': '2026-10-09T10:00:00',
        'durationMinutes': 30,
      },
    ],
  });
}

ShiftTeam _team(String id, int offset, bool attends) => ShiftTeam(
  id: id,
  name: id,
  leaderName: 'Руководитель $id',
  colorValue: 0xFF2196F3,
  phaseOffsetDays: offset,
  attends: attends,
);

class _FakeGenerator implements AiTextGenerator {
  String response = '';
  @override
  Future<String> generate(String prompt, {int maxTokens = 256}) async =>
      response;
}
