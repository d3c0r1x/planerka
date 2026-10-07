import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'planning_repository.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.repository});

  final PlanningRepository repository;

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

  Future<void> _schedule(TaskEntry task) async {
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
    await widget.repository.schedule(
      task.id,
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
    if (mounted) _refresh();
  }

  Widget _taskTile(TaskEntry task, {bool backlog = false}) => Card(
    child: ListTile(
      title: Text(task.title),
      subtitle: task.dueAt == null
          ? null
          : Text(
              'Срок: ${MaterialLocalizations.of(context).formatMediumDate(task.dueAt!.toLocal())}',
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (backlog)
            IconButton(
              tooltip: 'На сегодня',
              onPressed: () => _selectToday(task),
              icon: const Icon(Icons.today_rounded),
            ),
          IconButton(
            tooltip: 'Назначить срок',
            onPressed: () => _schedule(task),
            icon: const Icon(Icons.event_rounded),
          ),
          IconButton(
            tooltip: 'Завершить',
            onPressed: () => _complete(task),
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
              ...plan.overdue.map(_taskTile),
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
