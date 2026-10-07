import 'package:uuid/uuid.dart';

import '../../core/models.dart';
import '../gamification/gamification_service.dart';
import 'timer_repository.dart';

enum TimerKind { focus, recovery, delay }

enum BreathingPhase { inhale, hold, exhale }

class BreathingCycle {
  static BreathingPhase phaseAt(Duration elapsed) {
    final second = (elapsed.inMilliseconds.clamp(0, 1 << 62) % 18000) / 1000;
    if (second < 4) return BreathingPhase.inhale;
    if (second < 10) return BreathingPhase.hold;
    return BreathingPhase.exhale;
  }
}

class TimerEngine {
  TimerEngine(
    this.repository, {
    DateTime Function()? now,
    String Function()? newId,
  }) : _now = now ?? DateTime.now,
       _newId = newId ?? const Uuid().v4;

  final TimerRepository repository;
  final DateTime Function() _now;
  final String Function() _newId;

  Future<TimerSession> start(
    TimerKind kind,
    Duration duration, {
    String? taskId,
  }) async {
    if (kind == TimerKind.focus) {
      if (taskId == null || taskId.isEmpty) {
        throw ArgumentError.value(taskId, 'taskId', 'Выберите одну задачу');
      }
      if (duration < const Duration(minutes: 45) ||
          duration > const Duration(minutes: 90)) {
        throw ArgumentError.value(duration, 'duration', 'Фокус: 45–90 минут');
      }
    }
    if (kind == TimerKind.recovery && duration != const Duration(minutes: 15)) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Восстановление: 15 минут',
      );
    }
    if (kind == TimerKind.delay && duration < const Duration(minutes: 10)) {
      throw ArgumentError.value(duration, 'duration', 'Отсрочка: от 10 минут');
    }
    if (await repository.active() != null) {
      throw StateError('Другой таймер уже запущен');
    }
    final now = _now().toUtc();
    final session = TimerSession(
      id: _newId(),
      kind: kind.name,
      taskId: taskId,
      durationSeconds: duration.inSeconds,
      startedAt: now,
      deadlineAt: now.add(duration),
      remainingSeconds: duration.inSeconds,
      elapsedSeconds: 0,
      status: 'running',
    );
    await repository.create(session);
    await repository.database.remindersChanged();
    return session;
  }

  Duration remaining(TimerSession? session) {
    if (session == null ||
        session.status == 'completed' ||
        session.status == 'cancelled') {
      return Duration.zero;
    }
    if (session.status == 'paused') {
      return Duration(
        seconds: session.remainingSeconds ?? session.durationSeconds,
      );
    }
    final deadline = session.deadlineAt;
    if (deadline == null) {
      return Duration(seconds: session.remainingSeconds ?? 0);
    }
    final difference = deadline.difference(_now().toUtc());
    return difference.isNegative ? Duration.zero : difference;
  }

  TimerSession _changed(
    TimerSession session, {
    required String status,
    required DateTime? deadlineAt,
    required int remainingSeconds,
    DateTime? endedAt,
    String? outcome,
    int? elapsedSeconds,
  }) => TimerSession(
    id: session.id,
    kind: session.kind,
    taskId: session.taskId,
    durationSeconds: session.durationSeconds,
    startedAt: session.startedAt,
    status: status,
    deadlineAt: deadlineAt,
    remainingSeconds: remainingSeconds,
    endedAt: endedAt,
    outcome: outcome,
    elapsedSeconds:
        elapsedSeconds ?? session.durationSeconds - remainingSeconds,
  );

  Future<TimerSession?> refresh() async {
    final session = await repository.active();
    if (session == null) return repository.latest();
    if (session.status == 'running' && remaining(session) == Duration.zero) {
      final completed = _changed(
        session,
        status: 'completed',
        deadlineAt: null,
        remainingSeconds: 0,
        endedAt: _now().toUtc(),
        elapsedSeconds: session.durationSeconds,
      );
      await repository.save(completed);
      if (session.kind == TimerKind.focus.name) {
        await GamificationService(repository.database)
            .awardFocusSession(session.id, occurredAt: _now());
      }
      await repository.database.remindersChanged();
      return completed;
    }
    return session;
  }

  Future<void> pause() async {
    final session = await repository.active();
    if (session == null || session.status != 'running') {
      throw StateError('Таймер не запущен');
    }
    final left = remaining(session).inSeconds;
    await repository.save(
      _changed(
        session,
        status: 'paused',
        deadlineAt: null,
        remainingSeconds: left,
      ),
    );
    if (session.kind == TimerKind.focus.name) {
      await GamificationService(repository.database)
          .awardFocusSession(session.id, occurredAt: _now());
    }
    await repository.database.remindersChanged();
  }

  Future<void> resume() async {
    final session = await repository.active();
    if (session == null || session.status != 'paused') {
      throw StateError('Таймер не на паузе');
    }
    final left = session.remainingSeconds ?? session.durationSeconds;
    await repository.save(
      _changed(
        session,
        status: 'running',
        deadlineAt: _now().toUtc().add(Duration(seconds: left)),
        remainingSeconds: left,
      ),
    );
    await repository.database.remindersChanged();
  }

  Future<void> finish({String? outcome}) async {
    final session = await repository.active();
    if (session == null) throw StateError('Нет активного таймера');
    final left = remaining(session).inSeconds;
    await repository.save(
      _changed(
        session,
        status: 'completed',
        deadlineAt: null,
        remainingSeconds: 0,
        endedAt: _now().toUtc(),
        outcome: outcome,
        elapsedSeconds: session.durationSeconds - left,
      ),
    );
    if (session.kind == TimerKind.focus.name) {
      await GamificationService(repository.database)
          .awardFocusSession(session.id, occurredAt: _now());
    }
    await repository.database.remindersChanged();
  }

  Future<Duration> recommended(TimerKind kind) async {
    if (kind == TimerKind.recovery) return const Duration(minutes: 15);
    final key = '${kind.name}_minutes';
    final defaultMinutes = kind == TimerKind.focus ? 45 : 10;
    return Duration(minutes: await repository.setting(key) ?? defaultMinutes);
  }

  Future<void> increase(TimerKind kind) async {
    if (kind == TimerKind.recovery) return;
    final current = (await recommended(kind)).inMinutes;
    final step =
        await repository.setting('${kind.name}_step_minutes') ??
        (kind == TimerKind.focus ? 5 : 2);
    final maximum = kind == TimerKind.focus ? 90 : 60;
    await repository.setSetting(
      '${kind.name}_minutes',
      (current + step).clamp(1, maximum),
    );
  }

  Future<void> setStep(TimerKind kind, Duration step) async {
    if (kind == TimerKind.recovery || step.inMinutes < 1) {
      throw ArgumentError.value(step, 'step');
    }
    await repository.setSetting('${kind.name}_step_minutes', step.inMinutes);
  }
}
