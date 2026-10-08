import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../../core/app_database.dart';
import '../../shifts/shift_repository.dart';
import '../model/local_ai_engine.dart';

export '../../gamification/game_models.dart' show MissedTaskCause;

import '../../gamification/game_models.dart' show MissedTaskCause;

enum MissedTaskActionType { reschedule, split, changeDeadline, discard }

class MissedTaskInterview {
  const MissedTaskInterview({
    required this.taskId,
    required this.taskTitle,
    required this.questions,
  });

  final String taskId;
  final String taskTitle;
  final List<String> questions;
}

class MissedTaskAnswer {
  const MissedTaskAnswer({required this.question, required this.answer});

  final String question;
  final String answer;
}

class MissedTaskAction {
  const MissedTaskAction({
    required this.type,
    required this.label,
    this.scheduledAt,
    this.dueAt,
    this.durationMinutes,
    this.followUpTitle,
  });

  final MissedTaskActionType type;
  final String label;
  final DateTime? scheduledAt;
  final DateTime? dueAt;
  final int? durationMinutes;
  final String? followUpTitle;
}

class MissedTaskProposal {
  const MissedTaskProposal({
    required this.id,
    required this.taskId,
    required this.cause,
    required this.explanation,
    required this.actions,
    this.taskSnapshot,
  });

  final String id;
  final String taskId;
  final MissedTaskCause cause;
  final String explanation;
  final List<MissedTaskAction> actions;
  final Map<String, Object?>? taskSnapshot;
}

abstract interface class MissedTaskReviewFlow {
  Future<MissedTaskInterview> startInterview(String taskId);
  Future<MissedTaskProposal> analyzeAnswers(
    String taskId,
    List<MissedTaskAnswer> answers,
  );
  Future<void> applyAction(MissedTaskProposal proposal, int actionIndex);
}

class MissedTaskReviewService implements MissedTaskReviewFlow {
  MissedTaskReviewService(
    this.database,
    this.generator, {
    DateTime Function()? now,
    String Function()? newId,
  }) : _now = now ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  final AppDatabase database;
  final AiTextGenerator generator;
  final DateTime Function() _now;
  final String Function() _newId;
  final Map<String, Map<String, Object?>> _interviewSnapshots = {};

  @override
  Future<MissedTaskInterview> startInterview(String taskId) async {
    final task = await _openTask(taskId);
    if (!_isMissed(task)) throw StateError('У задачи ещё не истёк срок');
    _interviewSnapshots[taskId] = _snapshot(task);
    final prompt =
        '''Ты бережный помощник планировщика. Задай 2–4 коротких последовательных вопроса, чтобы понять, почему пропущена задача и что поможет дальше. Не обвиняй и не предлагай штраф.
Ответ только JSON: {"questions":["вопрос 1","вопрос 2"]}.
Задача: ${_limit(task['title'] as String, 160)}''';
    final response = await generator.generate(prompt, maxTokens: 256);
    final decoded = _decode(response);
    final rawQuestions = decoded['questions'];
    if (rawQuestions is! List ||
        rawQuestions.length < 2 ||
        rawQuestions.length > 4) {
      throw const FormatException('Нужно от 2 до 4 вопросов');
    }
    final questions = <String>[];
    for (final raw in rawQuestions) {
      if (raw is! String || raw.trim().isEmpty || raw.length > 180) {
        throw const FormatException('Неверный вопрос интервью');
      }
      questions.add(raw.trim());
    }
    return MissedTaskInterview(
      taskId: taskId,
      taskTitle: task['title'] as String,
      questions: questions,
    );
  }

