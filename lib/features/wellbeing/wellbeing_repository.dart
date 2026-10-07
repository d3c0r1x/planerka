import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:uuid/uuid.dart';

import '../../core/app_database.dart';

class Habit {
  const Habit({
    required this.id,
    required this.title,
    required this.targetPerWeek,
  });
  final String id;
  final String title;
  final int targetPerWeek;
}

class HabitSummary {
  const HabitSummary({
    required this.weekCount,
    required this.streak,
    required this.todayDone,
  });
  final int weekCount;
  final int streak;
  final bool todayDone;
}

class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.text,
    required this.createdAt,
    this.mood,
  });
  final String id;
  final String text;
  final DateTime createdAt;
  final int? mood;
}

class WellbeingRepository {
  WellbeingRepository(
    this.database, {
    DateTime Function()? now,
    String Function()? newId,
  }) : _now = now ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  final AppDatabase database;
  final DateTime Function() _now;
  final String Function() _newId;

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<Habit> addHabit(String title, {int targetPerWeek = 7}) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty || targetPerWeek < 1 || targetPerWeek > 7) {
      throw ArgumentError('Введите название и недельную цель от 1 до 7');
    }
    final habit = Habit(
      id: _newId(),
      title: trimmed,
      targetPerWeek: targetPerWeek,
    );
    await database.database.insert('habits', {
      'id': habit.id,
      'title': habit.title,
      'target_per_week': habit.targetPerWeek,
      'created_at': _now().toUtc().toIso8601String(),
    });
    return habit;
  }

  Future<List<Habit>> listHabits() async {
    final rows = await database.database.query(
      'habits',
      where: 'archived_at IS NULL',
      orderBy: 'created_at',
    );
    return rows
        .map(
          (row) => Habit(
            id: row['id'] as String,
            title: row['title'] as String,
            targetPerWeek: row['target_per_week'] as int,
          ),
        )
        .toList();
  }

  Future<void> archiveHabit(String id) async {
    await database.database.update(
      'habits',
      {'archived_at': _now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> checkIn(String habitId, DateTime date) async {
    await database.database.insert('habit_logs', {
      'id': _newId(),
      'habit_id': habitId,
      'date': _date(date),
      'value': 1,
      'created_at': _now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> uncheck(String habitId, DateTime date) async {
    await database.database.delete(
      'habit_logs',
      where: 'habit_id = ? AND date = ?',
      whereArgs: [habitId, _date(date)],
    );
  }

  Future<HabitSummary> summary(String habitId, DateTime date) async {
    final rows = await database.database.query(
      'habit_logs',
      columns: ['date'],
      where: 'habit_id = ?',
      whereArgs: [habitId],
    );
    final dates = rows.map((row) => row['date'] as String).toSet();
    final today = DateTime(date.year, date.month, date.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final weekCount = dates
        .where(
          (day) =>
              day.compareTo(_date(monday)) >= 0 &&
              day.compareTo(_date(sunday)) <= 0,
        )
        .length;
    var streak = 0;
    var cursor = today;
    while (dates.contains(_date(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return HabitSummary(
      weekCount: weekCount,
      streak: streak,
      todayDone: dates.contains(_date(today)),
    );
  }

  void _validateJournal(String text, int? mood) {
    if (text.trim().isEmpty || (mood != null && (mood < 1 || mood > 5))) {
      throw ArgumentError('Введите запись и оценку настроения от 1 до 5');
    }
  }

  Future<JournalEntry> addJournal(String text, {int? mood}) async {
    _validateJournal(text, mood);
    final entry = JournalEntry(
      id: _newId(),
      text: text.trim(),
      createdAt: _now().toUtc(),
      mood: mood,
    );
    await database.database.insert('journal_entries', {
      'id': entry.id,
      'text': entry.text,
      'mood': entry.mood,
      'created_at': entry.createdAt.toIso8601String(),
    });
    return entry;
  }

  Future<void> updateJournal(String id, String text, {int? mood}) async {
    _validateJournal(text, mood);
    await database.database.update(
      'journal_entries',
      {'text': text.trim(), 'mood': mood},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteJournal(String id) async {
    await database.database.delete(
      'journal_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<JournalEntry>> listJournal() async {
    final rows = await database.database.query(
      'journal_entries',
      orderBy: 'created_at DESC',
    );
    return rows
        .map(
          (row) => JournalEntry(
            id: row['id'] as String,
            text: row['text'] as String,
            mood: row['mood'] as int?,
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
        )
        .toList();
  }
}
