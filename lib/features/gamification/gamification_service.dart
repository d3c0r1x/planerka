import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:sqflite_common/sqlite_api.dart' show Transaction;
import 'package:uuid/uuid.dart';

import '../../core/app_database.dart';
import 'game_models.dart';

abstract interface class GamificationDataSource {
  Future<void> awardWeeklyReview(DateTime date);
  Future<bool> weeklyReviewAwarded(DateTime date);
  Future<PlayerProgress> progress();
  Future<List<GameQuest>> dailyQuests(DateTime date);
  Future<List<GameQuest>> weeklyQuests(DateTime date);
  Future<List<GameAchievement>> achievements();
  Future<CustomReward> addReward(String title);
  Future<List<CustomReward>> rewards();
  Future<void> redeemReward(String id, {DateTime? at});
  Future<WeeklyReliability> reliabilityForWeek(DateTime date);
  Future<void> setAccountabilityEnabled(bool enabled);
  Future<List<AccountabilityEvent>> accountabilityHistory({int limit = 20});
  Future<List<RecoveryTask>> completedTasks();
  Future<void> resolvePenalty(String eventId, String recoveryTaskId);
}

class GamificationService implements GamificationDataSource {
  GamificationService(
    this.database, {
    DateTime Function()? now,
    String Function()? newId,
  }) : _now = now ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  static const xpPerLevel = 100;
  static const taskXp = 10;
  static const focusXp = 15;
  static const habitXp = 5;

  final AppDatabase database;
  final DateTime Function() _now;
  final String Function() _newId;

  Future<void> awardTask(String taskId, {DateTime? occurredAt}) =>
      _award('task:$taskId', 'task', taskXp, occurredAt);

  Future<void> awardFocusSession(String sessionId, {DateTime? occurredAt}) =>
      _award('focus:$sessionId', 'focus', focusXp, occurredAt);

  Future<void> awardHabitCheckIn(
    String habitId,
    DateTime date, {
    DateTime? occurredAt,
  }) =>
      _award('habit:$habitId:${_dateKey(date)}', 'habit', habitXp, occurredAt);

  @override
  Future<void> awardWeeklyReview(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final monday = day.subtract(Duration(days: day.weekday - 1));
    return _award(
      'weekly_review:${_dateKey(monday)}',
      'weekly_review',
      25,
      date,
    );
  }

