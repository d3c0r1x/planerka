enum ShiftPhase { day, preNightRest, night, recovery, rest }

class ShiftTeam {
  const ShiftTeam({
    required this.id,
    required this.name,
    required this.leaderName,
    required this.colorValue,
    required this.phaseOffsetDays,
    required this.attends,
  });

  final String id;
  final String name;
  final String leaderName;
  final int colorValue;
  final int phaseOffsetDays;
  final bool attends;
}

class ShiftSettings {
  const ShiftSettings({
    required this.anchorDate,
    this.commuteBeforeMinutes = 60,
    this.commuteAfterMinutes = 90,
    this.reminderLeadMinutes = 30,
  });

  final DateTime anchorDate;
  final int commuteBeforeMinutes;
  final int commuteAfterMinutes;
  final int reminderLeadMinutes;
}

class ShiftDayStatus {
  const ShiftDayStatus({
    required this.date,
    required this.teamId,
    required this.phase,
    this.workStart,
    this.workEnd,
    this.blockStart,
    this.blockEnd,
  });

  final DateTime date;
  final String teamId;
  final ShiftPhase phase;
  final DateTime? workStart;
  final DateTime? workEnd;
  final DateTime? blockStart;
  final DateTime? blockEnd;
}

class ShiftOverride {
  const ShiftOverride({
    required this.teamId,
    required this.date,
    required this.phase,
    this.workStart,
    this.workEnd,
    this.cancelled = false,
  });

  final String teamId;
  final DateTime date;
  final ShiftPhase phase;
  final DateTime? workStart;
  final DateTime? workEnd;
  final bool cancelled;
}

class ShiftPhaseAdjustment {
  const ShiftPhaseAdjustment({
    required this.teamId,
    required this.effectiveDate,
    required this.deltaDays,
  });

  final String teamId;
  final DateTime effectiveDate;
  final int deltaDays;
}

enum ShiftAttendance { attended, missed }
