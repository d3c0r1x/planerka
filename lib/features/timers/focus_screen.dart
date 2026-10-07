import 'dart:async';

import 'package:flutter/material.dart';

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
    final recommended = await widget.engine.recommended(_kind);
    final lists = await Future.wait([
      widget.planning.listForDay(DateTime.now()),
      widget.planning.listUnscheduled(),
    ]);
    final seen = <String>{};
    final tasks = [
      ...lists[0],
      ...lists[1],
    ].where((task) => seen.add(task.id)).toList();
    if (!mounted) return;
    setState(() {
      _session = session;
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

  @override
  Widget build(BuildContext context) {
    final active =
        _session?.status == 'running' || _session?.status == 'paused';
    final duration = active ? widget.engine.remaining(_session) : _recommended;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final kind in TimerKind.values)
              ChoiceChip(
                label: Text(switch (kind) {
                  TimerKind.focus => 'Фокус',
                  TimerKind.recovery => 'Восстановление',
                  TimerKind.delay => 'Отсрочка',
                }),
                selected: _kind == kind,
                onSelected: active ? null : (_) => _selectKind(kind),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            _time(duration),
            style: Theme.of(context).textTheme.displayLarge,
          ),
        ),
        const SizedBox(height: 16),
        if (_kind == TimerKind.focus && !active)
          DropdownButtonFormField<String>(
            key: const Key('focusTaskPicker'),
            initialValue: _selectedTaskId,
            decoration: const InputDecoration(
              labelText: 'Одна задача для фокуса',
            ),
            items: _tasks
                .map(
                  (task) =>
                      DropdownMenuItem(value: task.id, child: Text(task.title)),
                )
                .toList(),
            onChanged: (value) => setState(() => _selectedTaskId = value),
          ),
        if (_kind == TimerKind.focus && !active && _tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Сначала добавьте задачу и разберите её в Inbox.'),
          ),
        const SizedBox(height: 16),
        if (!active)
          FilledButton(
            onPressed: _start,
            child: Text(switch (_kind) {
              TimerKind.focus => 'Начать фокус',
              TimerKind.recovery => 'Начать восстановление',
              TimerKind.delay => 'Начать отсрочку',
            }),
          ),
        if (active) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _session?.status == 'paused' ? _resume : _pause,
                  child: Text(
                    _session?.status == 'paused' ? 'Продолжить' : 'Пауза',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _finish,
                  child: const Text('Завершить'),
                ),
              ),
            ],
          ),
        ],
        if (!active &&
            _session?.status == 'completed' &&
            _session?.kind == TimerKind.focus.name)
          TextButton(
            onPressed: _startRecovery,
            child: const Text('Начать восстановление'),
          ),
        if (!active && _kind != TimerKind.recovery)
          TextButton(
            onPressed: _increase,
            child: const Text('Увеличить следующий таймер'),
          ),
        if (_kind == TimerKind.recovery)
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const BreathingScreen()),
            ),
            icon: const Icon(Icons.air_rounded),
            label: const Text('Дыхание 4–6–8'),
          ),
      ],
    );
  }
}
