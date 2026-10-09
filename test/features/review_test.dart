import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/review/review_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  late ReviewService review;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_review_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    review = ReviewService(database);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('empty week returns zero counts and no goals', () async {
    final week = await review.week(DateTime(2026, 10, 7));
    expect(week.start, DateTime(2026, 10, 5));
    expect(week.endExclusive, DateTime(2026, 10, 12));
    expect(week.completedTasks, 0);
    expect(week.focusSessions, 0);
    expect(week.focusMinutes, 0);
    expect(week.habitCheckins, 0);
    expect(week.goals, isEmpty);
    expect(week.attendedShifts, 0);
    expect(week.missedShifts, 0);
    expect(week.reliabilityScore, 100);
    expect(week.moodRatingsCount, 0);
    expect(week.averageMood, isNull);
  });

  test(
    'period review summarizes mood scores without reading diary text',
    () async {
      final start = DateTime(2026, 10, 8).toUtc();
      final end = DateTime(2026, 10, 9).toUtc();
      Future<void> addEntry(String id, DateTime createdAt, int? mood) async {
        await database.database.insert('journal_entries', {
          'id': id,
          'text': 'Секретная заметка $id',
          'mood': mood,
          'created_at': createdAt.toIso8601String(),
        });
      }

      await addEntry('low', start.add(const Duration(hours: 2)), 2);
      await addEntry('high', start.add(const Duration(hours: 8)), 4);
      await addEntry('no-score', start.add(const Duration(hours: 10)), null);
      await addEntry('outside', end, 5);

      final day = await review.day(DateTime(2026, 10, 8));

      expect(day.moodRatingsCount, 2);
      expect(day.averageMood, 3);
    },
  );

  test('week includes start boundary and excludes following Monday', () async {
    await database.database.insert('tasks', {
      'id': 'monday',
      'title': 'Тест',
      'status': 'completed',
      'completed_at': '2026-10-05T00:00:00.000Z',
      'created_at': '2026-10-04T00:00:00.000Z',
      'updated_at': '2026-10-05T00:00:00.000Z',
    });
    await database.database.insert('tasks', {
      'id': 'next-monday',
      'title': 'Тест',
      'status': 'completed',
      'completed_at': '2026-10-12T00:00:00.000Z',
      'created_at': '2026-10-11T00:00:00.000Z',
      'updated_at': '2026-10-12T00:00:00.000Z',
    });
    expect((await review.week(DateTime(2026, 10, 8))).completedTasks, 1);
  });

  test(
    'week reports shift attendance and reliability without diary influence',
    () async {
      await database.database.insert('shift_teams', {
        'id': 'team-a',
        'name': 'Смена А',
        'leader_name': 'Тест',
        'color_value': 0xFF123456,
        'phase_offset_days': 0,
        'attends': 1,
      });
      await database.database.insert('shift_attendance', {
        'team_id': 'team-a',
        'date': '2026-10-05',
        'status': 'attended',
      });
      await database.database.insert('shift_attendance', {
        'team_id': 'team-a',
        'date': '2026-10-11',
        'status': 'missed',
      });
      await database.database.insert('shift_attendance', {
        'team_id': 'team-a',
        'date': '2026-10-12',
        'status': 'missed',
      });
      await database.database.insert('tasks', {
        'id': 'task',
        'title': 'Тест',
        'status': 'planned',
        'created_at': '2026-10-05T00:00:00.000Z',
        'updated_at': '2026-10-05T00:00:00.000Z',
      });
      await database.database.insert('accountability_events', {
        'id': 'penalty',
        'task_id': 'task',
        'week_start': '2026-10-05',
        'cause': 'avoidableDelay',
        'points': 10,
        'status': 'confirmed',
        'created_at': '2026-10-08T09:00:00.000Z',
      });
      final week = await review.week(DateTime(2026, 10, 5));
      expect(week.attendedShifts, 1);
      expect(week.missedShifts, 1);
      expect(week.reliabilityScore, 90);
    },
  );

  test('day attendance excludes records outside selected date', () async {
    await database.database.insert('shift_teams', {
      'id': 'team-a',
      'name': 'Смена А',
      'leader_name': 'Тест',
      'color_value': 0xFF123456,
      'phase_offset_days': 0,
      'attends': 1,
    });
    await database.database.insert('shift_attendance', {
      'team_id': 'team-a',
      'date': '2026-10-08',
      'status': 'attended',
    });
    await database.database.insert('shift_attendance', {
      'team_id': 'team-a',
      'date': '2026-10-09',
      'status': 'missed',
    });

    final day = await review.day(DateTime(2026, 10, 8));
    expect(day.attendedShifts, 1);
    expect(day.missedShifts, 0);
    expect(day.reliabilityScore, 100);
  });

  test(
    'partial focus uses actual elapsed minutes and includes habits and goals',
    () async {
      await database.database.insert('timer_sessions', {
        'id': 'partial',
        'kind': 'focus',
        'duration_seconds': 2700,
        'started_at': '2026-10-08T09:00:00.000Z',
        'status': 'completed',
        'elapsed_seconds': 615,
        'remaining_seconds': 0,
      });
      await database.database.insert('habits', {
        'id': 'habit',
        'title': 'Тест',
        'target_per_week': 2,
        'created_at': '2026-10-01T00:00:00.000Z',
      });
      await database.database.insert('habit_logs', {
        'id': 'log',
        'habit_id': 'habit',
        'date': '2026-10-08',
        'value': 1,
        'created_at': '2026-10-08T09:00:00.000Z',
      });
      await database.database.insert('goals', {
        'id': 'goal',
        'title': 'Тест',
        'progress': 4.0,
        'target': 10.0,
        'unit': 'шагов',
        'created_at': '2026-10-01T00:00:00.000Z',
        'updated_at': '2026-10-08T09:00:00.000Z',
      });
      final day = await review.day(DateTime(2026, 10, 8));
      expect(day.focusSessions, 1);
      expect(day.focusMinutes, 10);
      expect(day.habitCheckins, 1);
      expect(day.goals.single.progressPercent, 40);
    },
  );
}
