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
  late DateTime _month;
  late Future<_MonthData> _monthData;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? DateTime.now();
    _selected = DateTime(initial.year, initial.month, initial.day);
    _tasks = widget.repository.listForDay(_selected);
    _month = DateTime(_selected.year, _selected.month);
    _monthData = _loadMonth();
  }

  Future<_MonthData> _loadMonth() async {
    final month = _month;
    final end = DateTime(month.year, month.month + 1);
    final days = end.subtract(const Duration(days: 1)).day;
    final taskFuture = Future.wait([
      for (var day = 1; day <= days; day++)
        widget.repository.listForDay(DateTime(month.year, month.month, day)),
    ]);
    final shiftFuture = widget.shifts.calendar(month, end);
    final (tasks, shifts) = await (taskFuture, shiftFuture).wait;
    return _MonthData(
      tasks: {for (var day = 1; day <= days; day++) day: tasks[day - 1]},
      shiftDays: {
        for (final shift in shifts)
          if (!shift.cancelled && shift.workStart != null) shift.date.day,
      },
    );
  }

  void _changeMonth(int delta) => setState(() {
    _month = DateTime(_month.year, _month.month + delta);
    _monthData = _loadMonth();
  });

  void _reloadMonth() {
    setState(() {
      _monthData = _loadMonth();
    });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100, 12, 31),
    );
    if (date == null || !mounted) return;
    setState(() {
      _selected = date;
      _tasks = widget.repository.listForDay(date);
      _month = DateTime(date.year, date.month);
      _monthData = _loadMonth();
    });
  }

  Future<void> _openShiftSetup() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => ShiftSetupScreen(repository: widget.shifts),
      ),
    );
    if (saved == true && mounted) _reloadMonth();
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
          _monthGrid(context),
          ShiftCalendarSection(
            key: ValueKey(
              'calendar-shifts-${_selected.year}-${_selected.month}-${_selected.day}',
            ),
            repository: widget.shifts,
            selectedDate: _selected,
            onSetup: _openShiftSetup,
            onChanged: _reloadMonth,
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
              Expanded(
                child: Text(
                  'ТВОЙ КАЛЕНДАРЬ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.mint.withValues(alpha: .95),
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        weekday,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
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
              ),
            ],
          ),
          const SizedBox(height: 13),
          FutureBuilder<List<TaskEntry>>(
            future: _tasks,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox(height: 16);
              final tasks = snapshot.data!;
              final deadlines = tasks
                  .where(
                    (task) =>
                        DateUtils.isSameDay(task.dueAt?.toLocal(), _selected),
                  )
                  .length;
              return Text(
                '${_count(tasks.length, 'задача', 'задачи', 'задач')} · ${_count(deadlines, 'дедлайн', 'дедлайна', 'дедлайнов')}',
                key: const Key('calendar-day-summary'),
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: AppTheme.mint),
              );
            },
          ),
        ],
      ),
    );
  }

  String _count(int count, String one, String few, String many) {
    final last = count % 10;
    final teen = count % 100 >= 11 && count % 100 <= 14;
    return '$count ${teen
        ? many
        : last == 1
        ? one
        : last >= 2 && last <= 4
        ? few
        : many}';
  }

  Widget _monthGrid(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final length = DateTime(_month.year, _month.month + 1, 0).day;
    final offset = _month.weekday - 1;
    final weeks = ((length + offset) / 7).ceil();
    return Card(
      key: const Key('calendar-month-grid'),
      margin: const EdgeInsets.only(top: 12, bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Предыдущий месяц',
                  onPressed: _month.year == 2020 && _month.month == 1
                      ? null
                      : () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _pickDate,
                    child: Text(
                      MaterialLocalizations.of(context).formatMonthYear(_month),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Следующий месяц',
                  onPressed: _month.year == 2100 && _month.month == 12
                      ? null
                      : () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            Row(
              children: [
                for (final day in const [
                  'ПН',
                  'ВТ',
                  'СР',
                  'ЧТ',
                  'ПТ',
                  'СБ',
                  'ВС',
                ])
                  Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            FutureBuilder<_MonthData>(
              future: _monthData,
              builder: (context, snapshot) => Column(
                children: [
                  if (snapshot.hasError)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          const Text(
                            'События месяца недоступны',
                            style: TextStyle(color: AppTheme.coral),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Не удалось загрузить задачи и смены.',
                            textAlign: TextAlign.center,
                          ),
                          TextButton.icon(
                            key: const Key('calendar-month-retry'),
                            onPressed: _reloadMonth,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Повторить загрузку'),
                          ),
                        ],
                      ),
                    ),
                  for (var week = 0; week < weeks; week++)
                    Row(
                      children: [
                        for (var weekday = 0; weekday < 7; weekday++)
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final day = week * 7 + weekday - offset + 1;
                                if (day < 1 || day > length) {
                                  return const SizedBox(height: 48);
                                }
                                final date = DateTime(
                                  _month.year,
                                  _month.month,
                                  day,
                                );
                                final selected = DateUtils.isSameDay(
                                  date,
                                  _selected,
                                );
                                final today = DateUtils.isSameDay(
                                  date,
                                  DateTime.now(),
                                );
                                final data =
                                    snapshot.connectionState ==
                                        ConnectionState.done
                                    ? snapshot.data
                                    : null;
                                final tasks =
                                    data?.tasks[day] ?? const <TaskEntry>[];
                                final deadline = tasks.any(
                                  (task) => DateUtils.isSameDay(
                                    task.dueAt?.toLocal(),
                                    date,
                                  ),
                                );
                                final shift =
                                    data?.shiftDays.contains(day) ?? false;
                                final suffix =
                                    '${date.year}-${date.month}-${date.day}';
                                final eventsLabel = snapshot.hasError
                                    ? 'данные недоступны'
                                    : data == null
                                    ? 'события загружаются'
                                    : '${tasks.length} задач${deadline ? ', есть дедлайн' : ''}${shift ? ', есть смена' : ''}';
                                return Semantics(
                                  label:
                                      '${MaterialLocalizations.of(context).formatFullDate(date)}, $eventsLabel',
                                  selected: selected,
                                  button: true,
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Material(
                                      color: selected
                                          ? scheme.primary
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(13),
                                      child: InkWell(
                                        key: ValueKey('calendar-day-$suffix'),
                                        borderRadius: BorderRadius.circular(13),
                                        onTap: () => setState(() {
                                          _selected = date;
                                          _tasks = widget.repository.listForDay(
                                            date,
                                          );
                                        }),
                                        child: Container(
                                          height: 44,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              13,
                                            ),
                                            border: today && !selected
                                                ? Border.all(
                                                    color: scheme.primary,
                                                  )
                                                : null,
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                '$day',
                                                style: TextStyle(
                                                  color: selected
                                                      ? scheme.onPrimary
                                                      : scheme.onSurface,
                                                  fontWeight: selected || today
                                                      ? FontWeight.w800
                                                      : FontWeight.w500,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              SizedBox(
                                                height: 4,
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    if (tasks.isNotEmpty)
                                                      _dot(
                                                        'calendar-task-marker-$suffix',
                                                        selected
                                                            ? scheme.onPrimary
                                                            : AppTheme.seed,
                                                      ),
                                                    if (deadline)
                                                      _dot(
                                                        'calendar-deadline-marker-$suffix',
                                                        AppTheme.coral,
                                                      ),
                                                    if (shift)
                                                      _dot(
                                                        'calendar-shift-marker-$suffix',
                                                        AppTheme.mint,
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _markerLegend('Задачи', AppTheme.seed),
                _markerLegend('Дедлайны', AppTheme.coral),
                _markerLegend('Смены', AppTheme.mint),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(String key, Color color) => Container(
    key: ValueKey(key),
    width: 4,
    height: 4,
    margin: const EdgeInsets.symmetric(horizontal: 1),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  Widget _markerLegend(String title, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(title, style: const TextStyle(fontSize: 10)),
    ],
  );

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
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
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

class _MonthData {
  const _MonthData({required this.tasks, required this.shiftDays});
  final Map<int, List<TaskEntry>> tasks;
  final Set<int> shiftDays;
}