  @override
  Future<MissedTaskProposal> analyzeAnswers(
    String taskId,
    List<MissedTaskAnswer> answers,
  ) async {
    if (answers.length < 2 ||
        answers.length > 4 ||
        answers.any(
          (answer) =>
              answer.question.trim().isEmpty ||
              answer.answer.trim().isEmpty ||
              answer.answer.length > 1000,
        )) {
      throw ArgumentError('Ответь на каждый вопрос интервью');
    }
    final task = await _openTask(taskId);
    final interviewSnapshot = _interviewSnapshots.remove(taskId);
    if (interviewSnapshot != null &&
        !_matchesSnapshot(task, interviewSnapshot)) {
      throw StateError('Задача изменилась; начни разбор заново');
    }
    if (!_isMissed(task)) throw StateError('Задача больше не пропущена');
    final taskSnapshot = _snapshot(task);
    final prompt =
        '''Ты помощник по планированию. Определи наиболее подходящую причину без осуждения и предложи 1–4 действия на выбор. Не записывай ничего сам.
Причины: externalObstacle, estimateWrong, priorityChanged, avoidableDelay.
Действия: reschedule требует scheduledAt и durationMinutes; split требует followUpTitle; changeDeadline требует dueAt; discard не требует даты.
Ответ только JSON: {"cause":"externalObstacle","explanation":"кратко","actions":[{"type":"reschedule","label":"Перенести","scheduledAt":"ISO8601","durationMinutes":30}]}.
Задача: ${_limit(task['title'] as String, 160)}
Ответы: ${jsonEncode(answers.map((answer) => {'question': _limit(answer.question, 180), 'answer': _limit(answer.answer.trim(), 500)}).toList())}''';
    final response = await generator.generate(prompt, maxTokens: 512);
    final proposal = _parseProposal(response, taskId, taskSnapshot);
    await _validateRescheduleActions(proposal, database.database);
    final freshTask = await _openTask(taskId);
    if (!_matchesSnapshot(freshTask, taskSnapshot)) {
      throw StateError('Задача изменилась; сформируй рекомендацию заново');
    }
    return proposal;
  }

