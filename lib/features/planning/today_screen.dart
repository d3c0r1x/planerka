import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'planning_repository.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.repository,
    this.interactive = true,
    this.onReviewMissed,
  });

  final PlanningRepository repository;
  final bool interactive;
  final Future<void> Function(String taskId)? onReviewMissed;

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
    child: ListTile(
      title: Text(task.title),
      subtitle: task.dueAt == null && task.scheduledAt == null
          ? null
          : Text(
              [
                if (task.scheduledAt != null)
                  'План: ${MaterialLocalizations.of(context).formatMediumDate(task.scheduledAt!.toLocal())}, ${TimeOfDay.fromDateTime(task.scheduledAt!.toLocal()).format(context)} · ${task.estimatedMinutes ?? 30} мин',
                if (task.dueAt != null)
                  'Дедлайн: ${MaterialLocalizations.of(context).formatMediumDate(task.dueAt!.toLocal())}',
              ].join('\n'),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (missed)
            IconButton(
              tooltip: 'Разобрать пропуск',
              onPressed: widget.interactive ? () => _reviewMissed(task) : null,
              icon: const Icon(Icons.psychology_alt_rounded),
            ),
          if (backlog)
            IconButton(
              tooltip: 'На сегодня',
              onPressed: widget.interactive ? () => _selectToday(task) : null,
              icon: const Icon(Icons.today_rounded),
            ),
          IconButton(
            tooltip: 'Напомнить',
            onPressed: widget.interactive ? () => _setReminder(task) : null,
            icon: const Icon(Icons.notifications_active_rounded),
          ),
          IconButton(
            tooltip: 'Запланировать время',
            onPressed: widget.interactive ? () => _scheduleBlock(task) : null,
            icon: const Icon(Icons.schedule_rounded),
          ),
          if (task.scheduledAt != null)
            IconButton(
              tooltip: 'Убрать время',
              onPressed: widget.interactive
                  ? () => _clearScheduleBlock(task)
                  : null,
              icon: const Icon(Icons.event_busy_rounded),
            ),
          IconButton(
            tooltip: 'Назначить срок',
            onPressed: widget.interactive ? () => _schedule(task) : null,
            icon: const Icon(Icons.event_rounded),
          ),
          IconButton(
            tooltip: 'Завершить',
            onPressed: widget.interactive ? () => _complete(task) : null,
            icon: const Icon(Icons.check_circle_outline_rounded),
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
        if (plan.today.isEmpty &&
            plan.overdue.isEmpty &&
            plan.unscheduled.isEmpty) {
          return const Center(child: Text('Ваш день начинается здесь'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (plan.overdue.isNotEmpty) ...[
              Text('Просрочено', style: Theme.of(context).textTheme.titleLarge),
              ...plan.overdue.map((task) => _taskTile(task, missed: true)),
              const SizedBox(height: 16),
            ],
            Text('Сегодня', style: Theme.of(context).textTheme.titleLarge),
            if (plan.today.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('На сегодня пока ничего не выбрано.'),
              ),
            ...plan.today.map(_taskTile),
            if (plan.unscheduled.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('К выбору', style: Theme.of(context).textTheme.titleLarge),
              ...plan.unscheduled.map((task) => _taskTile(task, backlog: true)),
            ],
          ],
        );
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
