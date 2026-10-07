import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/ai/planning/ai_context_builder.dart';
import 'package:planerka/features/ai/planning/ai_suggestion.dart';

void main() {
  final validator = AiSuggestionValidator();
  final context = AiPlanningContext(
    tasks: const [
      AiTaskContext(id: 't1', title: 'Прогуляться'),
      AiTaskContext(id: 't2', title: 'Позвонить в вуз'),
    ],
    goals: const [],
    diary: const [],
  );
  final today = DateTime(2026, 10, 8);

  test('parses JSON fence and validates existing task IDs', () {
    final suggestion = validator.parseAndValidate(
      '''
      ```json
      {"summary":"Начни с короткого дела","recommendations":[{"taskId":"t1","day":"2026-10-08","reason":"Займёт мало времени"}]}
      ```
    ''',
      context: context,
      today: today,
    );
    expect(suggestion.summary, 'Начни с короткого дела');
    expect(suggestion.recommendations.single.taskId, 't1');
  });

  test('rejects empty or invalid JSON response', () {
    expect(
      () => validator.parseAndValidate('', context: context, today: today),
      throwsFormatException,
    );
    expect(
      () => validator.parseAndValidate(
        'not json',
        context: context,
        today: today,
      ),
      throwsFormatException,
    );
  });

  test(
    'rejects unknown task, past date, duplicate task and excess proposals',
    () {
      for (final json in [
        '{"summary":"x","recommendations":[{"taskId":"ghost","day":"2026-10-08","reason":"x"}]}',
        '{"summary":"x","recommendations":[{"taskId":"t1","day":"2026-10-07","reason":"x"}]}',
        '{"summary":"x","recommendations":[{"taskId":"t1","day":"2026-10-08","reason":"x"},{"taskId":"t1","day":"2026-10-09","reason":"y"}]}',
        '{"summary":"x","recommendations":[{"taskId":"t1","day":"2026-10-08","reason":"x"},{"taskId":"t2","day":"2026-10-09","reason":"y"},{"taskId":"t3","day":"2026-10-10","reason":"z"},{"taskId":"t4","day":"2026-10-11","reason":"z"},{"taskId":"t5","day":"2026-10-12","reason":"z"},{"taskId":"t6","day":"2026-10-13","reason":"z"}]}',
      ]) {
        expect(
          () =>
              validator.parseAndValidate(json, context: context, today: today),
          throwsFormatException,
        );
      }
    },
  );

  test('applies only selected preview actions', () {
    final suggestion = validator.parseAndValidate(
      '{"summary":"Выбери","recommendations":[{"taskId":"t1","day":"2026-10-08","reason":"Первое"},{"taskId":"t2","day":"2026-10-09","reason":"Второе"}]}',
      context: context,
      today: today,
    );
    final selected = suggestion.select({'t2'});
    expect(selected.map((item) => item.taskId), ['t2']);
    expect(suggestion.select({}), isEmpty);
  });
}
