import 'package:flutter/material.dart';

import 'shift_models.dart';
import 'shift_repository.dart';

class ShiftCalendarSection extends StatefulWidget {
  const ShiftCalendarSection({
    super.key,
    required this.repository,
    required this.selectedDate,
    this.onSetup,
  });

  final ShiftRepository repository;
  final DateTime selectedDate;
  final VoidCallback? onSetup;

  @override
  State<ShiftCalendarSection> createState() => _ShiftCalendarSectionState();
}

class _ShiftCalendarSectionState extends State<ShiftCalendarSection> {
  late Future<({List<ShiftTeam> teams, List<ShiftDayStatus> days})> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant ShiftCalendarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) _reload();
  }

  void _reload() {
    _data = _load();
  }

  Future<({List<ShiftTeam> teams, List<ShiftDayStatus> days})> _load() async {
    final date = widget.selectedDate;
    final teams = await widget.repository.listTeams();
    final days = await widget.repository.calendar(
      date,
      DateTime(date.year, date.month, date.day + 1),
    );
    return (teams: teams, days: days);
  }

  String _phaseLabel(ShiftPhase phase) => switch (phase) {
    ShiftPhase.day => 'Дневная',
    ShiftPhase.preNightRest => 'Отдых перед ночью',
    ShiftPhase.night => 'Ночная',
    ShiftPhase.recovery => 'Отсыпной',
    ShiftPhase.rest => 'Выходной',
  };

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _endDate(DateTime value) => '${value.day} ${_month(value.month)}.';

  String _month(int month) => const [
    'янв',
    'фев',
    'мар',
    'апр',
    'май',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ][month - 1];

  String _timeLabel(ShiftDayStatus status) {
    if (status.cancelled) return 'Смена отменена';
    if (status.workStart == null || status.workEnd == null) {
      return 'Без рабочей смены';
    }
    final work = '${_time(status.workStart!)}–${_time(status.workEnd!)}';
    final blockStart = status.blockStart;
    final blockEnd = status.blockEnd;
    if (blockStart == null || blockEnd == null) return 'Работа $work';
    final commute = '${_time(blockStart)}–${_time(blockEnd)}';
    final nextDay = blockEnd.day != status.date.day;
    return 'Работа $work · дорога $commute${nextDay ? ' · до ${_endDate(blockEnd)}' : ''}';
  }

  Future<void> _recordAttendance(ShiftTeam team) async {
    final value = await showDialog<ShiftAttendance>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Посещение · ${team.name}'),
        content: const Text('Отметь, в чью смену сегодня ходил.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ShiftAttendance.missed),
            child: const Text('Пропустил'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ShiftAttendance.attended),
            child: const Text('Ходил'),
          ),
        ],
      ),
    );
    if (value == null) return;
    await widget.repository.setAttendance(team.id, widget.selectedDate, value);
    if (mounted) setState(_reload);
  }

  Future<void> _editDate(ShiftDayStatus status) async {
    var phase = status.phase;
    var cancelled = status.cancelled;
    final value = await showDialog<ShiftOverride>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Изменить эту дату'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<ShiftPhase>(
                key: const Key('override-phase-select'),
                initialValue: phase,
                decoration: const InputDecoration(labelText: 'Фаза смены'),
                items: [
                  for (final value in ShiftPhase.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_phaseLabel(value)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) updateDialog(() => phase = value);
                },
              ),
              SwitchListTile(
                key: const Key('override-cancel-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Смену отменили'),
                value: cancelled,
                onChanged: (value) => updateDialog(() => cancelled = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('save-shift-override'),
              onPressed: () => Navigator.pop(
                context,
                ShiftOverride(
                  teamId: status.teamId,
                  date: widget.selectedDate,
                  phase: phase,
                  cancelled: cancelled,
                ),
              ),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (value == null) return;
    await widget.repository.setDayOverride(value);
    if (mounted) setState(_reload);
  }

  Future<void> _adjustFuture(ShiftDayStatus status) async {
    final delta = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Изменить этот и будущие дни'),
        content: const Text(
          'Сдвинуть цикл смены относительно исходного графика?',
        ),
        actions: [
          TextButton(
            key: ValueKey('shift-adjust-backward-${status.teamId}'),
            onPressed: () => Navigator.pop(context, -1),
            child: const Text('Назад на день'),
          ),
          FilledButton(
            key: ValueKey('shift-adjust-forward-${status.teamId}'),
            onPressed: () => Navigator.pop(context, 1),
            child: const Text('Вперёд на день'),
          ),
        ],
      ),
    );
    if (delta == null) return;
    await widget.repository.adjustFrom(
      ShiftPhaseAdjustment(
        teamId: status.teamId,
        effectiveDate: widget.selectedDate,
        deltaDays: delta,
      ),
    );
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<({List<ShiftTeam> teams, List<ShiftDayStatus> days})>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Card(
              child: ListTile(title: Text('Не удалось открыть смены')),
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final teams = snapshot.data!.teams;
          final days = snapshot.data!.days;
          if (teams.isEmpty || days.isEmpty) {
            return Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_month_rounded),
                title: const Text('Настроить график смен'),
                subtitle: const Text('Добавь четыре команды и руководителей'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: widget.onSetup,
              ),
            );
          }
          final byId = {for (final team in teams) team.id: team};
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text(
                  'Смены на день',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              for (final status in days)
                if (byId[status.teamId] case final team?)
                  _teamCard(team, status),
            ],
          );
        },
      );

  Widget _teamCard(ShiftTeam team, ShiftDayStatus status) {
    final color = Color(team.colorValue);
    return Card(
      key: ValueKey('shift-day-${team.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 5,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${team.name} · ${status.cancelled ? 'Отменена' : _phaseLabel(status.phase)}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(team.leaderName),
                      Text(
                        _timeLabel(status),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('edit-shift-${team.id}'),
                  tooltip: 'Изменить смену ${team.name}',
                  onPressed: () => _editDate(status),
                  icon: const Icon(Icons.edit_calendar_rounded),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Сдвиг будущего графика',
                  onSelected: (value) {
                    if (value == 'adjust') _adjustFuture(status);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      key: ValueKey('shift-adjust-forward-${team.id}'),
                      value: 'adjust',
                      child: const Text('Сдвинуть цикл…'),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert_rounded),
                ),
              ],
            ),
            if (team.attends)
              Align(
                alignment: Alignment.centerRight,
                child: FutureBuilder<ShiftAttendance?>(
                  future: widget.repository.attendanceFor(
                    team.id,
                    widget.selectedDate,
                  ),
                  builder: (context, attendance) => OutlinedButton.icon(
                    key: ValueKey('attendance-${team.id}'),
                    onPressed: () => _recordAttendance(team),
                    icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                    label: Text(switch (attendance.data) {
                      ShiftAttendance.attended => 'Ходил',
                      ShiftAttendance.missed => 'Пропустил',
                      null => 'Отметить посещение',
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
