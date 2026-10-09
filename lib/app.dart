import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';
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
import 'features/ai/ai_provider_router.dart';
import 'features/ai/ai_provider_settings.dart';
import 'features/ai/ai_provider_settings_screen.dart';
import 'features/ai/secure_ai_store.dart';
import 'features/ai/review/missed_task_review_service.dart';
import 'features/ai/review/missed_task_review_screen.dart';

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'features/backup/backup_screen.dart';
import 'features/backup/backup_service.dart';
import 'features/planning/calendar_screen.dart';
import 'features/planning/planning_repository.dart';
import 'features/planning/projects_screen.dart';
import 'features/shifts/shift_repository.dart';
import 'features/reminders/local_notification_port.dart';
import 'features/reminders/reminder_service.dart';
import 'features/reminders/sleep_mode_service.dart';
import 'features/review/progress_screen.dart';
import 'features/review/review_service.dart';
import 'features/timers/focus_screen.dart';
import 'features/timers/timer_engine.dart';
import 'features/timers/timer_repository.dart';
import 'features/wellbeing/habits_screen.dart';
import 'features/wellbeing/journal_screen.dart';
import 'features/wellbeing/wellbeing_repository.dart';
import 'features/widget/widget_sync_service.dart';

class _ActionGlyph extends StatelessWidget {
  const _ActionGlyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: .24), color.withValues(alpha: .07)],
      ),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: color.withValues(alpha: .22)),
    ),
    child: Icon(icon, color: color, size: 21),
  );
}

class _NavGlyph extends StatelessWidget {
  const _NavGlyph({
    required this.icon,
    required this.color,
    required this.selected,
    this.horizontalOffset = 0,
  });

