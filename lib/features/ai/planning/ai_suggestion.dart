import 'dart:convert';

import 'ai_context_builder.dart';

class TaskScheduleSuggestion {
  const TaskScheduleSuggestion({
    required this.taskId,
    required this.taskTitle,
    required this.day,
    required this.reason,
  });

  final String taskId;
  final String taskTitle;
  final DateTime day;
  final String reason;

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
      final reason = item['reason'];
      if (taskId is! String ||
          !allowedIds.contains(taskId) ||
          !usedIds.add(taskId)) {
        throw const FormatException(
          'Рекомендация содержит неизвестную или повторную задачу',
        );
      }
      if (date is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
        throw const FormatException('Неверная дата рекомендации');
      }
      final parsed = DateTime.tryParse(date);
      final todayDay = DateTime(today.year, today.month, today.day);
      if (parsed == null || parsed.isBefore(todayDay)) {
        throw const FormatException('Нельзя запланировать задачу в прошлом');
      }
      if (reason is! String || reason.trim().isEmpty || reason.length > 240) {
        throw const FormatException('Неверное пояснение рекомендации');
      }
      recommendations.add(
        TaskScheduleSuggestion(
          taskId: taskId,
          taskTitle: context.tasks
              .firstWhere((task) => task.id == taskId)
              .title,
          day: DateTime(parsed.year, parsed.month, parsed.day),
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
