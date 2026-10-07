import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/core/models.dart';

void main() {
  test('task retains its ID and optional dates through storage mapping', () {
    final entry = TaskEntry(
      id: 'stable-id',
      title: 'Проверить дату',
      status: 'planned',
      createdAt: DateTime.utc(2026, 10, 7),
      updatedAt: DateTime.utc(2026, 10, 7),
      dueAt: DateTime.utc(2026, 10, 9, 12),
    );

    final restored = TaskEntry.fromMap(entry.toMap());
    expect(restored.id, 'stable-id');
    expect(restored.title, 'Проверить дату');
    expect(restored.status, 'planned');
    expect(restored.dueAt, DateTime.utc(2026, 10, 9, 12));
  });

  test('timer session retains outcome through storage mapping', () {
    final session = TimerSession(
      id: 'session-1',
      kind: 'delay',
      durationSeconds: 600,
      startedAt: DateTime.utc(2026, 10, 7),
      status: 'completed',
      outcome: 'urge passed',
    );
    final restored = TimerSession.fromMap(session.toMap());
    expect(restored.durationSeconds, 600);
    expect(restored.outcome, 'urge passed');
  });
}