  final IconData icon;
  final Color color;
  final bool selected;
  final double horizontalOffset;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset(horizontalOffset, 0),
    child: AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: 42,
      height: 34,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: selected ? .3 : .06),
            color.withValues(alpha: selected ? .12 : .02),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: selected ? .58 : .12),
          width: selected ? 1 : .7,
        ),
        boxShadow: selected
            ? [BoxShadow(color: color.withValues(alpha: .12), blurRadius: 14)]
            : null,
      ),
      child: Icon(icon, color: color, size: selected ? 23 : 21),
    ),
  );
}

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
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  int _tab = 0;
  int _inboxVersion = 0;
  late final PageController _pageController = PageController();
  ReminderService? _reminders;
  SleepModeService? _sleepMode;
  ModelStore? _modelStore;
  ModelDownloader? _sharedModelDownloader;
  ThemeMode _themeMode = ThemeMode.dark;
  String? _backgroundPath;
  bool _sleepEnabled = false;
  WidgetSyncService? _widgetSync;
  StreamSubscription<Uri?>? _widgetClickSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final database = widget.database;
    if (database != null) {
      unawaited(_loadThemeMode());
      unawaited(_loadBackground());
      unawaited(_initializeModelStore());
      _reminders = ReminderService(
        database,
        widget.notificationPort ?? LocalNotificationPort(),
        shifts: ShiftRepository(database),
        sleepMode: _sleepMode = SleepModeService(database),
      );
      unawaited(_loadSleepMode());
      database.onRemindersChanged = _syncAppServices;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_syncAppServices()),
      );
      unawaited(_initializeWidgetSync());
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

  Future<void> _loadBackground() async {
    final rows = await widget.database!.database.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['custom_background_path'],
      limit: 1,
    );
    if (mounted) {
      setState(
        () => _backgroundPath = rows.isEmpty
            ? null
            : rows.single['value'] as String,
      );
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

  Future<void> _syncAppServices() async {
    await _syncReminders();
    try {
      await _widgetSync?.refresh();
    } catch (_) {
      // Widget updates can fail while a launcher is unavailable.
    }
  }

  Future<void> _initializeWidgetSync() async {
    final database = widget.database;
    if (database == null) return;
    final service = WidgetSyncService(
      planning: PlanningRepository(database),
      shifts: ShiftRepository(database),
    );
    try {
      await HomeWidget.saveWidgetData<String>('planner_widget_snapshot', null);
    } catch (_) {
      // No home_widget channel is available in widget tests or unsupported hosts.
      return;
    }
    _widgetSync = service;
    try {
      await service.refresh();
    } catch (_) {
      // No launcher/widget is a normal installation state.
    }
    try {
      _widgetClickSubscription = HomeWidget.widgetClicked.listen(
        (uri) => unawaited(_handleWidgetLaunch(uri)),
        onError: (_) {},
      );
      final initialUri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      await _handleWidgetLaunch(initialUri);
    } catch (_) {
      // Non-Android builds and older plugin hosts may not provide widget intents.
    }
  }

  Future<void> _handleWidgetLaunch(Uri? uri) async {
    if (uri == null || !mounted) return;
    final completed = await _widgetSync?.handleLaunchUri(uri) ?? false;
    if (!mounted) return;
    _selectTab(0);
    if (completed) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Задача отмечена выполненной')),
      );
    }
  }

  Future<void> _loadSleepMode() async {
    final enabled = await _sleepMode?.isEnabled() ?? false;
    if (mounted) setState(() => _sleepEnabled = enabled);
  }

  Future<void> _toggleSleepMode() async {
    final next = !_sleepEnabled;
    await _sleepMode?.setEnabled(next);
    if (mounted) setState(() => _sleepEnabled = next);
    await _syncReminders();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncReminders());
      unawaited(_refreshWidgetSilently());
    }
  }

  Future<void> _refreshWidgetSilently() async {
    try {
      await _widgetSync?.refresh();
    } catch (_) {
      // Keep lifecycle changes independent of launcher availability.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_widgetClickSubscription?.cancel());
    widget.database?.onRemindersChanged = null;
    _pageController.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    if (index != _tab) unawaited(HapticFeedback.selectionClick());
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
    await _widgetSync?.refresh();
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
    final secrets = SecureAiStore();
    final settings = AiProviderSettingsStore(database, secrets);
    return AiRecommendationService(
      database,
      AiProviderRouter(
        local: LocalAiEngine(
          store: modelStore,
          manifest: Qwen3ModelManifest.manifest,
        ),
        cloud: OpenAiCompatibleGenerator(),
        settings: settings.load,
        secrets: secrets,
      ),
    );
  }

  void _openModelScreen() {
    final database = widget.database;
    if (database == null) return;
    _navigatorKey.currentState?.push<void>(
      MaterialPageRoute(
        builder: (_) => ModelScreen(
          database: database,
          downloader: _sharedModelDownloader,
          modelStore: _modelStore,
          enableBackgroundDownload: true,
        ),
      ),
    );
  }

  void _openAiSettings() {
    final database = widget.database;
    if (database == null) return;
    _navigatorKey.currentState?.push<void>(
      MaterialPageRoute(
        builder: (_) => AiProviderSettingsScreen(database: database),
      ),
    );
  }

  Future<void> _openMissedTaskReview(String taskId) async {
    final database = widget.database;
    if (database == null) return;
    final ai = _localAiService();
    if (ai == null) {
      _openModelScreen();
      return;
    }
    await _navigatorKey.currentState?.push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => MissedTaskReviewScreen(
          service: MissedTaskReviewService(database, ai.generator),
          taskId: taskId,
          onModelRequired: _openModelScreen,
          onAiSettingsRequired: _openAiSettings,
          onConfirmPenalty: (id, cause) async {
            final supplied = widget.gamificationDataSource;
            final accountability = supplied is GamificationService
                ? supplied
                : GamificationService(database);
            final proposal = await accountability.proposePenalty(id, cause);
            await accountability.confirmPenalty(proposal);
          },
        ),
      ),
    );
  }

  String? _modelDirectoryPath;

  Future<void> _showQuickCapture(BuildContext context) async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _QuickCaptureSheet(),
    );
    if (text != null && text.trim().isNotEmpty) await _quickCapture(text);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      title: 'Ритм дня',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark().copyWith(
        scaffoldBackgroundColor: _backgroundPath == null
            ? AppTheme.dark().colorScheme.surface
            : Colors.transparent,
        appBarTheme: AppTheme.dark().appBarTheme.copyWith(
          backgroundColor: _backgroundPath == null
              ? AppTheme.dark().colorScheme.surface
              : Colors.transparent,
        ),
      ),
      themeMode: _themeMode,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarDividerColor: Colors.black,
          systemNavigationBarContrastEnforced: false,
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: _backgroundPath == null
            ? _mainScaffoldBody(context)
            : DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: FileImage(File(_backgroundPath!)),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: .58),
                      BlendMode.darken,
                    ),
                  ),
                ),
                child: _mainScaffoldBody(context),
              ),
      ),
    );
  }

  Widget _mainScaffoldBody(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        switch (_tab) {
          0 => 'Ритм дня',
          1 => 'Inbox',
          2 => 'Фокус',
          _ => 'Прогресс',
        },
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          letterSpacing: -.7,
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Цветовая тема',
          icon: const _ActionGlyph(
            icon: Icons.palette_rounded,
            color: Color(0xFFFFC857),
          ),
          onSelected: (value) {
            final mode = ThemeMode.values.firstWhere(
              (item) => item.name == value,
            );
            unawaited(_setThemeMode(mode));
          },
          itemBuilder: (context) => const [
            PopupMenuItem(enabled: false, child: Text('Цветовая тема')),
            PopupMenuItem(value: 'system', child: Text('Как на устройстве')),
            PopupMenuItem(value: 'light', child: Text('Светлая тема')),
            PopupMenuItem(value: 'dark', child: Text('Тёмная тема')),
          ],
        ),
        if (_tab == 3 && widget.database != null)
          IconButton(
            tooltip: 'Игровой прогресс',
            icon: const _ActionGlyph(
              icon: Icons.emoji_events_rounded,
              color: Color(0xFFFFB84D),
            ),
            onPressed: () => _navigatorKey.currentState?.push(
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
              icon: const _ActionGlyph(
                icon: Icons.calendar_month_rounded,
                color: Color(0xFF66D8CE),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => CalendarScreen(
                    repository: PlanningRepository(widget.database!),
                    shifts: ShiftRepository(widget.database!),
                  ),
                ),
              ),
            ),
          ),
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Проекты',
              icon: const _ActionGlyph(
                icon: Icons.folder_special_rounded,
                color: Color(0xFFFFAE72),
              ),
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
              icon: const _ActionGlyph(
                icon: Icons.flag_rounded,
                color: Color(0xFFFF7FA8),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => GoalsScreen(
                    repository: PlanningRepository(widget.database!),
                    ai: _localAiService(),
                    onModelRequired: _openModelScreen,
                    onAiSettingsRequired: _openAiSettings,
                  ),
                ),
              ),
            ),
          ),
          Builder(
            builder: (context) => PopupMenuButton<String>(
              tooltip: 'Ещё',
              icon: const _ActionGlyph(
                icon: Icons.auto_awesome_rounded,
                color: Color(0xFFA991FF),
              ),
              onSelected: (value) {
                if (value == 'sleep') {
                  unawaited(_toggleSleepMode());
                  return;
                }
                Navigator.push(
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
                );
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  key: const Key('sleep-mode-menu-item'),
                  value: 'sleep',
                  checked: _sleepEnabled,
                  child: const Text('Режим сна'),
                ),
                const PopupMenuItem(value: 'habits', child: Text('Привычки')),
                const PopupMenuItem(value: 'journal', child: Text('Дневник')),
                const PopupMenuItem(
                  value: 'model',
                  child: Text('Локальный ИИ'),
                ),
                const PopupMenuItem(
                  value: 'backup',
                  child: Text('Настройки и резервная копия'),
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
                onHabits: () => _navigatorKey.currentState?.push(
                  MaterialPageRoute<void>(
                    builder: (_) => HabitsScreen(
                      repository: WellbeingRepository(widget.database!),
                    ),
                  ),
                ),
                onJournal: () => _navigatorKey.currentState?.push(
                  MaterialPageRoute<void>(
                    builder: (_) => JournalScreen(
                      repository: WellbeingRepository(widget.database!),
                    ),
                  ),
                ),
                onQuickCapture: _quickCapture,
                modelStore: _modelStore,
                modelDownloader: _sharedModelDownloader,
                onModel: _openModelScreen,
                isActive: _tab == 0,
                onChooseGoal: () => _navigatorKey.currentState?.push(
                  MaterialPageRoute<void>(
                    builder: (_) => GoalsScreen(
                      repository: PlanningRepository(widget.database!),
                      ai: _localAiService(),
                      onModelRequired: _openModelScreen,
                      onAiSettingsRequired: _openAiSettings,
                    ),
                  ),
                ),
                onReviewMissed: _openMissedTaskReview,
              ),
              Builder(
                builder: (inboxContext) => InboxScreen(
                  key: ValueKey(_inboxVersion),
                  repository: InboxRepository(widget.database!),
                  onQuickCapture: () => _showQuickCapture(inboxContext),
                  ai: _localAiService(),
                  onModelRequired: _openModelScreen,
                  onAiSettingsRequired: _openAiSettings,
                ),
              ),
              FocusScreen(
                engine: TimerEngine(TimerRepository(widget.database!)),
                planning: PlanningRepository(widget.database!),
              ),
              ProgressScreen(service: ReviewService(widget.database!)),
            ],
          ),
    bottomNavigationBar: AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.black,
        systemNavigationBarContrastEnforced: false,
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: SizedBox(
          height: 78,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned.fill(
                top: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF101115),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: const Color(0xFF2B2C35)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 26,
                          offset: Offset(0, -8),
                        ),
                      ],
                    ),
                    child: NavigationBar(
                      height: 70,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.alwaysShow,
                      indicatorColor: Colors.transparent,
                      backgroundColor: Colors.transparent,
                      selectedIndex: _tab,
                      onDestinationSelected: _selectTab,
                      destinations: [
                        NavigationDestination(
                          key: const ValueKey('nav-today'),
                          icon: const _NavGlyph(
                            icon: Icons.wb_sunny_rounded,
                            color: Color(0xFFFFC857),
                            selected: false,
                          ),
                          selectedIcon: const _NavGlyph(
                            icon: Icons.wb_sunny_rounded,
                            color: Color(0xFFFFC857),
                            selected: true,
                          ),
                          label: 'Сегодня',
                        ),
                        NavigationDestination(
                          key: const ValueKey('nav-inbox'),
                          icon: const _NavGlyph(
                            icon: Icons.inbox_rounded,
                            horizontalOffset: -18,
                            color: Color(0xFF62C9FF),
                            selected: false,
                          ),
                          selectedIcon: const _NavGlyph(
                            icon: Icons.inbox_rounded,
                            horizontalOffset: -18,
                            color: Color(0xFF62C9FF),
                            selected: true,
                          ),
                          label: 'Inbox',
                        ),
                        NavigationDestination(
                          key: const ValueKey('nav-focus'),
                          icon: const _NavGlyph(
                            icon: Icons.bolt_rounded,
                            horizontalOffset: 18,
                            color: Color(0xFFFF8C69),
                            selected: false,
                          ),
                          selectedIcon: const _NavGlyph(
                            icon: Icons.bolt_rounded,
                            horizontalOffset: 18,
                            color: Color(0xFFFF8C69),
                            selected: true,
                          ),
                          label: 'Фокус',
                        ),
                        NavigationDestination(
                          key: const ValueKey('nav-progress'),
                          icon: const _NavGlyph(
                            icon: Icons.auto_graph_rounded,
                            color: Color(0xFFA991FF),
                            selected: false,
                          ),
                          selectedIcon: const _NavGlyph(
                            icon: Icons.auto_graph_rounded,
                            color: Color(0xFFA991FF),
                            selected: true,
                          ),
                          label: 'Прогресс',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                child: Builder(
                  builder: (context) => Semantics(
                    key: const Key('center-action-button'),
                    label: 'Записать задачу в Inbox',
                    button: true,
                    onTap: () => _showQuickCapture(context),
                    excludeSemantics: true,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFFFE398),
                            Color(0xFFFFBE48),
                            Color(0xFFFF9863),
                          ],
                        ),
                        border: Border.all(color: Colors.black, width: 4),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x35FFC857),
                            blurRadius: 20,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: FloatingActionButton(
                          heroTag: 'center-quick-capture',
                          tooltip: 'Добавить задачу',
                          onPressed: () {
                            unawaited(HapticFeedback.lightImpact());
                            unawaited(_showQuickCapture(context));
                          },
                          backgroundColor: Colors.transparent,
                          foregroundColor: const Color(0xFF241700),
                          elevation: 0,
                          highlightElevation: 0,
                          shape: const CircleBorder(),
                          child: const Icon(Icons.add_rounded, size: 30),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _QuickCaptureSheet extends StatefulWidget {
  const _QuickCaptureSheet();

  @override
  State<_QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends State<_QuickCaptureSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Быстрая запись',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('quick-capture-input'),
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              hintText: 'Запиши мысль или задачу',
              prefixIcon: Icon(Icons.edit_note_rounded),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('quick-capture-save'),
            onPressed: _save,
            icon: const Icon(Icons.inbox_rounded),
            label: const Text('Сохранить в Inbox'),
          ),
        ],
      ),
    ),
  );
}
