import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDate ?? DateTime.now();
    _selected = DateTime(initial.year, initial.month, initial.day);
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
        children: [
          CalendarDatePicker(
            initialDate: _selected,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            onDateChanged: (date) => setState(() => _selected = date),
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              'Задачи',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          FutureBuilder(
            future: widget.repository.listForDay(_selected),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const ListTile(title: Text('Не удалось открыть задачи'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final tasks = snapshot.data!;
              if (tasks.isEmpty) {
                return const ListTile(title: Text('На этот день задач нет'));
              }
              return Column(
                children: tasks
                    .map((task) => ListTile(title: Text(task.title)))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
