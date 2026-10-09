import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/models.dart';
import '../planning/planning_repository.dart';
import 'breathing_screen.dart';
import 'timer_engine.dart';

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key, required this.engine, required this.planning});

  final TimerEngine engine;
  final PlanningRepository planning;

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  TimerKind _kind = TimerKind.focus;
  Duration _recommended = const Duration(minutes: 45);
  TimerSession? _session;
  List<TaskEntry> _tasks = [];
  TaskEntry? _sessionTask;
  String? _selectedTaskId;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshSession(),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final session = await widget.engine.refresh();
    final hasActiveSession =
        session?.status == 'running' || session?.status == 'paused';
    final kind = hasActiveSession
        ? TimerKind.values.byName(session!.kind)
        : _kind;
    final recommended = await widget.engine.recommended(kind);
    final lists = await Future.wait([
      widget.planning.listForDay(DateTime.now()),
      widget.planning.listUnscheduled(),
    ]);
    final seen = <String>{};
    final tasks = [
      ...lists[0],
      ...lists[1],
    ].where((task) => seen.add(task.id)).toList();
    final sessionTask = hasActiveSession && session?.taskId != null
        ? await widget.planning.taskById(session!.taskId!)
        : null;
    if (!mounted) return;
    setState(() {
      _session = session;
      _sessionTask = sessionTask;
      _kind = kind;
      _selectedTaskId = hasActiveSession ? session!.taskId : null;
      _recommended = recommended;
      _tasks = tasks;
    });
  }

  Future<void> _refreshSession() async {
    final session = await widget.engine.refresh();
    if (mounted) {
      setState(() {
        _session = session;
      });
    }
  }

  Future<void> _selectKind(TimerKind kind) async {
    if (_session?.status == 'running' || _session?.status == 'paused') return;
    final recommended = await widget.engine.recommended(kind);
    if (mounted) {
      setState(() {
        _kind = kind;
        _recommended = recommended;
      });
    }
  }

  Future<void> _start() async {
    if (_kind == TimerKind.focus && _selectedTaskId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Выберите одну задачу')));
      return;
    }
    final session = await widget.engine.start(
      _kind,
      _recommended,
      taskId: _kind == TimerKind.focus ? _selectedTaskId : null,
    );
    if (mounted) {
      setState(() {
        _session = session;
      });
    }
  }

  Future<void> _pause() async {
    await widget.engine.pause();
    await _refreshSession();
  }

  Future<void> _resume() async {
    await widget.engine.resume();
    await _refreshSession();
  }

  Future<void> _finish() async {
    String? outcome;
    if (_session?.kind == TimerKind.delay.name) {
      var draft = '';
      outcome = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Что изменилось?'),
          content: TextField(
            autofocus: true,
            onChanged: (value) => draft = value,
            decoration: const InputDecoration(
              hintText: 'Например, импульс прошёл',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, draft.trim()),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      );
      if (outcome == null) return;
    }
    await widget.engine.finish(outcome: outcome);
    await _refreshSession();
  }

  Future<void> _increase() async {
    await widget.engine.increase(_kind);
    final value = await widget.engine.recommended(_kind);
    if (mounted) {
      setState(() {
        _recommended = value;
      });
    }
  }

  Future<void> _startRecovery() async {
    final session = await widget.engine.start(
      TimerKind.recovery,
      const Duration(minutes: 15),
    );
    if (mounted) {
      setState(() {
        _kind = TimerKind.recovery;
        _recommended = const Duration(minutes: 15);
        _session = session;
      });
    }
  }

  String _time(Duration duration) {
    final seconds = (duration.inMilliseconds / 1000).ceil();
    final minutesPart = (seconds ~/ 60).toString().padLeft(2, '0');
    final secondsPart = (seconds % 60).toString().padLeft(2, '0');
    return '$minutesPart:$secondsPart';
  }

  Color _accentFor(TimerKind kind) => switch (kind) {
    TimerKind.focus => AppTheme.seed,
    TimerKind.recovery => AppTheme.mint,
    TimerKind.delay => AppTheme.coral,
  };

  IconData _iconFor(TimerKind kind) => switch (kind) {
    TimerKind.focus => Icons.bolt_rounded,
    TimerKind.recovery => Icons.spa_rounded,
    TimerKind.delay => Icons.hourglass_bottom_rounded,
  };

  Future<void> _openBreathing() => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const BreathingScreen()),
  );

  Widget _modeSelector(bool active) => Row(
    children: [
      for (final kind in TimerKind.values) ...[
        if (kind != TimerKind.focus) const SizedBox(width: 8),
        Expanded(
          child: _ModeCard(
            kind: kind,
            selected: _kind == kind,
            enabled: !active,
            onTap: () => _selectKind(kind),
          ),
        ),
      ],
    ],
  );

  Widget _taskPicker() => DropdownButtonFormField<String>(
    key: const Key('focusTaskPicker'),
    initialValue: _selectedTaskId,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: _selectedTaskId == null ? 'Выбери задачу' : 'Задача фокуса',
      prefixIcon: const Icon(Icons.check_circle_outline_rounded),
      filled: true,
      fillColor: Colors.white.withValues(alpha: .06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .1)),
      ),
    ),
    items: _tasks
        .map(
          (task) => DropdownMenuItem(
            value: task.id,
            child: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: (value) => setState(() => _selectedTaskId = value),
  );

  Widget _timerHero({required bool active, required Duration duration}) {
    final accent = _accentFor(_kind);
    TaskEntry? selectedTask;
    for (final task in _tasks) {
      if (task.id == _selectedTaskId) {
        selectedTask = task;
        break;
      }
    }
    if (selectedTask == null && _session?.taskId == _selectedTaskId) {
      selectedTask = _sessionTask;
    }
    final sessionDuration = _session == null
        ? _recommended
        : Duration(seconds: _session!.durationSeconds);
    final progress = active && sessionDuration.inMilliseconds > 0
        ? (duration.inMilliseconds / sessionDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 1.0;
    final actionLabel = active
        ? (_session?.status == 'paused' ? 'Продолжить' : 'Пауза')
        : switch (_kind) {
            TimerKind.focus => 'Начать фокус',
            TimerKind.recovery => 'Начать восстановление',
            TimerKind.delay => 'Начать отсрочку',
          };
    final actionIcon = active
        ? (_session?.status == 'paused'
              ? Icons.play_arrow_rounded
              : Icons.pause_rounded)
        : Icons.play_arrow_rounded;

    return Card(
      key: const Key('focus-timer-hero'),
      margin: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: .24),
              AppTheme.surfaceLow,
              AppTheme.surface,
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: .3)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(_iconFor(_kind), color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active
                            ? (_session?.status == 'paused'
                                  ? 'ПАУЗА'
                                  : 'СЕССИЯ ИДЁТ')
                            : 'ВРЕМЯ ДЛЯ ГЛАВНОГО',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        _kind == TimerKind.focus
                            ? 'Один шаг за раз'
                            : _kind == TimerKind.recovery
                            ? 'Верни себе энергию'
                            : 'Дай импульсу пройти',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 218,
              height: 218,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 218,
                    height: 218,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: .18),
                          blurRadius: 42,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    height: 210,
                    child: CircularProgressIndicator(
                      key: const Key('focus-timer-ring'),
                      value: progress,
                      strokeWidth: 10,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Colors.white.withValues(alpha: .1),
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        active ? 'ОСТАЛОСЬ' : 'ТВОЙ РИТМ',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _time(duration),
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(fontSize: 48, color: accent),
                        ),
                      ),
                      Text(
                        _kind == TimerKind.focus
                            ? 'до следующего шага'
                            : _kind == TimerKind.recovery
                            ? '15 минут для себя'
                            : 'спокойно подожди',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_kind == TimerKind.focus) ...[
              const SizedBox(height: 22),
              if (selectedTask != null)
                Container(
                  key: const Key('focus-selected-task'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.flag_rounded, color: accent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          selectedTask.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                )
              else if (!active)
                Text(
                  'Выбери одну задачу — и отдай ей всё внимание.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              if (!active) ...[const SizedBox(height: 12), _taskPicker()],
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('focus-primary-action'),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: const Color(0xFF100E17),
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: active
                    ? (_session?.status == 'paused' ? _resume : _pause)
                    : _start,
                icon: Icon(actionIcon),
                label: Text(actionLabel),
              ),
            ),
            if (active) ...[
              const SizedBox(height: 4),
              TextButton(onPressed: _finish, child: const Text('Завершить')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recoveryCard({required bool active}) => Card(
    key: const Key('recovery-breathing-card'),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppTheme.mint.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.air_rounded, color: AppTheme.mint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Перезагрузка',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '15 минут на отдых и дыхание 4–6–8.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (!active && _kind != TimerKind.recovery)
                      TextButton.icon(
                        onPressed: _startRecovery,
                        icon: const Icon(Icons.spa_rounded),
                        label: const Text('Начать восстановление'),
                      ),
                    TextButton.icon(
                      onPressed: _openBreathing,
                      icon: const Icon(Icons.air_rounded),
                      label: const Text('Дыхание 4–6–8'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final active =
        _session?.status == 'running' || _session?.status == 'paused';
    final duration = active ? widget.engine.remaining(_session) : _recommended;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _modeSelector(active),
        const SizedBox(height: 14),
        _timerHero(active: active, duration: duration),
        const SizedBox(height: 14),
        _recoveryCard(active: active),
        if (!active && _kind != TimerKind.recovery)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: _accentFor(_kind)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Следующий таймер · ${_time(_recommended)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Увеличить следующий таймер',
                    onPressed: _increase,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
          ),
        if (_kind != TimerKind.recovery && _tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Сначала добавь задачу и разбери её в Inbox.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.kind,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final TimerKind kind;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = switch (kind) {
      TimerKind.focus => AppTheme.seed,
      TimerKind.recovery => AppTheme.mint,
      TimerKind.delay => AppTheme.coral,
    };
    final icon = switch (kind) {
      TimerKind.focus => Icons.bolt_rounded,
      TimerKind.recovery => Icons.spa_rounded,
      TimerKind.delay => Icons.hourglass_bottom_rounded,
    };
    final label = switch (kind) {
      TimerKind.focus => 'Фокус',
      TimerKind.recovery => 'Восстановление',
      TimerKind.delay => 'Отсрочка',
    };
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? accent.withValues(alpha: .18) : AppTheme.surfaceLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: .55)
                    : Colors.white.withValues(alpha: .06),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: selected ? accent : Colors.white70),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? accent : Colors.white70,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
