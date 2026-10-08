import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/models.dart';
import '../shifts/shift_calendar_section.dart';
import '../shifts/shift_repository.dart';
import '../shifts/shift_setup_screen.dart';
import 'planning_repository.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.repository,
    required this.shifts,
    this.initialDate,
  });

  final PlanningRepository repository;
  final ShiftRepository shifts;
  final DateTime? initialDate;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _selected;
  late Future<List<TaskEntry>> _tasks;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? DateTime.now();
    _selected = DateTime(initial.year, initial.month, initial.day);
    _tasks = widget.repository.listForDay(_selected);
  }

  Future<void> _openShiftSetup() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => ShiftSetupScreen(repository: widget.shifts),
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Календарь'),
        actions: [
          IconButton(
            key: const Key('open-shift-settings'),
            tooltip: 'Настроить график смен',
            onPressed: _openShiftSetup,
            icon: const Icon(Icons.groups_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        children: [
          _selectedDayCard(context),
          Card(
            margin: const EdgeInsets.only(top: 12, bottom: 6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: CalendarDatePicker(
                initialDate: _selected,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                onDateChanged: (date) => setState(() {
                  _selected = date;
                  _tasks = widget.repository.listForDay(date);
                }),
              ),
            ),
          ),
          ShiftCalendarSection(
            key: ValueKey(
              'calendar-shifts-${_selected.year}-${_selected.month}-${_selected.day}',
            ),
            repository: widget.shifts,
            selectedDate: _selected,
            onSetup: _openShiftSetup,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 4),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.seed.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.checklist_rounded,
                    color: AppTheme.seed,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Задачи дня',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          FutureBuilder<List<TaskEntry>>(
            future: _tasks,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const ListTile(title: Text('Не удалось открыть задачи'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final tasks = snapshot.data!;
              if (tasks.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.spa_rounded, color: AppTheme.mint),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'На этот день задач нет',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: tasks
                    .map((task) => _taskCard(context, task))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _selectedDayCard(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final isToday = DateUtils.isSameDay(_selected, DateTime.now());
    final dateLabel = localizations.formatMediumDate(_selected);
    final weekday = _weekday(_selected.weekday);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('calendar-selected-day-card'),
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102B2B), Color(0xFF171C27), Color(0xFF201A34)],
        ),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: AppTheme.mint.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.mint.withValues(alpha: .08),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                color: AppTheme.mint,
                size: 19,
              ),
              const SizedBox(width: 8),
              Text(
                'ТВОЙ КАЛЕНДАРЬ',
                style: TextStyle(
                  color: AppTheme.mint.withValues(alpha: .95),
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: (isToday ? AppTheme.mint : AppTheme.seed).withValues(
                    alpha: .15,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isToday ? 'СЕГОДНЯ' : 'ВЫБРАННАЯ ДАТА',
                  style: TextStyle(
                    color: isToday ? AppTheme.mint : scheme.primary,
                    fontSize: 9,
                    letterSpacing: .5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_selected.day}',
                style: Theme.of(context).textTheme.displaySmall
                    ?.copyWith(color: Colors.white, fontSize: 46, height: .95),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      weekday,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      dateLabel,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _legendChip(Icons.groups_rounded, 'Смены', AppTheme.mint),
              _legendChip(Icons.task_alt_rounded, 'Задачи', AppTheme.seed),
              _legendChip(
                Icons.notifications_active_rounded,
                'Дедлайны',
                AppTheme.coral,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendChip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .22)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _taskCard(BuildContext context, TaskEntry task) {
    final localizations = MaterialLocalizations.of(context);
    final dueAt = task.dueAt?.toLocal();
    final scheduledAt = task.scheduledAt?.toLocal();
    final isOverdue = dueAt != null && dueAt.isBefore(DateTime.now());
    final dueColor = isOverdue ? const Color(0xFFFF718B) : AppTheme.coral;
    String time(DateTime value) =>
        TimeOfDay.fromDateTime(value).format(context);
    final planText = scheduledAt == null
        ? null
        : '${localizations.formatMediumDate(scheduledAt)}, ${time(scheduledAt)} · ${task.estimatedMinutes ?? 30} мин';
    final dueText = dueAt == null
        ? null
        : '${isOverdue ? 'Просрочено' : 'Дедлайн'} · ${localizations.formatMediumDate(dueAt)}${dueAt.hour == 0 && dueAt.minute == 0 ? '' : ', ${time(dueAt)}'}';
    return Card(
      key: ValueKey('calendar-task-${task.id}'),
      margin: const EdgeInsets.only(top: 6, bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 42,
              decoration: BoxDecoration(
                color: dueAt == null ? AppTheme.seed : dueColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (planText != null || dueText != null) ...[
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        if (planText != null)
                          _legendChip(
                            Icons.schedule_rounded,
                            planText,
                            AppTheme.mint,
                          ),
                        if (dueText != null)
                          Container(
                            key: ValueKey('calendar-task-deadline-${task.id}'),
                            child: _legendChip(
                              Icons.flag_rounded,
                              dueText,
                              dueColor,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _weekday(int value) => const [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ][value - 1];
}
