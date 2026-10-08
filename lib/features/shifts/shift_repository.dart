import 'package:sqflite_common/sqlite_api.dart';

import '../../core/app_database.dart';
import 'shift_cycle.dart';
import 'shift_models.dart';

class ShiftRepository {
  ShiftRepository(this.database, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase database;
  final DateTime Function() _now;

  Future<void> saveSchedule(
    ShiftSettings settings,
    List<ShiftTeam> teams,
  ) async {
    _validateSchedule(settings, teams);
    await database.database.transaction((tx) async {
      final incomingIds = teams.map((team) => team.id).toSet();
      final existingRows = await tx.query('shift_teams', columns: ['id']);
      for (final row in existingRows) {
        final id = row['id'] as String;
        if (!incomingIds.contains(id)) {
          await tx.delete('shift_teams', where: 'id = ?', whereArgs: [id]);
        }
      }

      for (final team in teams) {
        final values = <String, Object?>{
          'name': team.name.trim(),
          'leader_name': team.leaderName.trim(),
          'color_value': team.colorValue,
          'phase_offset_days': team.phaseOffsetDays,
          'attends': team.attends ? 1 : 0,
        };
        final existing = await tx.query(
          'shift_teams',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [team.id],
          limit: 1,
        );
        if (existing.isEmpty) {
          await tx.insert('shift_teams', {'id': team.id, ...values});
        } else {
          await tx.update(
            'shift_teams',
            values,
            where: 'id = ?',
            whereArgs: [team.id],
          );
        }
      }

      await tx.insert('shift_settings', {
        'id': 1,
        'anchor_date': _day(settings.anchorDate),
        'commute_before_minutes': settings.commuteBeforeMinutes,
        'commute_after_minutes': settings.commuteAfterMinutes,
        'reminder_lead_minutes': settings.reminderLeadMinutes,
        'updated_at': _now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<ShiftSettings?> loadSettings() async {
    final rows = await database.database.query(
      'shift_settings',
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return ShiftSettings(
      anchorDate: DateTime.parse(row['anchor_date'] as String),
      commuteBeforeMinutes: row['commute_before_minutes'] as int,
      commuteAfterMinutes: row['commute_after_minutes'] as int,
      reminderLeadMinutes: row['reminder_lead_minutes'] as int,
    );
  }

  Future<List<ShiftTeam>> listTeams() async {
    final rows = await database.database.query(
      'shift_teams',
      orderBy: 'phase_offset_days',
    );
    return rows
        .map(
          (row) => ShiftTeam(
            id: row['id'] as String,
            name: row['name'] as String,
            leaderName: row['leader_name'] as String,
            colorValue: row['color_value'] as int,
            phaseOffsetDays: row['phase_offset_days'] as int,
            attends: (row['attends'] as int) == 1,
          ),
        )
        .toList();
  }

  Future<void> setDayOverride(ShiftOverride value) async {
    await _requireTeam(value.teamId);
    if ((value.workStart == null) != (value.workEnd == null)) {
      throw ArgumentError('Укажите начало и конец смены вместе');
    }
    if (value.workStart != null && !value.workEnd!.isAfter(value.workStart!)) {
      throw ArgumentError('Конец смены должен быть позже начала');
    }
    await database.database.insert('shift_overrides', {
      'team_id': value.teamId,
      'date': _day(value.date),
      'phase': value.phase.name,
      'work_start': value.workStart?.toIso8601String(),
      'work_end': value.workEnd?.toIso8601String(),
      'cancelled': value.cancelled ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> adjustFrom(ShiftPhaseAdjustment value) async {
    await _requireTeam(value.teamId);
    await database.database.insert('shift_adjustments', {
      'team_id': value.teamId,
      'effective_date': _day(value.effectiveDate),
      'delta_days': value.deltaDays,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setAttendance(
    String teamId,
    DateTime date,
    ShiftAttendance value,
  ) async {
    await _requireTeam(teamId);
    await database.database.insert('shift_attendance', {
      'team_id': teamId,
      'date': _day(date),
      'status': value.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<ShiftAttendance?> attendanceFor(String teamId, DateTime date) async {
    final rows = await database.database.query(
      'shift_attendance',
      columns: ['status'],
      where: 'team_id = ? AND date = ?',
      whereArgs: [teamId, _day(date)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ShiftAttendance.values.byName(rows.single['status'] as String);
  }

  Future<List<ShiftDayStatus>> calendar(
    DateTime start,
    DateTime endExclusive,
  ) async {
    final settings = await loadSettings();
    if (settings == null) return const [];
    final teams = await listTeams();
    if (teams.isEmpty) return const [];

    var date = DateTime(start.year, start.month, start.day);
    final end = DateTime(
      endExclusive.year,
      endExclusive.month,
      endExclusive.day,
    );
    if (!date.isBefore(end)) return const [];

    final overrides = await database.database.query(
      'shift_overrides',
      where: 'date >= ? AND date < ?',
      whereArgs: [_day(date), _day(end)],
    );
    final overrideByKey = {
      for (final row in overrides)
        _overrideKey(row['team_id'] as String, row['date'] as String): row,
    };
    final adjustmentRows = await database.database.query(
      'shift_adjustments',
      where: 'effective_date < ?',
      whereArgs: [_day(end)],
      orderBy: 'effective_date',
    );
    final adjustments = <String, List<Map<String, Object?>>>{};
    for (final row in adjustmentRows) {
      adjustments.putIfAbsent(row['team_id'] as String, () => []).add(row);
    }

    final result = <ShiftDayStatus>[];
    while (date.isBefore(end)) {
      final dateKey = _day(date);
      for (final team in teams) {
        final applicable = adjustments[team.id]
            ?.where(
              (row) =>
                  (row['effective_date'] as String).compareTo(dateKey) <= 0,
            )
            .toList();
        final delta = applicable == null || applicable.isEmpty
            ? 0
            : applicable.last['delta_days'] as int;
        final shiftedTeam = delta == 0
            ? team
            : ShiftTeam(
                id: team.id,
                name: team.name,
                leaderName: team.leaderName,
                colorValue: team.colorValue,
                phaseOffsetDays: team.phaseOffsetDays + delta,
                attends: team.attends,
              );
        final base = ShiftCycleCalculator.dayAt(
          date: date,
          anchorDate: settings.anchorDate,
          team: shiftedTeam,
          settings: settings,
        );
        final override = overrideByKey[_overrideKey(team.id, dateKey)];
        result.add(
          override == null ? base : _applyOverride(base, override, settings),
        );
      }
      date = DateTime(date.year, date.month, date.day + 1);
    }
    return result;
  }

  Future<void> _requireTeam(String teamId) async {
    final rows = await database.database.query(
      'shift_teams',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [teamId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Смена больше не существует');
  }

  ShiftDayStatus _applyOverride(
    ShiftDayStatus base,
    Map<String, Object?> row,
    ShiftSettings settings,
  ) {
    final phase = ShiftPhase.values.byName(row['phase'] as String);
    final cancelled = (row['cancelled'] as int) == 1;
    final customStart = row['work_start'] == null
        ? null
        : DateTime.parse(row['work_start'] as String);
    final customEnd = row['work_end'] == null
        ? null
        : DateTime.parse(row['work_end'] as String);
    final defaultRange = _defaultWorkRange(base.date, phase);
    final workStart = cancelled ? null : customStart ?? defaultRange.$1;
    final workEnd = cancelled ? null : customEnd ?? defaultRange.$2;
    return ShiftDayStatus(
      date: base.date,
      teamId: base.teamId,
      phase: phase,
      workStart: workStart,
      workEnd: workEnd,
      blockStart: workStart?.subtract(
        Duration(minutes: settings.commuteBeforeMinutes),
      ),
      blockEnd: workEnd?.add(Duration(minutes: settings.commuteAfterMinutes)),
      cancelled: cancelled,
    );
  }

  (DateTime?, DateTime?) _defaultWorkRange(DateTime date, ShiftPhase phase) {
    return switch (phase) {
      ShiftPhase.day => (
        DateTime(date.year, date.month, date.day, 8),
        DateTime(date.year, date.month, date.day, 20),
      ),
      ShiftPhase.night => (
        DateTime(date.year, date.month, date.day, 20),
        DateTime(date.year, date.month, date.day + 1, 8),
      ),
      _ => (null, null),
    };
  }

  void _validateSchedule(ShiftSettings settings, List<ShiftTeam> teams) {
    if (teams.length != 4) {
      throw ArgumentError.value(
        teams.length,
        'teams',
        'Нужно указать четыре смены',
      );
    }
    final ids = teams.map((team) => team.id).toSet();
    if (ids.length != teams.length ||
        teams.any((team) => team.id.trim().isEmpty)) {
      throw ArgumentError('У смен должны быть уникальные ID');
    }
    final offsets = teams.map((team) => team.phaseOffsetDays).toSet();
    if (offsets.length != 4 || !offsets.containsAll([0, 2, 4, 6])) {
      throw ArgumentError('Смещения смен должны быть 0, 2, 4 и 6 дней');
    }
    if (teams.any(
      (team) =>
          team.name.trim().isEmpty ||
          team.leaderName.trim().isEmpty ||
          team.colorValue < 0 ||
          team.colorValue > 0xFFFFFFFF,
    )) {
      throw ArgumentError('Укажите название, руководителя и корректный цвет');
    }
    if (settings.commuteBeforeMinutes < 0 ||
        settings.commuteAfterMinutes < 0 ||
        settings.reminderLeadMinutes < 0) {
      throw ArgumentError('Интервалы времени не могут быть отрицательными');
    }
  }

  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _overrideKey(String teamId, String date) => '$teamId\u0000$date';
}
