import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'core/app_database.dart';
import 'core/app_theme.dart';
import 'features/inbox/inbox_repository.dart';
import 'features/inbox/inbox_screen.dart';
import 'features/home/home_screen.dart';
import 'features/goals/goals_screen.dart';
import 'features/gamification/gamification_screen.dart';
import 'features/gamification/gamification_service.dart';
import 'features/backup/backup_screen.dart';
import 'features/backup/backup_service.dart';
import 'features/planning/calendar_screen.dart';
import 'features/planning/planning_repository.dart';
import 'features/planning/projects_screen.dart';
import 'features/reminders/local_notification_port.dart';
import 'features/reminders/reminder_service.dart';
import 'features/review/progress_screen.dart';
import 'features/review/review_service.dart';
import 'features/timers/focus_screen.dart';
import 'features/timers/timer_engine.dart';
import 'features/timers/timer_repository.dart';
import 'features/wellbeing/habits_screen.dart';
import 'features/wellbeing/journal_screen.dart';
import 'features/wellbeing/wellbeing_repository.dart';

class PlanerkaApp extends StatefulWidget {
  const PlanerkaApp({
    super.key,
    this.database,
    this.notificationPort,
    this.gamificationDataSource,
  });

  final AppDatabase? database;
  final NotificationPort? notificationPort;
  final GamificationDataSource? gamificationDataSource;

  @override
  State<PlanerkaApp> createState() => _PlanerkaAppState();
}

class _PlanerkaAppState extends State<PlanerkaApp> with WidgetsBindingObserver {
  int _tab = 0;
  int _inboxVersion = 0;
  ReminderService? _reminders;
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final database = widget.database;
    if (database != null) {
      unawaited(_loadThemeMode());
      _reminders = ReminderService(
        database,
        widget.notificationPort ?? LocalNotificationPort(),
      );
      database.onRemindersChanged = _syncReminders;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_syncReminders()),
      );
    }
  }

  Future<void> _loadThemeMode() async {
    final rows = await widget.database!.database.query(
      'app_metadata',
      where: 'key = ?',
      whereArgs: ['theme_mode'],
    );
    if (!mounted || rows.isEmpty) return;
    final value = rows.single['value'] as String;
    for (final mode in ThemeMode.values) {
      if (mode.name == value) setState(() => _themeMode = mode);
    }
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await widget.database?.database.insert('app_metadata', {
      'key': 'theme_mode',
      'value': mode.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _syncReminders() async {
    try {
      await _reminders?.rescheduleAll();
    } catch (_) {
      // Task and timer operations remain available if Android blocks reminders.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_syncReminders());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.database?.onRemindersChanged = null;
    super.dispose();
  }

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
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _themeMode,
      home: Scaffold(
        appBar: AppBar(
          title: Text(switch (_tab) {
            0 => 'Планерка',
            1 => 'Inbox',
            2 => 'Фокус',
            _ => 'Прогресс',
          }),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Тема',
              icon: const Icon(Icons.palette_outlined),
              onSelected: (value) {
                final mode = ThemeMode.values.firstWhere(
                  (item) => item.name == value,
                );
                unawaited(_setThemeMode(mode));
              },
              itemBuilder: (context) => const [
                PopupMenuItem(enabled: false, child: Text('Цветовая тема')),
                PopupMenuItem(
                  value: 'system',
                  child: Text('Как на устройстве'),
                ),
                PopupMenuItem(value: 'light', child: Text('Светлая тема')),
                PopupMenuItem(value: 'dark', child: Text('Тёмная тема')),
              ],
            ),
            if (_tab == 3 && widget.database != null)
              IconButton(
                tooltip: 'Игровой прогресс',
                icon: const Icon(Icons.emoji_events_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => GamificationScreen(
                      service:
                          widget.gamificationDataSource ??
                          GamificationService(widget.database!),
                    ),
                  ),
                ),
              ),
            if (_tab == 0 && widget.database != null) ...[
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
              Builder(
                builder: (context) => PopupMenuButton<String>(
                  tooltip: 'Ещё',
                  onSelected: (value) => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => switch (value) {
                        'habits' => HabitsScreen(
                          repository: WellbeingRepository(widget.database!),
                        ),
                        'journal' => JournalScreen(
                          repository: WellbeingRepository(widget.database!),
                        ),
                        _ => BackupScreen(
                          service: BackupService(widget.database!),
                        ),
                      },
                    ),
                  ),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'habits', child: Text('Привычки')),
                    PopupMenuItem(value: 'journal', child: Text('Дневник')),
                    PopupMenuItem(
                      value: 'backup',
                      child: Text('Резервная копия'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        body: widget.database == null
            ? const Center(child: Text('Ваш день начинается здесь'))
            : switch (_tab) {
                0 => HomeScreen(
                  planning: PlanningRepository(widget.database!),
                  wellbeing: WellbeingRepository(widget.database!),
                  onInbox: () => setState(() => _tab = 1),
                  onFocus: () => setState(() => _tab = 2),
                  onHabits: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => HabitsScreen(
                        repository: WellbeingRepository(widget.database!),
                      ),
                    ),
                  ),
                  onJournal: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => JournalScreen(
                        repository: WellbeingRepository(widget.database!),
                      ),
                    ),
                  ),
                ),
                1 => InboxScreen(
                  key: ValueKey(_inboxVersion),
                  repository: InboxRepository(widget.database!),
                ),
                2 => FocusScreen(
                  engine: TimerEngine(TimerRepository(widget.database!)),
                  planning: PlanningRepository(widget.database!),
                ),
                _ => ProgressScreen(service: ReviewService(widget.database!)),
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
            NavigationDestination(
              icon: Icon(Icons.insights_rounded),
              label: 'Прогресс',
            ),
          ],
        ),
        floatingActionButton: _tab >= 2
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