  @override
  Future<void> applyAction(MissedTaskProposal proposal, int actionIndex) async {
    if (actionIndex < 0 || actionIndex >= proposal.actions.length) {
      throw RangeError.index(actionIndex, proposal.actions);
    }
    final action = proposal.actions[actionIndex];
    final now = _now();
    final key = 'missed_review_applied:${proposal.id}';
    if (action.type == MissedTaskActionType.reschedule) {
      await _validateNoShiftOverlap(
        action.scheduledAt!,
        action.scheduledAt!.add(Duration(minutes: action.durationMinutes!)),
      );
    }
    await database.database.transaction((tx) async {
      final applied = await tx.query(
        'app_metadata',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (applied.isNotEmpty) throw StateError('Рекомендация уже применена');
      final rows = await tx.query(
        'tasks',
        columns: [
          'id',
          'status',
          'due_at',
          'scheduled_at',
          'estimated_minutes',
          'updated_at',
        ],
        where: "id = ? AND status IN ('planned', 'quick')",
        whereArgs: [proposal.taskId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Задача больше недоступна');
      if (proposal.taskSnapshot == null ||
          !_matchesSnapshot(rows.single, proposal.taskSnapshot!)) {
        throw StateError('Задача изменилась; сформируй рекомендацию заново');
      }
      final deadline = rows.single['due_at'] as String?;
      switch (action.type) {
        case MissedTaskActionType.reschedule:
          final start = action.scheduledAt!;
          final duration = action.durationMinutes!;
          final end = start.add(Duration(minutes: duration));
          final oldDeadline = deadline == null
              ? null
              : DateTime.parse(deadline);
          if (start.isBefore(now) ||
              oldDeadline != null &&
                  oldDeadline.isAfter(now.toUtc()) &&
                  end.toUtc().isAfter(oldDeadline)) {
            throw StateError('Время переноса больше не подходит');
          }
          await _validateNoTaskOverlap(
            tx,
            taskId: proposal.taskId,
            start: start,
            end: end,
          );
          await tx.update(
            'tasks',
            {
              'scheduled_at': start.toUtc().toIso8601String(),
              'scheduled_date': _day(start),
              'estimated_minutes': duration,
              if (oldDeadline != null && !oldDeadline.isAfter(now.toUtc()))
                'due_at': null,
              if (oldDeadline != null && !oldDeadline.isAfter(now.toUtc()))
                'remind_at': null,
              'updated_at': now.toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [proposal.taskId],
          );
        case MissedTaskActionType.changeDeadline:
          final dueAt = action.dueAt!;
          if (!dueAt.isAfter(now)) throw StateError('Новый срок уже прошёл');
          await tx.update(
            'tasks',
            {
              'due_at': dueAt.toUtc().toIso8601String(),
              'remind_at': dueAt.toUtc().toIso8601String(),
              'updated_at': now.toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [proposal.taskId],
          );
        case MissedTaskActionType.split:
          await tx.update(
            'tasks',
            {
              'due_at': null,
              'remind_at': null,
              'scheduled_at': null,
              'scheduled_date': null,
              'estimated_minutes': null,
              'updated_at': now.toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [proposal.taskId],
          );
          await tx.insert('tasks', {
            'id': _newId(),
            'title': action.followUpTitle!.trim(),
            'notes': '',
            'status': 'planned',
            'parent_task_id': proposal.taskId,
            'created_at': now.toUtc().toIso8601String(),
            'updated_at': now.toUtc().toIso8601String(),
          });
        case MissedTaskActionType.discard:
          await tx.update(
            'tasks',
            {'status': 'deleted', 'updated_at': now.toUtc().toIso8601String()},
            where: 'id = ?',
            whereArgs: [proposal.taskId],
          );
      }
      await tx.insert('app_metadata', {
        'key': key,
        'value': action.type.name,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
    });
    await database.remindersChanged();
  }

  Future<Map<String, Object?>> _openTask(String taskId) async {
    final rows = await database.database.query(
      'tasks',
      columns: [
        'id',
        'title',
        'status',
        'due_at',
        'scheduled_at',
        'estimated_minutes',
        'updated_at',
      ],
      where: "id = ? AND status IN ('planned', 'quick')",
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Задача больше недоступна');
    return rows.single;
  }

  bool _isMissed(Map<String, Object?> task) {
    final dueAt = task['due_at'] == null
        ? null
        : DateTime.parse(task['due_at'] as String);
    final scheduledAt = task['scheduled_at'] == null
        ? null
        : DateTime.parse(task['scheduled_at'] as String);
    final estimate = task['estimated_minutes'] as int? ?? 30;
    return dueAt != null && dueAt.isBefore(_now()) ||
        scheduledAt != null &&
            scheduledAt.add(Duration(minutes: estimate)).isBefore(_now());
  }

  MissedTaskProposal _parseProposal(
    String response,
    String taskId,
    Map<String, Object?> taskSnapshot,
  ) {
    final decoded = _decode(response);
    final causeRaw = decoded['cause'];
    final explanation = decoded['explanation'];
    final actionsRaw = decoded['actions'];
    if (causeRaw is! String ||
        explanation is! String ||
        explanation.trim().isEmpty ||
        explanation.length > 600 ||
        actionsRaw is! List ||
        actionsRaw.isEmpty ||
        actionsRaw.length > 4) {
      throw const FormatException('Предложение не прошло проверку');
    }
    final cause = MissedTaskCause.values.where(
      (value) => value.name == causeRaw,
    );
    if (cause.isEmpty) {
      throw const FormatException('Неизвестная причина пропуска');
    }
    final actions = <MissedTaskAction>[];
    final seen = <MissedTaskActionType>{};
    for (final raw in actionsRaw) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Неверный вариант действия');
      }
      final typeRaw = raw['type'];
      final label = raw['label'];
      final type = typeRaw is String
          ? MissedTaskActionType.values.where((value) => value.name == typeRaw)
          : const <MissedTaskActionType>[];
      if (type.isEmpty ||
          label is! String ||
          label.trim().isEmpty ||
          label.length > 100 ||
          !seen.add(type.first)) {
        throw const FormatException(
          'Неизвестный или повторный вариант действия',
        );
      }
      final scheduledAt = _date(raw['scheduledAt']);
      final dueAt = _date(raw['dueAt']);
      final duration = raw['durationMinutes'];
      final action = MissedTaskAction(
        type: type.first,
        label: label.trim(),
        scheduledAt: scheduledAt,
        dueAt: dueAt,
        durationMinutes: duration is int ? duration : null,
        followUpTitle: raw['followUpTitle'] is String
            ? (raw['followUpTitle'] as String).trim()
            : null,
      );
      switch (action.type) {
        case MissedTaskActionType.reschedule:
          if (scheduledAt == null ||
              !scheduledAt.isAfter(_now()) ||
              duration is! int ||
              duration < 1 ||
              duration > 480) {
            throw const FormatException('Неверное время переноса');
          }
        case MissedTaskActionType.changeDeadline:
          if (dueAt == null || !dueAt.isAfter(_now())) {
            throw const FormatException('Неверный новый срок');
          }
        case MissedTaskActionType.split:
          if (action.followUpTitle == null ||
              action.followUpTitle!.isEmpty ||
              action.followUpTitle!.length > 160) {
            throw const FormatException('Неверное название следующего шага');
          }
        case MissedTaskActionType.discard:
          break;
      }
      actions.add(action);
    }
    return MissedTaskProposal(
      id: _newId(),
      taskId: taskId,
      cause: cause.first,
      explanation: explanation.trim(),
      actions: actions,
      taskSnapshot: taskSnapshot,
    );
  }

  Map<String, Object?> _snapshot(Map<String, Object?> task) => {
    'status': task['status'],
    'due_at': task['due_at'],
    'scheduled_at': task['scheduled_at'],
    'estimated_minutes': task['estimated_minutes'],
    'updated_at': task['updated_at'],
  };

  bool _matchesSnapshot(
    Map<String, Object?> task,
    Map<String, Object?> snapshot,
  ) => snapshot.entries.every((entry) => task[entry.key] == entry.value);

  Future<void> _validateRescheduleActions(
    MissedTaskProposal proposal,
    DatabaseExecutor source,
  ) async {
    for (final action in proposal.actions) {
      if (action.type != MissedTaskActionType.reschedule) continue;
      final start = action.scheduledAt!;
      final end = start.add(Duration(minutes: action.durationMinutes!));
      final rawDueAt = proposal.taskSnapshot?['due_at'];
      if (rawDueAt is String) {
        final dueAt = DateTime.parse(rawDueAt);
        if (dueAt.isAfter(_now().toUtc()) && end.toUtc().isAfter(dueAt)) {
          throw StateError('Слот выходит за актуальный дедлайн');
        }
      }
      await _validateNoShiftOverlap(start, end);
      await _validateNoTaskOverlap(
        source,
        taskId: proposal.taskId,
        start: start,
        end: end,
      );
    }
  }

  Future<void> _validateNoShiftOverlap(DateTime start, DateTime end) async {
    final shifts = ShiftRepository(database, now: _now);
    final startDay = DateTime(start.year, start.month, start.day - 1);
    final endDay = DateTime(end.year, end.month, end.day + 2);
    final teams = await shifts.listTeams();
    final attending = teams
        .where((team) => team.attends)
        .map((team) => team.id)
        .toSet();
    if (attending.isEmpty) return;
    final days = await shifts.calendar(startDay, endDay);
    if (days.any(
      (shift) =>
          attending.contains(shift.teamId) &&
          shift.blockStart != null &&
          shift.blockEnd != null &&
          start.isBefore(shift.blockEnd!) &&
          end.isAfter(shift.blockStart!),
    )) {
      throw StateError('Слот пересекается со сменой или дорогой');
    }
  }

  Future<void> _validateNoTaskOverlap(
    DatabaseExecutor source, {
    required String taskId,
    required DateTime start,
    required DateTime end,
  }) async {
    final rows = await source.query(
      'tasks',
      columns: ['id', 'scheduled_at', 'estimated_minutes'],
      where: "status IN ('planned', 'quick') AND scheduled_at IS NOT NULL",
    );
    for (final row in rows) {
      if (row['id'] == taskId) continue;
      final otherStart = DateTime.parse(row['scheduled_at'] as String);
      final otherEnd = otherStart.add(
        Duration(minutes: row['estimated_minutes'] as int? ?? 30),
      );
      if (start.isBefore(otherEnd) && end.isAfter(otherStart)) {
        throw StateError('Слот пересекается с другой задачей');
      }
    }
  }

  DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  Map<String, dynamic> _decode(String response) {
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('Ответ не содержит JSON');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.substring(start, end + 1));
    } on FormatException {
      throw const FormatException('Ответ ИИ содержит неверный JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Ответ ИИ имеет неверную структуру');
    }
    return decoded;
  }

  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _limit(String value, int length) {
    final cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.length <= length ? cleaned : cleaned.substring(0, length);
  }
}
