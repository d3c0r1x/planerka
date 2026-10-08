import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/core/models.dart';
import 'package:planerka/features/planning/calendar_screen.dart';
import 'package:planerka/features/planning/planning_repository.dart';
import 'package:planerka/features/inbox/inbox_repository.dart';
import 'package:planerka/features/shifts/shift_calendar_section.dart';
import 'package:planerka/features/shifts/shift_models.dart';
import 'package:planerka/features/shifts/shift_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  late ShiftRepository shifts;
  final anchor = DateTime(2026, 10, 8);
  final teams = [
    _team('a', 0),
    _team('b', 2),
    _team('c', 4),
    _team('d', 6, attends: false),
  ];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'planerka_shift_calendar_',
    );
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfiNoIsolate,
    );
    shifts = ShiftRepository(database);
    await shifts.saveSchedule(ShiftSettings(anchorDate: anchor), teams);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('attendance selection is saved for the selected team and day', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShiftCalendarSection(
              repository: shifts,
              selectedDate: anchor,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('attendance-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ходил'));
    await tester.pumpAndSettle();

    expect(await shifts.attendanceFor('a', anchor), ShiftAttendance.attended);
    expect(find.text('Ходил'), findsOneWidget);
  });

  testWidgets('editing one calendar date leaves the next cycle day intact', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShiftCalendarSection(
              repository: shifts,
              selectedDate: anchor,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-shift-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('override-phase-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ночная').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-shift-override')));
    await tester.pumpAndSettle();

    final days = await shifts.calendar(
      anchor,
      anchor.add(const Duration(days: 2)),
    );
    expect(days.firstWhere((day) => day.teamId == 'a').phase, ShiftPhase.night);
    expect(
      days.firstWhere((day) => day.teamId == 'a' && day.date.day == 9).phase,
      ShiftPhase.day,
    );
  });

  testWidgets('future adjustment changes this and later dates only', (
    tester,
  ) async {
    final effective = anchor.add(const Duration(days: 2));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShiftCalendarSection(
              repository: shifts,
              selectedDate: effective,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final teamCard = find.byKey(const Key('shift-day-a'));
    await tester.tap(
      find.descendant(
        of: teamCard,
        matching: find.byTooltip('Сдвиг будущего графика'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сдвинуть цикл…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shift-adjust-forward-a')));
    await tester.pumpAndSettle();

    final days = await shifts.calendar(
      anchor,
      anchor.add(const Duration(days: 4)),
    );
    final teamDays = days.where((day) => day.teamId == 'a');
    expect(
      teamDays.firstWhere((day) => day.date.day == 9).phase,
      ShiftPhase.day,
    );
    expect(
      teamDays.firstWhere((day) => day.date.day == 10).phase,
      ShiftPhase.night,
    );
    expect(
      teamDays.firstWhere((day) => day.date.day == 11).phase,
      ShiftPhase.night,
    );
  });

  testWidgets('night calendar card shows the following day end time', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShiftCalendarSection(
              repository: shifts,
              selectedDate: anchor.add(const Duration(days: 3)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('19:00–09:30 · до 12 окт.'), findsOneWidget);
    expect(find.text('Руководитель A'), findsOneWidget);
  });

  testWidgets('calendar offers shift setup when no schedule exists', (
    tester,
  ) async {
    await database.database.delete('shift_teams');
    await database.database.delete('shift_settings');
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(
          repository: PlanningRepository(database),
          shifts: shifts,
          initialDate: anchor,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Настроить график смен'), findsOneWidget);
    await tester.tap(find.byTooltip('Настроить график смен'));
    await tester.pumpAndSettle();
    expect(find.text('Настройка смен'), findsOneWidget);
  });

  testWidgets('calendar highlights selected day and task deadline', (
    tester,
  ) async {
    final inbox = InboxRepository(database);
    final task = await inbox.add('Подготовить документы');
    await inbox.triage(
      task.id,
      TaskDisposition.planned,
      dueAt: DateTime(anchor.year, anchor.month, anchor.day, 18),
    );
    expect(
      (await PlanningRepository(database).listForDay(anchor))
          .map((entry) => entry.id),
      contains(task.id),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(
          repository: PlanningRepository(database),
          shifts: shifts,
          initialDate: anchor,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-selected-day-card')), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1800));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('calendar-task-${task.id}')), findsOneWidget);
    expect(
      find.byKey(Key('calendar-task-deadline-${task.id}')),
      findsOneWidget,
    );
  });

  testWidgets('compact month marks tasks deadlines and shifts at 360dp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final inbox = InboxRepository(database);
    final task = await inbox.add('Проверить план');
    await inbox.triage(
      task.id,
      TaskDisposition.planned,
      dueAt: DateTime(2026, 10, 8, 18),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(
          repository: PlanningRepository(database),
          shifts: shifts,
          initialDate: anchor,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-month-grid')), findsOneWidget);
    expect(
      find.byKey(const Key('calendar-task-marker-2026-10-8')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('calendar-deadline-marker-2026-10-8')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('calendar-shift-marker-2026-10-8')),
      findsOneWidget,
    );
    expect(find.text('1 задача · 1 дедлайн'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('calendar-day-2026-10-9')));
    await tester.pumpAndSettle();
    expect(find.text('0 задач · 0 дедлайнов'), findsOneWidget);
    await tester.tap(find.byTooltip('Следующий месяц'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-day-2026-11-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('month shift markers refresh after a day override', (
    tester,
  ) async {
    await database.database.delete(
      'shift_teams',
      where: 'id != ?',
      whereArgs: ['a'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(
          repository: PlanningRepository(database),
          shifts: shifts,
          initialDate: anchor,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('calendar-shift-marker-2026-10-8')),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-shift-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('override-cancel-switch')));
    await tester.tap(find.byKey(const Key('save-shift-override')));
    await tester.pumpAndSettle();
    expect(
      (await shifts.calendar(
        anchor,
        anchor.add(const Duration(days: 1)),
      )).single.cancelled,
      isTrue,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('calendar-shift-marker-2026-10-8')),
      findsNothing,
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('calendar-day-2026-10-8')))
          .label,
      isNot(contains('есть смена')),
    );
  });

  testWidgets('month shift markers refresh after future cycle adjustment', (
    tester,
  ) async {
    await database.database.delete(
      'shift_teams',
      where: 'id != ?',
      whereArgs: ['a'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CalendarScreen(
          repository: PlanningRepository(database),
          shifts: shifts,
          initialDate: anchor.add(const Duration(days: 2)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('calendar-shift-marker-2026-10-10')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('calendar-shift-marker-2026-10-12')),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Сдвиг будущего графика'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сдвинуть цикл…'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shift-adjust-forward-a')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('calendar-shift-marker-2026-10-10')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('calendar-shift-marker-2026-10-12')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('calendar-shift-marker-2026-10-9')),
      findsOneWidget,
    );
  });

  for (final failShifts in [true, false]) {
    testWidgets(
      'month marker loading ${failShifts ? 'shift' : 'task'} errors offer retry without false zero semantics',
      (tester) async {
        final unreliableShifts = _RetryableShiftRepository(database)
          ..failMonth = failShifts;
        final unreliableTasks = _RetryablePlanningRepository(database)
          ..failMonth = !failShifts;
        await tester.pumpWidget(
          MaterialApp(
            home: CalendarScreen(
              repository: unreliableTasks,
              shifts: unreliableShifts,
              initialDate: anchor,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('События месяца недоступны'), findsOneWidget);
        final label = tester
            .getSemantics(find.byKey(const Key('calendar-day-2026-10-8')))
            .label;
        expect(label, contains('данные недоступны'));
        expect(label, isNot(contains('0 задач')));
        unreliableShifts.failMonth = false;
        unreliableTasks.failMonth = false;
        await tester.tap(find.byKey(const Key('calendar-month-retry')));
        await tester.pumpAndSettle();
        expect(find.text('События месяца недоступны'), findsNothing);
        expect(
          find.byKey(const Key('calendar-shift-marker-2026-10-8')),
          findsOneWidget,
        );
        expect(
          tester
              .getSemantics(find.byKey(const Key('calendar-day-2026-10-8')))
              .label,
          contains('есть смена'),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _RetryableShiftRepository extends ShiftRepository {
  _RetryableShiftRepository(super.database);
  bool failMonth = true;

  @override
  Future<List<ShiftDayStatus>> calendar(
    DateTime start,
    DateTime endExclusive,
  ) async {
    if (failMonth && endExclusive.difference(start).inDays > 1) {
      throw StateError('Synthetic month shift read failure');
    }
    return super.calendar(start, endExclusive);
  }
}

class _RetryablePlanningRepository extends PlanningRepository {
  _RetryablePlanningRepository(super.database);
  bool failMonth = false;

  @override
  Future<List<TaskEntry>> listForDay(DateTime date) async {
    if (failMonth && date.day == 9) {
      throw StateError('Synthetic month task read failure');
    }
    return super.listForDay(date);
  }
}

ShiftTeam _team(String id, int offset, {bool attends = true}) => ShiftTeam(
  id: id,
  name: 'Смена ${id.toUpperCase()}',
  leaderName: 'Руководитель ${id.toUpperCase()}',
  colorValue: 0xFF66D8CE,
  phaseOffsetDays: offset,
  attends: attends,
);