  @override
  Future<bool> weeklyReviewAwarded(DateTime date) async {
    final day = DateTime(date.year, date.month, date.day);
    final monday = day.subtract(Duration(days: day.weekday - 1));
    final rows = await database.database.query(
      'xp_events',
      columns: ['event_id'],
      where: 'event_id = ?',
      whereArgs: ['weekly_review:${_dateKey(monday)}'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _award(
    String eventId,
    String kind,
    int points,
    DateTime? occurredAt,
  ) async {
    if (eventId.endsWith(':') || eventId.trim().isEmpty) {
      throw ArgumentError.value(eventId, 'eventId');
    }
    final timestamp = (occurredAt ?? _now()).toUtc().toIso8601String();
    await database.database.transaction((transaction) async {
      await transaction.insert('xp_events', {
        'event_id': eventId,
        'kind': kind,
        'points': points,
        'occurred_at': timestamp,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await _unlockAchievements(transaction, timestamp);
    });
  }

  @override
  Future<PlayerProgress> progress() async {
    final rows = await database.database.rawQuery(
      'SELECT COALESCE(SUM(points), 0) AS xp FROM xp_events',
    );
    final total = (rows.single['xp'] as int?) ?? 0;
    return PlayerProgress(
      totalXp: total,
      level: total ~/ xpPerLevel + 1,
      xpInLevel: total % xpPerLevel,
      xpToNextLevel: xpPerLevel,
    );
  }

  @override
  Future<List<GameQuest>> dailyQuests(DateTime date) => _quests('daily', date);

  @override
  Future<List<GameQuest>> weeklyQuests(DateTime date) =>
      _quests('weekly', date);

  Future<List<GameQuest>> _quests(String period, DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final periodStart = period == 'weekly'
        ? start.subtract(Duration(days: start.weekday - 1))
        : start;
    final end = periodStart.add(Duration(days: period == 'weekly' ? 7 : 1));
    final startUtc = periodStart.toUtc().toIso8601String();
    final endUtc = end.toUtc().toIso8601String();
    final key = _dateKey(periodStart);
    final definitions = period == 'daily'
        ? const [
            _QuestDefinition('task', 'Заверши одно дело', 1, 5),
            _QuestDefinition('focus', 'Проведи фокус-сессию', 1, 5),
            _QuestDefinition('habit', 'Отметь привычку', 1, 5),
          ]
        : const [_QuestDefinition('focus', 'Проведи 5 фокус-сессий', 5, 15)];
    return database.database.transaction((transaction) async {
      for (final definition in definitions) {
        final id = '$period:$key:${definition.key}';
        await transaction.insert('game_quests', {
          'id': id,
          'period': period,
          'period_start': key,
          'quest_key': definition.key,
          'title': definition.title,
          'target': definition.target,
          'reward_xp': definition.rewardXp,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      final rows = await transaction.query(
        'game_quests',
        where: 'period = ? AND period_start = ?',
        whereArgs: [period, key],
        orderBy: 'quest_key',
      );
      for (final row in rows) {
        final countRows = await transaction.rawQuery(
          '''
          SELECT COUNT(*) AS count FROM xp_events
          WHERE kind = ? AND occurred_at >= ? AND occurred_at < ?
          ''',
          [row['quest_key'], startUtc, endUtc],
        );
        final count = (countRows.single['count'] as int).clamp(
          0,
          row['target'] as int,
        );
        final completedAt = row['completed_at'] as String?;
        await transaction.update(
          'game_quests',
          {
            'progress': count,
            if (count >= (row['target'] as int) && completedAt == null)
              'completed_at': _now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        if (count >= (row['target'] as int) && completedAt == null) {
          final rewardAt = _now().toUtc().toIso8601String();
          await transaction.insert('xp_events', {
            'event_id': 'quest:${row['id']}',
            'kind': 'quest_reward',
            'points': row['reward_xp'],
            'occurred_at': rewardAt,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          await _unlockAchievements(transaction, rewardAt);
        }
      }
      final updated = await transaction.query(
        'game_quests',
        where: 'period = ? AND period_start = ?',
        whereArgs: [period, key],
        orderBy: 'quest_key',
      );
      return updated.map(_questFromRow).toList();
    });
  }

  @override
  Future<List<GameAchievement>> achievements() async {
    final rows = await database.database.query(
      'game_achievements',
      orderBy: 'unlocked_at',
    );
    return rows
        .map(
          (row) => GameAchievement(
            key: row['key'] as String,
            title: row['title'] as String,
            description: row['description'] as String,
            unlockedAt: DateTime.parse(row['unlocked_at'] as String),
          ),
        )
        .toList();
  }

  Future<void> _unlockAchievements(Transaction transaction, String at) async {
    final counts = await transaction.rawQuery(
      'SELECT kind, COUNT(*) AS count FROM xp_events GROUP BY kind',
    );
    final byKind = {
      for (final row in counts) row['kind'] as String: row['count'] as int,
    };
    final totalRows = await transaction.rawQuery(
      'SELECT COALESCE(SUM(points), 0) AS xp FROM xp_events',
    );
    final totalXp = (totalRows.single['xp'] as int?) ?? 0;
    final habitRows = await transaction.rawQuery(
      'SELECT COUNT(DISTINCT date) AS count FROM habit_logs',
    );
    final habitDays = (habitRows.single['count'] as int?) ?? 0;
    final milestones =
        <({String key, String title, String description, bool met})>[
          (
            key: 'first_task',
            title: 'Первый шаг',
            description: 'Завершено первое дело',
            met: (byKind['task'] ?? 0) >= 1,
          ),
          (
            key: 'five_focus_sessions',
            title: 'В ритме',
            description: 'Проведено пять фокус-сессий',
            met: (byKind['focus'] ?? 0) >= 5,
          ),
          (
            key: 'habit_week',
            title: 'Забота о себе',
            description: 'Отмечено семь дней привычек',
            met: habitDays >= 7,
          ),
          (
            key: 'first_level',
            title: 'Новый уровень',
            description: 'Набрано 100 очков опыта',
            met: totalXp >= xpPerLevel,
          ),
        ];
    for (final item in milestones.where((item) => item.met)) {
      await transaction.insert('game_achievements', {
        'key': item.key,
        'title': item.title,
        'description': item.description,
        'unlocked_at': at,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  @override
  Future<CustomReward> addReward(String title) async {
    final text = title.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Введите награду');
    }
    final reward = CustomReward(
      id: _newId(),
      title: text,
      createdAt: _now().toUtc(),
    );
    await database.database.insert('custom_rewards', {
      'id': reward.id,
      'title': reward.title,
      'created_at': reward.createdAt.toIso8601String(),
    });
    return reward;
  }

  @override
  Future<List<CustomReward>> rewards() async {
    final rows = await database.database.query(
      'custom_rewards',
      orderBy: 'created_at DESC',
    );
    return rows
        .map(
          (row) => CustomReward(
            id: row['id'] as String,
            title: row['title'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
            redeemedAt: row['redeemed_at'] == null
                ? null
                : DateTime.parse(row['redeemed_at'] as String),
          ),
        )
        .toList();
  }

  @override
  Future<void> redeemReward(String id, {DateTime? at}) async {
    final changed = await database.database.update(
      'custom_rewards',
      {'redeemed_at': (at ?? _now()).toUtc().toIso8601String()},
      where: 'id = ? AND redeemed_at IS NULL',
      whereArgs: [id],
    );
    if (changed == 0) {
      final existing = await database.database.query(
        'custom_rewards',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (existing.isEmpty) throw StateError('Награда не найдена');
    }
  }

  Future<PenaltyProposal> proposePenalty(
    String taskId,
    MissedTaskCause cause,
  ) async {
    if (cause != MissedTaskCause.avoidableDelay) {
      throw StateError('Эта причина не создаёт штраф');
    }
    final enabled = await _accountabilityEnabled();
    if (!enabled) throw StateError('Система ответственности выключена');
    final tasks = await database.database.query(
      'tasks',
      columns: ['id', 'status', 'due_at', 'scheduled_at', 'estimated_minutes'],
      where: "id = ? AND status IN ('planned', 'quick')",
      whereArgs: [taskId],
      limit: 1,
    );
    if (tasks.isEmpty) throw StateError('Задача недоступна');
    final row = tasks.single;
    final now = _now();
    final due = row['due_at'] as String?;
    final scheduled = row['scheduled_at'] as String?;
    final duration = row['estimated_minutes'] as int? ?? 30;
    final missed =
        due != null && !DateTime.parse(due).isAfter(now.toUtc()) ||
        scheduled != null &&
            !DateTime.parse(scheduled)
                .add(Duration(minutes: duration))
                .isAfter(now);
    if (!missed) throw StateError('Задача не просрочена');
    final week = _weekStart(now);
    return PenaltyProposal(
      id: _newId(),
      taskId: taskId,
      cause: cause,
      weekStart: week,
      points: 10,
    );
  }

  Future<void> confirmPenalty(PenaltyProposal proposal) async {
    if (proposal.cause != MissedTaskCause.avoidableDelay ||
        proposal.points != 10) {
      throw StateError('Недопустимый штраф');
    }
    if (!await _accountabilityEnabled()) {
      throw StateError('Система ответственности выключена');
    }
    final week = _weekStart(_now());
    if (!_sameDay(proposal.weekStart, week)) {
      throw StateError('Предложение устарело');
    }
    await database.database.transaction((tx) async {
      final task = await tx.query(
        'tasks',
        columns: ['id', 'due_at', 'scheduled_at', 'estimated_minutes'],
        where: "id = ? AND status IN ('planned', 'quick')",
        whereArgs: [proposal.taskId],
        limit: 1,
      );
      if (task.isEmpty) throw StateError('Задача недоступна');
      final due = task.single['due_at'] as String?;
      final scheduled = task.single['scheduled_at'] as String?;
      final duration = task.single['estimated_minutes'] as int? ?? 30;
      if (!(due != null && !DateTime.parse(due).isAfter(_now().toUtc()) ||
          scheduled != null &&
              !DateTime.parse(scheduled)
                  .add(Duration(minutes: duration))
                  .isAfter(_now()))) {
        throw StateError('Задача больше не просрочена');
      }
      final sameMiss = await tx.query(
        'accountability_events',
        where: 'task_id = ? AND week_start = ? AND cause = ?',
        whereArgs: [proposal.taskId, _dateKey(week), proposal.cause.name],
        limit: 1,
      );
      if (sameMiss.isNotEmpty) return;
      final duplicate = await tx.query(
        'accountability_events',
        where: 'id = ?',
        whereArgs: [proposal.id],
        limit: 1,
      );
      if (duplicate.isNotEmpty) return;
      final counts = await tx.rawQuery(
        'SELECT COUNT(*) AS count FROM accountability_events WHERE week_start = ?',
        [_dateKey(week)],
      );
      final count = (counts.single['count'] as int?) ?? 0;
      if (count >= 3) throw StateError('Достигнут недельный лимит');
      await tx.insert('accountability_events', {
        'id': proposal.id,
        'task_id': proposal.taskId,
        'week_start': _dateKey(week),
        'cause': proposal.cause.name,
        'points': 10,
        'status': 'confirmed',
        'created_at': _now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  @override
  Future<WeeklyReliability> reliabilityForWeek(DateTime date) async {
    final week = _weekStart(date);
    final rows = await database.database.rawQuery(
      "SELECT COUNT(*) AS count FROM accountability_events WHERE week_start = ? AND status = 'confirmed'",
      [_dateKey(week)],
    );
    final count = (rows.single['count'] as int?) ?? 0;
    return WeeklyReliability(
      weekStart: week,
      score: (100 - count * 10).clamp(70, 100),
      penaltyCount: count,
      enabled: await _accountabilityEnabled(),
    );
  }

  @override
  Future<void> resolvePenalty(String eventId, String recoveryTaskId) async {
    await database.database.transaction((tx) async {
      final rows = await tx.query(
        'accountability_events',
        where: "id = ? AND status = 'confirmed'",
        whereArgs: [eventId],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final tasks = await tx.query(
        'tasks',
        columns: ['id', 'status'],
        where: 'id = ?',
        whereArgs: [recoveryTaskId],
        limit: 1,
      );
      if (tasks.isEmpty || tasks.single['status'] != 'completed') {
        throw StateError('Заверши восстановительный шаг');
      }
      final alreadyUsed = await tx.query(
        'accountability_events',
        columns: ['id'],
        where: 'recovery_task_id = ?',
        whereArgs: [recoveryTaskId],
        limit: 1,
      );
      if (alreadyUsed.isNotEmpty) {
        throw StateError('Восстановительный шаг уже использован');
      }
      await tx.update(
        'accountability_events',
        {
          'status': 'resolved',
          'recovery_task_id': recoveryTaskId,
          'resolved_at': _now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [eventId],
      );
    });
  }

  @override
  Future<void> setAccountabilityEnabled(bool enabled) async {
    await database.database.insert('app_metadata', {
      'key': 'accountability_enabled',
      'value': enabled ? '1' : '0',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<AccountabilityEvent>> accountabilityHistory({
    int limit = 20,
  }) async {
    final rows = await database.database.rawQuery(
      '''SELECT e.*, t.title AS task_title
         FROM accountability_events e
         LEFT JOIN tasks t ON t.id = e.task_id
         ORDER BY e.created_at DESC LIMIT ?''',
      [limit.clamp(1, 100)],
    );
    return rows
        .map(
          (row) => AccountabilityEvent(
            id: row['id'] as String,
            taskId: row['task_id'] as String,
            taskTitle: row['task_title'] as String? ?? 'Задача',
            cause: row['cause'] as String,
            points: row['points'] as int,
            status: row['status'] as String,
            createdAt: DateTime.parse(row['created_at'] as String),
            recoveryTaskId: row['recovery_task_id'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<List<RecoveryTask>> completedTasks() async {
    final rows = await database.database.query(
      'tasks',
      columns: ['id', 'title'],
      where: "status = 'completed'",
      orderBy: 'completed_at DESC',
      limit: 100,
    );
    return rows
        .map(
          (row) => RecoveryTask(
            id: row['id'] as String,
            title: row['title'] as String,
          ),
        )
        .toList();
  }

  Future<bool> _accountabilityEnabled() async {
    final rows = await database.database.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['accountability_enabled'],
      limit: 1,
    );
    return rows.isEmpty || rows.single['value'] == '1';
  }

  DateTime _weekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  GameQuest _questFromRow(Map<String, Object?> row) => GameQuest(
    id: row['id'] as String,
    kind: row['quest_key'] as String,
    title: row['title'] as String,
    progress: row['progress'] as int,
    target: row['target'] as int,
    rewardXp: row['reward_xp'] as int,
    completed: row['completed_at'] != null,
  );

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _QuestDefinition {
  const _QuestDefinition(this.key, this.title, this.target, this.rewardXp);
  final String key;
  final String title;
  final int target;
  final int rewardXp;
}
