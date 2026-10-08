import 'dart:convert';

import 'ai_context_builder.dart';

class TaskScheduleSuggestion {
  const TaskScheduleSuggestion({
    required this.taskId,
    required this.taskTitle,
    required this.day,
    required this.reason,
    this.scheduledAt,
    this.durationMinutes = 30,
  });

  final String taskId;
  final String taskTitle;
  final DateTime day;
  final String reason;
  final DateTime? scheduledAt;
  final int durationMinutes;

  String get dayLabel =>
      '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}.${day.year}';
}

class AiSuggestion {
  const AiSuggestion({required this.summary, required this.recommendations});

  final String summary;
  final List<TaskScheduleSuggestion> recommendations;

  List<TaskScheduleSuggestion> select(Set<String> taskIds) =>
      recommendations.where((item) => taskIds.contains(item.taskId)).toList();
}

class AiSuggestionValidator {
  AiSuggestion parseAndValidate(
    String response, {
    required AiPlanningContext context,
    required DateTime today,
  }) {
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('Ответ не содержит JSON');
    }
    final decoded = jsonDecode(response.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Неверный формат ответа');
    }
    final summary = decoded['summary'];
    final items = decoded['recommendations'];
    if (summary is! String ||
        summary.trim().isEmpty ||
        summary.length > 1000 ||
        items is! List ||
        items.length > 5) {
      throw const FormatException('Ответ не прошёл проверку');
    }

    final allowedIds = context.tasks.map((task) => task.id).toSet();
    final usedIds = <String>{};
    final recommendations = <TaskScheduleSuggestion>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Неверный пункт рекомендации');
      }
      final taskId = item['taskId'];
      final date = item['day'];
      final rawStart = item['scheduledAt'];
      final rawDuration = item['durationMinutes'];
      final reason = item['reason'];
      if (taskId is! String ||
          !allowedIds.contains(taskId) ||
          !usedIds.add(taskId)) {
        throw const FormatException(
          'Рекомендация содержит неизвестную или повторную задачу',
        );
      }
      if (date is! String && rawStart is! String) {
        throw const FormatException('Неверная дата рекомендации');
      }
      if (rawStart != null && (rawStart is! String || rawDuration is! int)) {
        throw const FormatException('Неверный временной интервал рекомендации');
      }
      final parsedDay = date is String ? DateTime.tryParse(date) : null;
      final parsed = DateTime.tryParse(
        rawStart is String
            ? rawStart
            : (parsedDay != null &&
                      parsedDay.year == today.year &&
                      parsedDay.month == today.month &&
                      parsedDay.day == today.day
                  ? DateTime(
                      today.year,
                      today.month,
                      today.day,
                      today.hour + 1,
                    ).toIso8601String()
                  : '${date}T09:00:00'),
      );
      final duration = rawDuration is int ? rawDuration : 30;
      if (parsed == null ||
          parsed.isBefore(today) ||
          duration < 1 ||
          duration > 480) {
        throw const FormatException('Нельзя запланировать задачу в прошлом');
      }
      if (reason is! String || reason.trim().isEmpty || reason.length > 240) {
        throw const FormatException('Неверное пояснение рекомендации');
      }
      final finish = parsed.add(Duration(minutes: duration));
      final task = context.tasks.firstWhere((task) => task.id == taskId);
      if (task.dueAt != null && finish.isAfter(task.dueAt!)) {
        throw const FormatException('Слот выходит за дедлайн');
      }
      if (context.busyBlocks.any(
        (block) =>
            block.taskId != taskId &&
            parsed.isBefore(block.end) &&
            finish.isAfter(block.start),
      )) {
        throw const FormatException('Слот пересекается с занятым временем');
      }
      if (context.tasks.any(
        (other) =>
            other.id != taskId &&
            other.scheduledAt != null &&
            parsed.isBefore(
              other.scheduledAt!.add(
                Duration(minutes: other.estimatedMinutes ?? 30),
              ),
            ) &&
            finish.isAfter(other.scheduledAt!),
      )) {
        throw const FormatException('Слот пересекается с другой задачей');
      }
      recommendations.add(
        TaskScheduleSuggestion(
          taskId: taskId,
          taskTitle: context.tasks
              .firstWhere((task) => task.id == taskId)
              .title,
          day: DateTime(parsed.year, parsed.month, parsed.day),
          scheduledAt: parsed,
          durationMinutes: duration,
          reason: reason.trim(),
        ),
      );
    }
    return AiSuggestion(
      summary: summary.trim(),
      recommendations: recommendations,
    );
  }
}

class AiGoalLink {
  const AiGoalLink({
    required this.taskId,
    required this.goalId,
    required this.reason,
  });

  final String taskId;
  final String goalId;
  final String reason;
}
