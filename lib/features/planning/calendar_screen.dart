import 'package:flutter/material.dart';

import 'planning_repository.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.repository});

  final PlanningRepository repository;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Календарь')),
      body: ListView(
        children: [
          CalendarDatePicker(
            initialDate: _selected,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            onDateChanged: (date) => setState(() => _selected = date),
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
