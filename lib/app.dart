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
import 'features/ai/model/model_screen.dart';
import 'features/ai/model/model_manifest.dart';
import 'features/ai/model/model_store.dart';
import 'features/ai/model/local_ai_engine.dart';
import 'features/ai/model/model_downloader.dart';
import 'features/ai/planning/ai_recommendation_service.dart';

import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
  late final PageController _pageController = PageController();
  ReminderService? _reminders;
  ModelStore? _modelStore;
  ModelDownloader? _sharedModelDownloader;
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final database = widget.database;
    if (database != null) {
      unawaited(_loadThemeMode());
      unawaited(_initializeModelStore());
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
    _pageController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    setState(() => _tab = index);
    if (_pageController.hasClients && _pageController.page?.round() != index) {
      unawaited(
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  Future<void> _quickCapture(String text) async {
    final database = widget.database;
    if (database == null) return;
    await InboxRepository(database).add(text);
    if (mounted) setState(() => _inboxVersion++);
  }

  Future<void> _initializeModelStore() async {
    final root = await getApplicationSupportDirectory();
    if (!mounted) return;
    setState(() {
      _modelDirectoryPath = '${root.path}/models';
      _modelStore = ModelStore(
        LocalModelFileStore(Directory(_modelDirectoryPath!)),
      );
      _sharedModelDownloader = ModelDownloader(
        IoModelTransport(),
        _modelStore!,
      );
    });
    unawaited(_sharedModelDownloader!.initializeBackground());
  }

  AiRecommendationService? _localAiService() {
    final database = widget.database;
    if (database == null) return null;
    final modelStore = _modelStore;
    if (modelStore == null) return null;
    return AiRecommendationService(
      database,
      LocalAiEngine(store: modelStore, manifest: Qwen3ModelManifest.manifest),
    );
  }

  String? _modelDirectoryPath;

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
      setState(() => _inboxVersion++);
      _selectTab(1);
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
                        'model' => ModelScreen(
                          database: widget.database,
                          downloader: _sharedModelDownloader,
                          modelStore: _modelStore,
                          enableBackgroundDownload: true,
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
                    PopupMenuItem(value: 'model', child: Text('Локальный ИИ')),
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
            : PageView(
                key: const Key('main-page-view'),
                controller: _pageController,
                onPageChanged: (index) {
                  if (index != _tab) setState(() => _tab = index);
                },
                physics: const PageScrollPhysics(),
                children: [
                  HomeScreen(
                    key: ValueKey('home-${_tab == 0}'),
                    planning: PlanningRepository(widget.database!),
                    wellbeing: WellbeingRepository(widget.database!),
                    onInbox: () => _selectTab(1),
                    onFocus: () => _selectTab(2),
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
                    onQuickCapture: _quickCapture,
                    modelStore: _modelStore,
                    modelDownloader: _sharedModelDownloader,
                    onModel: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ModelScreen(
                          database: widget.database,
                          downloader: _sharedModelDownloader,
                          modelStore: _modelStore,
                          enableBackgroundDownload: true,
                        ),
                      ),
                    ),
                    isActive: _tab == 0,
                    onChooseGoal: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => GoalsScreen(
                          repository: PlanningRepository(widget.database!),
                        ),
                      ),
                    ),
                  ),
                  InboxScreen(
                    key: ValueKey(_inboxVersion),
                    repository: InboxRepository(widget.database!),
                    ai: _localAiService(),
                  ),
                  FocusScreen(
                    engine: TimerEngine(TimerRepository(widget.database!)),
                    planning: PlanningRepository(widget.database!),
                  ),
                  ProgressScreen(service: ReviewService(widget.database!)),
                ],
              ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _selectTab,
          destinations: [
            NavigationDestination(
              key: const ValueKey('nav-today'),
              icon: Icon(Icons.today_rounded),
              label: 'Сегодня',
            ),
            NavigationDestination(
              key: const ValueKey('nav-inbox'),
              icon: Icon(Icons.inbox_rounded),
              label: 'Inbox',
            ),
            NavigationDestination(
              key: const ValueKey('nav-focus'),
              icon: Icon(Icons.timer_outlined),
              label: 'Фокус',
            ),
            NavigationDestination(
              key: const ValueKey('nav-progress'),
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
