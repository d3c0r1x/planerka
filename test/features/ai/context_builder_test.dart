import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/ai/planning/ai_context_builder.dart';

void main() {
  test('omits diary entries when personalization is disabled', () {
    final context = AiContextBuilder().build(
      tasks: const [AiTaskContext(id: 't1', title: 'Прочитать главу')],
      goals: const [
        AiGoalContext(id: 'g1', title: 'Читать чаще', progress: 2, target: 10),
      ],
      diary: const [AiMoodContext(day: '2026-10-08', mood: 2, note: 'Устал')],
      includeDiary: false,
    );
    final payload = context.toJson();
    expect(payload['tasks'], hasLength(1));
    expect(payload['goals'], hasLength(1));
    expect(payload, isNot(contains('diary')));
    expect(payload.toString(), isNot(contains('Устал')));
  });

  test('includes recent mood notes only when user enabled diary context', () {
    final context = AiContextBuilder().build(
      tasks: const [],
      goals: const [],
      diary: const [AiMoodContext(day: '2026-10-08', mood: 2, note: 'Устал')],
      includeDiary: true,
    );
    expect(context.toJson()['diary'], [
      {'day': '2026-10-08', 'mood': 2, 'note': 'Устал'},
    ]);
  });

  test('limits context size and trims private text fields', () {
    final context = AiContextBuilder().build(
      tasks: List.generate(
        80,
        (index) => AiTaskContext(
          id: 't$index',
          title: 'T$index' * 100,
          notes: 'N' * 1000,
        ),
      ),
      goals: List.generate(
        20,
        (index) => AiGoalContext(
          id: 'g$index',
          title: 'G$index',
          progress: 0,
          target: 5,
        ),
      ),
      diary: List.generate(
        20,
        (index) =>
            AiMoodContext(day: '2026-10-08', mood: 4, note: 'note' * 100),
      ),
      includeDiary: true,
    );
    final payload = context.toJson();
    expect((payload['tasks'] as List), hasLength(50));
    expect((payload['goals'] as List), hasLength(10));
    expect((payload['diary'] as List), hasLength(7));
    expect(
      ((payload['tasks'] as List).first as Map)['title'].toString().length,
      lessThanOrEqualTo(120),
    );
    expect(
      ((payload['diary'] as List).first as Map)['note'].toString().length,
      lessThanOrEqualTo(240),
    );
  });
}
