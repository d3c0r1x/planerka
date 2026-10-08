import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/models.dart';
import 'planning_repository.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.repository,
    this.interactive = true,
    this.onReviewMissed,
    this.embedded = false,
    this.onChanged,
  });

  final PlanningRepository repository;
  final bool interactive;
  final Future<void> Function(String taskId)? onReviewMissed;
  final bool embedded;
  final VoidCallback? onChanged;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late Future<_DayPlan> _plan;

  @override
  void initState() {
    super.initState();
    _plan = _load();
  }

  Future<_DayPlan> _load() async {
    final now = DateTime.now();
    final lists = await Future.wait([
      widget.repository.listForDay(now),
      widget.repository.listOverdue(now),
      widget.repository.listUnscheduled(),
    ]);
    final todayIds = lists[0].map((task) => task.id).toSet();
    return _DayPlan(
      today: lists[0],
      overdue: lists[1].where((task) => !todayIds.contains(task.id)).toList(),
      unscheduled: lists[2],
    );
  }

  void _refresh() {
    setState(() {
      _plan = _load();
    });
    widget.onChanged?.call();
  }

  Future<void> _selectToday(TaskEntry task) async {
    await widget.repository.setToday(task.id, DateTime.now());
    if (mounted) _refresh();
  }

  Future<void> _complete(TaskEntry task) async {
    await widget.repository.complete(task.id);
    if (mounted) _refresh();
  }

  Future<void> _reviewMissed(TaskEntry task) async {
    final review = widget.onReviewMissed;
    if (review == null) return;
    await review(task.id);
    if (mounted) _refresh();
  }

  Future<void> _schedule(TaskEntry task) async {
    await _pickDateTime(task, reminder: false);
  }

  Future<void> _setReminder(TaskEntry task) async {
    await _pickDateTime(task, reminder: true);
  }

  Future<void> _scheduleBlock(TaskEntry task) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: task.scheduledAt ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: task.scheduledAt == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(task.scheduledAt!.toLocal()),
    );
    if (time == null || !mounted) return;
    var minutes = task.estimatedMinutes ?? 30;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Длительность задачи'),
        content: DropdownButtonFormField<int>(
          initialValue: minutes,
          items: [15, 30, 45, 60, 90, 120, 180]
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text('$value минут')),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) minutes = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await widget.repository.setScheduleBlock(
        task.id,
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
        minutes,
      );
      if (mounted) _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось запланировать задачу: $error')),
      );
    }
  }

  Future<void> _clearScheduleBlock(TaskEntry task) async {
    await widget.repository.clearScheduleBlock(task.id);
    if (mounted) _refresh();
  }

  Future<void> _pickDateTime(TaskEntry task, {required bool reminder}) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: task.dueAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null) return;
    final at = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (reminder) {
      await widget.repository.setReminder(task.id, at);
    } else {
      await widget.repository.schedule(task.id, at);
    }
    if (mounted) _refresh();
  }

  Widget _taskTile(
    TaskEntry task, {
    bool backlog = false,
    bool missed = false,
  }) => Card(
    key: ValueKey('today-task-${task.id}'),
    margin: const EdgeInsets.symmetric(vertical: 5),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 4, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: missed
                  ? AppTheme.coral
                  : backlog
                  ? AppTheme.seed
                  : AppTheme.mint,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: Theme.of(context).textTheme.titleSmall),
                if (task.dueAt != null || task.scheduledAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (task.scheduledAt != null)
                        'План: ${MaterialLocalizations.of(context).formatMediumDate(task.scheduledAt!.toLocal())}, ${TimeOfDay.fromDateTime(task.scheduledAt!.toLocal()).format(context)} · ${task.estimatedMinutes ?? 30} мин',
                      if (task.dueAt != null)
                        'Дедлайн: ${MaterialLocalizations.of(context).formatMediumDate(task.dueAt!.toLocal())}',
                    ].join('\n'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filledTonal(
                tooltip: backlog ? 'На сегодня' : 'Завершить',
                onPressed: widget.interactive
                    ? () => backlog ? _selectToday(task) : _complete(task)
                    : null,
                icon: Icon(
                  backlog ? Icons.add_rounded : Icons.check_rounded,
                  size: 19,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Действия задачи',
                enabled: widget.interactive,
                icon: const Icon(Icons.more_horiz_rounded, size: 20),
                onSelected: (value) {
                  switch (value) {
                    case 'review':
                      _reviewMissed(task);
                    case 'reminder':
                      _setReminder(task);
                    case 'time':
                      _scheduleBlock(task);
                    case 'clear':
                      _clearScheduleBlock(task);
                    case 'deadline':
                      _schedule(task);
                    case 'complete':
                      _complete(task);
                  }
                },
                itemBuilder: (_) => [
                  if (missed)
                    const PopupMenuItem(
                      value: 'review',
                      child: Text('Разобрать пропуск'),
                    ),
                  const PopupMenuItem(
                    value: 'reminder',
                    child: Text('Напомнить'),
                  ),
                  const PopupMenuItem(
                    value: 'time',
                    child: Text('Запланировать время'),
                  ),
                  if (task.scheduledAt != null)
                    const PopupMenuItem(
                      value: 'clear',
                      child: Text('Убрать время'),
                    ),
                  const PopupMenuItem(
                    value: 'deadline',
                    child: Text('Назначить срок'),
                  ),
                  if (backlog)
                    const PopupMenuItem(
                      value: 'complete',
                      child: Text('Завершить'),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DayPlan>(
      future: _plan,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Не удалось открыть план: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final plan = snapshot.data!;
        final children = <Widget>[
          Text(
            'Сегодня',
            key: const Key('home-today-section'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (plan.today.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('На сегодня пока ничего не выбрано.'),
            ),
          ...plan.today.map(_taskTile),
          if (plan.overdue.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Просрочено', style: Theme.of(context).textTheme.titleLarge),
            ...plan.overdue.map((task) => _taskTile(task, missed: true)),
          ],
          if (plan.unscheduled.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('К выбору', style: Theme.of(context).textTheme.titleLarge),
            ...plan.unscheduled.map((task) => _taskTile(task, backlog: true)),
          ],
        ];
        if (widget.embedded) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          );
        }
        return ListView(padding: const EdgeInsets.all(16), children: children);
      },
    );
  }
}

class _DayPlan {
  const _DayPlan({
    required this.today,
    required this.overdue,
    required this.unscheduled,
  });

  final List<TaskEntry> today;
  final List<TaskEntry> overdue;
  final List<TaskEntry> unscheduled;
}
