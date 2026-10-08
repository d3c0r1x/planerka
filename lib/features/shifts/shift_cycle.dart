import 'shift_models.dart';

class ShiftCycleCalculator {
  const ShiftCycleCalculator._();

  static const int cycleLengthDays = 8;
  static const List<ShiftPhase> _phases = [
    ShiftPhase.day,
    ShiftPhase.day,
    ShiftPhase.preNightRest,
    ShiftPhase.night,
    ShiftPhase.night,
    ShiftPhase.recovery,
    ShiftPhase.rest,
    ShiftPhase.rest,
  ];

  /// Positive offsets advance a team's phase from the anchor team; +2 is the
  /// pre-night rest phase on the anchor date.
  static ShiftPhase phaseAt({
    required DateTime date,
    required DateTime anchorDate,
    required int phaseOffsetDays,
  }) {
    final dateOrdinal = DateTime.utc(date.year, date.month, date.day);
    final anchorOrdinal = DateTime.utc(
      anchorDate.year,
      anchorDate.month,
      anchorDate.day,
    );
    final elapsedDays = dateOrdinal.difference(anchorOrdinal).inDays;
    final cycleIndex = (elapsedDays + phaseOffsetDays) % cycleLengthDays;
    return _phases[cycleIndex < 0 ? cycleIndex + cycleLengthDays : cycleIndex];
  }

  static ShiftDayStatus dayAt({
    required DateTime date,
    required DateTime anchorDate,
    required ShiftTeam team,
    required ShiftSettings settings,
  }) {
    final localDate = DateTime(date.year, date.month, date.day);
    final phase = phaseAt(
      date: localDate,
      anchorDate: anchorDate,
      phaseOffsetDays: team.phaseOffsetDays,
    );

    DateTime? workStart;
    DateTime? workEnd;
    if (phase == ShiftPhase.day) {
      workStart = DateTime(localDate.year, localDate.month, localDate.day, 8);
      workEnd = DateTime(localDate.year, localDate.month, localDate.day, 20);
    } else if (phase == ShiftPhase.night) {
      workStart = DateTime(localDate.year, localDate.month, localDate.day, 20);
      workEnd = DateTime(localDate.year, localDate.month, localDate.day + 1, 8);
    }

    return ShiftDayStatus(
      date: localDate,
      teamId: team.id,
      phase: phase,
      workStart: workStart,
      workEnd: workEnd,
      blockStart: workStart?.subtract(
        Duration(minutes: settings.commuteBeforeMinutes),
      ),
      blockEnd: workEnd?.add(Duration(minutes: settings.commuteAfterMinutes)),
    );
  }

  static List<ShiftDayStatus> range({
    required DateTime start,
    required DateTime endExclusive,
    required DateTime anchorDate,
    required List<ShiftTeam> teams,
    required ShiftSettings settings,
  }) {
    final result = <ShiftDayStatus>[];
    var date = DateTime(start.year, start.month, start.day);
    final end = DateTime(
      endExclusive.year,
      endExclusive.month,
      endExclusive.day,
    );
    while (date.isBefore(end)) {
      for (final team in teams) {
        result.add(
          dayAt(
            date: date,
            anchorDate: anchorDate,
            team: team,
            settings: settings,
          ),
        );
      }
      date = DateTime(date.year, date.month, date.day + 1);
    }
    return result;
  }
}
