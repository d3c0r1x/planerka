import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/shifts/shift_models.dart';
import 'package:planerka/features/shifts/shift_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  late ShiftRepository repository;

  final anchor = DateTime(2026, 10, 8);
  final settings = ShiftSettings(anchorDate: anchor);
  final teams = [
    _team('a', 0),
    _team('b', 2),
    _team('c', 4),
    _team('d', 6, attends: false),
  ];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_shifts_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    repository = ShiftRepository(database);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('saves four teams, settings and selected attendance teams', () async {
    await repository.saveSchedule(settings, teams);

    final loaded = await repository.loadSettings();
    expect(loaded?.anchorDate, anchor);
    expect(loaded?.commuteBeforeMinutes, 60);
    expect(loaded?.commuteAfterMinutes, 90);
    final loadedTeams = await repository.listTeams();
    expect(loadedTeams.map((team) => team.id), ['a', 'b', 'c', 'd']);
    expect(loadedTeams.where((team) => team.attends), hasLength(3));
  });

  test(
    'rejects duplicate IDs and invalid offsets without partial writes',
    () async {
      await expectLater(
        repository.saveSchedule(settings, [
          _team('same', 0),
          _team('same', 2),
          _team('c', 4),
          _team('d', 6),
        ]),
        throwsArgumentError,
      );
      await expectLater(
        repository.saveSchedule(settings, [
          _team('a', 0),
          _team('b', 2),
          _team('c', 4),
          _team('d', 4),
        ]),
        throwsArgumentError,
      );
      expect(await repository.listTeams(), isEmpty);
      expect(await repository.loadSettings(), isNull);
    },
  );

  test('re-saving known teams preserves overrides and attendance', () async {
    await repository.saveSchedule(settings, teams);
    await repository.setAttendance('a', anchor, ShiftAttendance.attended);
    await repository.setDayOverride(
      ShiftOverride(teamId: 'a', date: anchor, phase: ShiftPhase.rest),
    );

    await repository.saveSchedule(
      settings,
      teams
          .map(
            (team) =>
                _team(team.id, team.phaseOffsetDays, attends: team.attends),
          )
          .toList(),
    );

    expect(
      (await repository.calendar(
        anchor,
        anchor.add(const Duration(days: 1)),
      )).first.phase,
      ShiftPhase.rest,
    );
    expect(
      await repository.attendanceFor('a', anchor),
      ShiftAttendance.attended,
    );
  });

  test(
    'one date override changes only that date and derives commute block',
    () async {
      await repository.saveSchedule(settings, teams);
      await repository.setDayOverride(
        ShiftOverride(
          teamId: 'a',
          date: anchor.add(const Duration(days: 1)),
          phase: ShiftPhase.night,
        ),
      );

      final result = await repository.calendar(
        anchor,
        anchor.add(const Duration(days: 3)),
      );
      final dayOne = result.firstWhere(
        (day) => day.date.day == 8 && day.teamId == 'a',
      );
      final dayTwo = result.firstWhere(
        (day) => day.date.day == 9 && day.teamId == 'a',
      );

      expect(dayOne.phase, ShiftPhase.day);
      expect(dayTwo.phase, ShiftPhase.night);
      expect(dayTwo.workStart, DateTime(2026, 10, 9, 20));
      expect(dayTwo.workEnd, DateTime(2026, 10, 10, 8));
      expect(dayTwo.blockStart, DateTime(2026, 10, 9, 19));
      expect(dayTwo.blockEnd, DateTime(2026, 10, 10, 9, 30));
    },
  );

  test(
    'custom shift time and cancelled date are applied after the cycle',
    () async {
      await repository.saveSchedule(settings, teams);
      await repository.setDayOverride(
        ShiftOverride(
          teamId: 'a',
          date: anchor,
          phase: ShiftPhase.day,
          workStart: DateTime(2026, 10, 8, 9),
          workEnd: DateTime(2026, 10, 8, 21),
        ),
      );
      await repository.setDayOverride(
        ShiftOverride(
          teamId: 'a',
          date: anchor.add(const Duration(days: 1)),
          phase: ShiftPhase.day,
          cancelled: true,
        ),
      );

      final result = await repository.calendar(
        anchor,
        anchor.add(const Duration(days: 2)),
      );
      final custom = result.firstWhere(
        (day) => day.date.day == 8 && day.teamId == 'a',
      );
      final cancelled = result.firstWhere(
        (day) => day.date.day == 9 && day.teamId == 'a',
      );

      expect(custom.workStart, DateTime(2026, 10, 8, 9));
      expect(custom.blockStart, DateTime(2026, 10, 8, 8));
      expect(custom.blockEnd, DateTime(2026, 10, 8, 22, 30));
      expect(cancelled.cancelled, isTrue);
      expect(cancelled.workStart, isNull);
      expect(cancelled.blockStart, isNull);
    },
  );

  test('adjustment applies from its effective date into the future', () async {
    await repository.saveSchedule(settings, teams);
    await repository.adjustFrom(
      ShiftPhaseAdjustment(
        teamId: 'a',
        effectiveDate: anchor.add(const Duration(days: 2)),
        deltaDays: 1,
      ),
    );

    final result = await repository.calendar(
      anchor,
      anchor.add(const Duration(days: 4)),
    );
    final byDay = {
      for (final day in result.where((day) => day.teamId == 'a'))
        day.date.day: day,
    };
    expect(byDay[9]!.phase, ShiftPhase.day);
    expect(byDay[10]!.phase, ShiftPhase.night);
    expect(byDay[11]!.phase, ShiftPhase.night);
  });

  test(
    'attendance writes are idempotent and calendar includes all teams',
    () async {
      await repository.saveSchedule(settings, teams);
      await repository.setAttendance('a', anchor, ShiftAttendance.attended);
      await repository.setAttendance('a', anchor, ShiftAttendance.missed);

      expect(
        await repository.attendanceFor('a', anchor),
        ShiftAttendance.missed,
      );
      expect(
        await repository.calendar(anchor, anchor.add(const Duration(days: 1))),
        hasLength(4),
      );
    },
  );
}

ShiftTeam _team(String id, int offset, {bool attends = true}) => ShiftTeam(
  id: id,
  name: 'Смена $id',
  leaderName: 'Руководитель $id',
  colorValue: 0xFF66D8CE,
  phaseOffsetDays: offset,
  attends: attends,
);
