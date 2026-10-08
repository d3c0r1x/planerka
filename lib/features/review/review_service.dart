import '../../core/app_database.dart';

class GoalProgress {
  const GoalProgress({
    required this.title,
    required this.progress,
    this.target,
    this.unit = '',
  });
  final String title;
  final double progress;
  final double? target;
  final String unit;

  double? get progressPercent => target == null || target == 0
      ? null
      : (progress / target! * 100).clamp(0, 100);
}

class PeriodReview {
  const PeriodReview({
    required this.start,
    required this.endExclusive,
    required this.completedTasks,
    required this.focusSessions,
    required this.focusMinutes,
    required this.habitCheckins,
    required this.goals,
    this.attendedShifts = 0,
    this.missedShifts = 0,
    this.reliabilityScore,
  });

  final DateTime start;
  final DateTime endExclusive;
  final int completedTasks;
  final int focusSessions;
  final int focusMinutes;
  final int habitCheckins;
  final List<GoalProgress> goals;
  final int attendedShifts;
  final int missedShifts;
  final int? reliabilityScore;
}

class ReviewService {
  ReviewService(this.database);
  final AppDatabase database;

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  Future<PeriodReview> day(DateTime date) async {
    final start = _dateOnly(date);
    return _period(start, start.add(const Duration(days: 1)));
  }

  Future<PeriodReview> week(DateTime date) async {
    final selected = _dateOnly(date);
    final monday = selected.subtract(Duration(days: selected.weekday - 1));
    return _period(monday, monday.add(const Duration(days: 7)));
  }

  Future<PeriodReview> _period(DateTime start, DateTime end) async {
    final startUtc = start.toUtc().toIso8601String();
    final endUtc = end.toUtc().toIso8601String();
    final taskRows = await database.database.rawQuery(
      "SELECT COUNT(*) AS count FROM tasks WHERE status = 'completed' AND completed_at >= ? AND completed_at < ?",
      [startUtc, endUtc],
    );
    final timerRows = await database.database.rawQuery(
      "SELECT COUNT(*) AS count, COALESCE(SUM(elapsed_seconds), 0) AS seconds FROM timer_sessions WHERE kind = 'focus' AND started_at >= ? AND started_at < ?",
      [startUtc, endUtc],
    );
    final habitRows = await database.database.rawQuery(
      'SELECT COUNT(*) AS count FROM habit_logs WHERE date >= ? AND date < ?',
      [_dateKey(start), _dateKey(end)],
    );
    final goalRows = await database.database.query(
      'goals',
      orderBy: 'created_at',
    );
    final shiftRows = await database.database.rawQuery(
      '''
      SELECT status, COUNT(*) AS count FROM shift_attendance
      WHERE date >= ? AND date < ? GROUP BY status
      ''',
      [_dateKey(start), _dateKey(end)],
    );
    final attendance = {
      for (final row in shiftRows) row['status'] as String: row['count'] as int,
    };
    final weekStart = start.subtract(Duration(days: start.weekday - 1));
    final penaltyRows = await database.database.rawQuery(
      "SELECT COUNT(*) AS count FROM accountability_events WHERE week_start = ? AND status = 'confirmed'",
      [_dateKey(weekStart)],
    );
    final penaltyCount = penaltyRows.single['count'] as int;
    return PeriodReview(
      start: start,
      endExclusive: end,
      completedTasks: taskRows.single['count'] as int,
      focusSessions: timerRows.single['count'] as int,
      focusMinutes: ((timerRows.single['seconds'] as num).toInt() / 60).floor(),
      habitCheckins: habitRows.single['count'] as int,
      goals: goalRows
          .map(
            (row) => GoalProgress(
              title: row['title'] as String,
              progress: (row['progress'] as num).toDouble(),
              target: (row['target'] as num?)?.toDouble(),
              unit: row['unit'] as String,
            ),
          )
          .toList(),
      attendedShifts: attendance['attended'] ?? 0,
      missedShifts: attendance['missed'] ?? 0,
      reliabilityScore: (100 - penaltyCount * 10).clamp(70, 100),
    );
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
