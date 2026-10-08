import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/gamification/game_models.dart';
import 'package:planerka/features/gamification/gamification_service.dart';
import 'package:planerka/features/ai/review/missed_task_review_service.dart'
    show MissedTaskCause;
import 'package:planerka/core/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'dart:io';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase db;
  late GamificationService service;
  final now = DateTime(2026, 10, 8, 10);
  var idCounter = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('accountability_');
    db = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    idCounter = 0;
    service = GamificationService(
      db,
      now: () => now,
      newId: () => 'penalty-${idCounter++}',
    );
    await db.database.insert('tasks', {
      'id': 'task-1',
      'title': 'synthetic',
      'status': 'planned',
      'due_at': DateTime(2026, 10, 7).toUtc().toIso8601String(),
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    });
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'preview writes nothing; confirmed avoidable miss lowers weekly score once',
    () async {
      final proposal = await service.proposePenalty(
        'task-1',
        MissedTaskCause.avoidableDelay,
      );
      expect((await service.reliabilityForWeek(now)).score, 100);
      await service.confirmPenalty(proposal);
      await service.confirmPenalty(proposal);
      expect((await service.reliabilityForWeek(now)).score, 90);
      expect(
        (await service.accountabilityHistory()).single.taskTitle,
        'synthetic',
      );
    },
  );

  test('scheduled task is not missed until its estimated block ends', () async {
    await db.database.update(
      'tasks',
      {
        'due_at': null,
        'scheduled_at': DateTime(2026, 10, 8, 9, 55).toUtc().toIso8601String(),
        'estimated_minutes': 30,
      },
      where: 'id = ?',
      whereArgs: ['task-1'],
    );
    await expectLater(
      service.proposePenalty('task-1', MissedTaskCause.avoidableDelay),
      throwsStateError,
    );
  });

  test('excluded causes cannot be penalized', () async {
    for (final cause in [
      MissedTaskCause.externalObstacle,
      MissedTaskCause.estimateWrong,
      MissedTaskCause.priorityChanged,
    ]) {
      await expectLater(
        service.proposePenalty('task-1', cause),
        throwsStateError,
      );
    }
  });

  test(
    'caps at three per week, resets Monday, and recovery restores one',
    () async {
      for (var i = 0; i < 4; i++) {
        final id = 'extra-task-$i';
        await db.database.insert('tasks', {
          'id': id,
          'title': 'synthetic',
          'status': 'planned',
          'due_at': DateTime(2026, 10, 7).toUtc().toIso8601String(),
          'created_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
        });
        final proposal = await service.proposePenalty(
          id,
          MissedTaskCause.avoidableDelay,
        );
        if (i < 3) {
          await service.confirmPenalty(proposal);
        } else {
          await expectLater(service.confirmPenalty(proposal), throwsStateError);
        }
      }
      expect((await service.reliabilityForWeek(now)).score, 70);
      final event =
          (await db.database.query(
                'accountability_events',
                columns: ['id'],
                limit: 1,
              )).single['id']
              as String;
      await db.database.update(
        'tasks',
        {'status': 'completed'},
        where: 'id = ?',
        whereArgs: ['task-1'],
      );
      await service.resolvePenalty(event, 'task-1');
      expect((await service.reliabilityForWeek(now)).score, 80);
      final another =
          (await db.database.query(
                'accountability_events',
                columns: ['id'],
                where: 'id != ?',
                whereArgs: [event],
                limit: 1,
              )).single['id']
              as String;
      await expectLater(
        service.resolvePenalty(another, 'task-1'),
        throwsStateError,
      );
      expect(
        (await service.reliabilityForWeek(DateTime(2026, 10, 12))).score,
        100,
      );
    },
  );

  test(
    'disabled system and cancelled preview do not write; XP stays unchanged',
    () async {
      await service.setAccountabilityEnabled(false);
      await expectLater(
        service.proposePenalty('task-1', MissedTaskCause.avoidableDelay),
        throwsStateError,
      );
      expect(await db.database.query('accountability_events'), isEmpty);
      expect((await service.progress()).totalXp, 0);
      expect((await service.reliabilityForWeek(now)).score, 100);
    },
  );
}
