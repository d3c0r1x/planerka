import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/ai/planning/ai_context_builder.dart';
import 'package:planerka/features/ai/planning/ai_suggestion.dart';

void main() {
  test('rejects AI time slot overlapping a busy block or passing deadline', () {
    final context = AiPlanningContext(
      tasks: [
        AiTaskContext(
          id: 't1',
          title: 'Task',
          dueAt: DateTime(2026, 10, 8, 12),
        ),
      ],
      goals: const [],
      diary: const [],
      busyBlocks: [
        AiBusyBlock(
          start: DateTime(2026, 10, 8, 10),
          end: DateTime(2026, 10, 8, 20),
          label: 'Смена',
        ),
      ],
    );
    final validator = AiSuggestionValidator();
    expect(
      () => validator.parseAndValidate(
        '{"summary":"Ок","recommendations":[{"taskId":"t1","scheduledAt":"2026-10-08T11:00:00","durationMinutes":60,"reason":"Причина"}]}',
        context: context,
        today: DateTime(2026, 10, 8, 8),
      ),
      throwsFormatException,
    );
    expect(
      () => validator.parseAndValidate(
        '{"summary":"Ок","recommendations":[{"taskId":"t1","scheduledAt":"2026-10-08T12:00:00","durationMinutes":60,"reason":"Причина"}]}',
        context: context,
        today: DateTime(2026, 10, 8, 8),
      ),
      throwsFormatException,
    );
  });

  test('accepts a free interval before shift and deadline', () {
    final context = AiPlanningContext(
      tasks: [
        AiTaskContext(
          id: 't1',
          title: 'Task',
          dueAt: DateTime(2026, 10, 8, 12),
        ),
      ],
      goals: const [],
      diary: const [],
      busyBlocks: [
        AiBusyBlock(
          start: DateTime(2026, 10, 8, 10),
          end: DateTime(2026, 10, 8, 20),
          label: 'Смена',
        ),
      ],
    );
    final suggestion = AiSuggestionValidator().parseAndValidate(
      '{"summary":"Ок","recommendations":[{"taskId":"t1","scheduledAt":"2026-10-08T09:00:00","durationMinutes":60,"reason":"До смены"}]}',
      context: context,
      today: DateTime(2026, 10, 8, 8),
    );
    expect(
      suggestion.recommendations.single.scheduledAt,
      DateTime(2026, 10, 8, 9),
    );
  });
}
