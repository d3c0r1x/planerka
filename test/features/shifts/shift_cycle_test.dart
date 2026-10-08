import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/shifts/shift_cycle.dart';
import 'package:planerka/features/shifts/shift_models.dart';

void main() {
  const phases = [
    ShiftPhase.day,
    ShiftPhase.day,
    ShiftPhase.preNightRest,
    ShiftPhase.night,
    ShiftPhase.night,
    ShiftPhase.recovery,
    ShiftPhase.rest,
    ShiftPhase.rest,
  ];
  final anchor = DateTime(2026, 10, 8);
  final settings = ShiftSettings(anchorDate: anchor);
  final team = ShiftTeam(
    id: 'team-a',
    name: 'Смена А',
    leaderName: 'Руководитель',
    colorValue: 0xFF66D8CE,
    phaseOffsetDays: 0,
    attends: true,
  );

  group('ShiftCycleCalculator', () {
    test('maps the complete eight day cycle', () {
      for (var index = 0; index < phases.length; index++) {
        expect(
          ShiftCycleCalculator.phaseAt(
            date: anchor.add(Duration(days: index)),
            anchorDate: anchor,
            phaseOffsetDays: 0,
          ),
          phases[index],
          reason: 'cycle day $index',
        );
      }
    });

    test('places four teams two cycle days apart', () {
      final expected = [
        ShiftPhase.day,
        ShiftPhase.preNightRest,
        ShiftPhase.night,
        ShiftPhase.rest,
      ];
      for (var index = 0; index < expected.length; index++) {
        expect(
          ShiftCycleCalculator.phaseAt(
            date: anchor,
            anchorDate: anchor,
            phaseOffsetDays: index * 2,
          ),
          expected[index],
        );
      }
    });

    test('uses floor modulo before the anchor across leap day and year', () {
      expect(
        ShiftCycleCalculator.phaseAt(
          date: DateTime(2024, 2, 29),
          anchorDate: DateTime(2024, 3, 1),
          phaseOffsetDays: 0,
        ),
        ShiftPhase.rest,
      );
      expect(
        ShiftCycleCalculator.phaseAt(
          date: DateTime(2026, 12, 29),
          anchorDate: DateTime(2027, 1, 1),
          phaseOffsetDays: 0,
        ),
        ShiftPhase.recovery,
      );
    });

    test('builds day shift and commute block at exact local times', () {
      final result = ShiftCycleCalculator.dayAt(
        date: anchor,
        anchorDate: anchor,
        team: team,
        settings: settings,
      );

      expect(result.phase, ShiftPhase.day);
      expect(result.workStart, DateTime(2026, 10, 8, 8));
      expect(result.workEnd, DateTime(2026, 10, 8, 20));
      expect(result.blockStart, DateTime(2026, 10, 8, 7));
      expect(result.blockEnd, DateTime(2026, 10, 8, 21, 30));
    });

    test('keeps night work and commute block on the following day', () {
      final result = ShiftCycleCalculator.dayAt(
        date: anchor.add(const Duration(days: 3)),
        anchorDate: anchor,
        team: team,
        settings: settings,
      );

      expect(result.phase, ShiftPhase.night);
      expect(result.workStart, DateTime(2026, 10, 11, 20));
      expect(result.workEnd, DateTime(2026, 10, 12, 8));
      expect(result.blockStart, DateTime(2026, 10, 11, 19));
      expect(result.blockEnd, DateTime(2026, 10, 12, 9, 30));
      expect(result.blockEnd!.isAfter(result.blockStart!), isTrue);
    });

    test('has no work block on pre night rest, recovery or rest', () {
      for (final index in [2, 5, 6, 7]) {
        final result = ShiftCycleCalculator.dayAt(
          date: anchor.add(Duration(days: index)),
          anchorDate: anchor,
          team: team,
          settings: settings,
        );
        expect(result.phase, phases[index]);
        expect(result.workStart, isNull);
        expect(result.workEnd, isNull);
        expect(result.blockStart, isNull);
        expect(result.blockEnd, isNull);
      }
    });

    test('range includes its start and excludes its end', () {
      final result = ShiftCycleCalculator.range(
        start: anchor,
        endExclusive: anchor.add(const Duration(days: 2)),
        anchorDate: anchor,
        teams: [team],
        settings: settings,
      );

      expect(result, hasLength(2));
      expect(result.map((day) => day.date), [
        anchor,
        anchor.add(const Duration(days: 1)),
      ]);
    });
  });
}
