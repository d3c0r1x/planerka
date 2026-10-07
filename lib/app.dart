import 'package:flutter/material.dart';

import 'core/app_database.dart';
import 'features/inbox/inbox_repository.dart';
import 'features/inbox/inbox_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/planning/calendar_screen.dart';
import 'features/planning/planning_repository.dart';
import 'features/planning/projects_screen.dart';
import 'features/planning/today_screen.dart';
import 'features/timers/focus_screen.dart';
import 'features/timers/timer_engine.dart';
import 'features/timers/timer_repository.dart';

class PlanerkaApp extends StatefulWidget {
  const PlanerkaApp({super.key, this.database});

  final AppDatabase? database;

  @override
  State<PlanerkaApp> createState() => _PlanerkaAppState();
}

class _PlanerkaAppState extends State<PlanerkaApp> {
  int _tab = 0;
  int _inboxVersion = 0;

  Future<void> _add(BuildContext dialogContext) async {
    final database = widget.database;
    if (database == null) return;
    var draft = '';
    var showError = false;
    final text = await showDialog<String>(
      context: dialogContext,
      builder: (context) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Новая запись'),
          content: TextField(
            onChanged: (value) => draft = value,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Что сейчас в голове?',
              errorText: showError ? 'Введите задачу' : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (draft.trim().isEmpty) {
                  updateDialog(() => showError = true);
                  return;
                }
                Navigator.pop(context, draft);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (text == null) return;
    await InboxRepository(database).add(text);
    if (mounted) {
      setState(() {
        _tab = 1;
        _inboxVersion++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Планерка',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5263D8)),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Text(switch (_tab) {
            0 => 'Планерка',
            1 => 'Inbox',
            _ => 'Фокус',
          }),
          actions: _tab == 0 && widget.database != null
              ? [
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: 'Календарь',
                      icon: const Icon(Icons.calendar_month_rounded),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CalendarScreen(
                            repository: PlanningRepository(widget.database!),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: 'Проекты',
                      icon: const Icon(Icons.folder_outlined),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ProjectsScreen(
                            repository: PlanningRepository(widget.database!),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: 'Цели',
                      icon: const Icon(Icons.flag_outlined),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => GoalsScreen(
                            repository: PlanningRepository(widget.database!),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]
              : null,
        ),
        body: widget.database == null
            ? const Center(child: Text('Ваш день начинается здесь'))
            : switch (_tab) {
                0 => TodayScreen(
                  repository: PlanningRepository(widget.database!),
                ),
                1 => InboxScreen(
                  key: ValueKey(_inboxVersion),
                  repository: InboxRepository(widget.database!),
                ),
                _ => FocusScreen(
                  engine: TimerEngine(TimerRepository(widget.database!)),
                  planning: PlanningRepository(widget.database!),
                ),
              },
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.today_rounded),
              label: 'Сегодня',
            ),
            NavigationDestination(
              icon: Icon(Icons.inbox_rounded),
              label: 'Inbox',
            ),
            NavigationDestination(
              icon: Icon(Icons.timer_outlined),
              label: 'Фокус',
            ),
          ],
        ),
        floatingActionButton: _tab == 2
            ? null
            : Builder(
                builder: (context) => FloatingActionButton(
                  onPressed: () => _add(context),
                  tooltip: 'Добавить',
                  child: const Icon(Icons.add_rounded),
                ),
              ),
      ),
    );
  }
}
