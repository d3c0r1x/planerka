import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/timers/timer_engine.dart';
import 'package:planerka/features/timers/timer_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late AppDatabase database;
  late TimerRepository repository;
  late TimerEngine engine;
  late DateTime current;
  var id = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_timers_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    current = DateTime.utc(2026, 10, 8, 12);
    id = 0;
    repository = TimerRepository(database);
    engine = TimerEngine(
      repository,
      now: () => current,
      newId: () => 'timer-${++id}',
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('focus needs one task, pauses, resumes and completes once', () async {
    await expectLater(
      engine.start(TimerKind.focus, const Duration(minutes: 45)),
      throwsArgumentError,
    );
    final task = await InboxRepository(database).add('Учить Go');
    await engine.start(
      TimerKind.focus,
      const Duration(minutes: 45),
      taskId: task.id,
    );

    current = current.add(const Duration(minutes: 10));
    expect(
      engine.remaining(await engine.refresh()),
      const Duration(minutes: 35),
    );
    await engine.pause();
    current = current.add(const Duration(hours: 1));
    expect(
      engine.remaining(await engine.refresh()),
      const Duration(minutes: 35),
    );
    await engine.resume();
    current = current.add(const Duration(minutes: 35));
    expect((await engine.refresh())?.status, 'completed');
    expect((await engine.refresh())?.status, 'completed');
    expect(await repository.completed(), hasLength(1));
  });

  test(
    'running timer survives service recreation and stores delay outcome',
    () async {
      await engine.start(TimerKind.delay, const Duration(minutes: 10));
      current = current.add(const Duration(minutes: 3));
      final restored = TimerEngine(repository, now: () => current);
      expect(
        restored.remaining(await restored.refresh()),
        const Duration(minutes: 7),
      );
      await restored.finish(outcome: 'Импульс прошёл');
      expect((await repository.completed()).single.outcome, 'Импульс прошёл');
      expect((await repository.completed()).single.elapsedSeconds, 180);
    },
  );

  test('recommended durations increase inside focus bounds', () async {
    expect(
      await engine.recommended(TimerKind.focus),
      const Duration(minutes: 45),
    );
    expect(
      await engine.recommended(TimerKind.recovery),
      const Duration(minutes: 15),
    );
    expect(
      await engine.recommended(TimerKind.delay),
      const Duration(minutes: 10),
    );
    await engine.increase(TimerKind.focus);
    await engine.increase(TimerKind.delay);
    expect(
      await engine.recommended(TimerKind.focus),
      const Duration(minutes: 50),
    );
    expect(
      await engine.recommended(TimerKind.delay),
      const Duration(minutes: 12),
    );
    await engine.setStep(TimerKind.delay, const Duration(minutes: 3));
    await engine.increase(TimerKind.delay);
    expect(
      await engine.recommended(TimerKind.delay),
      const Duration(minutes: 15),
    );
    for (var i = 0; i < 20; i++) {
      await engine.increase(TimerKind.focus);
    }
    expect(
      await engine.recommended(TimerKind.focus),
      const Duration(minutes: 90),
    );
    await expectLater(
      engine.start(TimerKind.focus, const Duration(minutes: 44), taskId: 'x'),
      throwsArgumentError,
    );
    await expectLater(
      engine.start(TimerKind.focus, const Duration(minutes: 91), taskId: 'x'),
      throwsArgumentError,
    );
  });

  test('breathing follows 4 second inhale, 6 second hold, 8 second exhale', () {
    expect(
      BreathingCycle.phaseAt(const Duration(seconds: 0)),
      BreathingPhase.inhale,
    );
    expect(
      BreathingCycle.phaseAt(const Duration(seconds: 4)),
      BreathingPhase.hold,
    );
    expect(
      BreathingCycle.phaseAt(const Duration(seconds: 10)),
      BreathingPhase.exhale,
    );
    expect(
      BreathingCycle.phaseAt(const Duration(seconds: 18)),
      BreathingPhase.inhale,
    );
  });
}
