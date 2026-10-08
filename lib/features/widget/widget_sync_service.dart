import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../planning/planning_repository.dart';
import '../shifts/shift_repository.dart';
import 'widget_snapshot.dart';

abstract interface class WidgetHost {
  Future<void> saveSnapshot(PlannerWidgetSnapshot value);
  Future<void> updateWidget();
}

class HomeWidgetHost implements WidgetHost {
  const HomeWidgetHost();

  static const qualifiedAndroidName =
      'com.planerka.mobile.PlannerWidgetProvider';

  @override
  Future<void> saveSnapshot(PlannerWidgetSnapshot value) async {
    await HomeWidget.saveWidgetData<String>(
      'planner_widget_snapshot',
      jsonEncode(value.toJson()),
    );
  }

  @override
  Future<void> updateWidget() async {
    await HomeWidget.updateWidget(qualifiedAndroidName: qualifiedAndroidName);
  }
}

class WidgetSyncService {
  WidgetSyncService({
    required this.planning,
    required this.shifts,
    WidgetHost? host,
    DateTime Function()? now,
  }) : host = host ?? const HomeWidgetHost(),
       _now = now ?? DateTime.now;

  final PlanningRepository planning;
  final ShiftRepository shifts;
  final WidgetHost host;
  final DateTime Function() _now;
  final Set<String> _completing = {};

  Future<PlannerWidgetSnapshot> refresh() async {
    final snapshot = await PlannerWidgetSnapshot.fromRepositories(
      planning: planning,
      shifts: shifts,
      now: _now(),
    );
    await host.saveSnapshot(snapshot);
    await host.updateWidget();
    return snapshot;
  }

  Future<bool> handleLaunchUri(Uri? uri) async {
    if (uri == null ||
        uri.scheme != 'planerka' ||
        uri.host != 'complete' ||
        uri.queryParametersAll.length != 1) {
      return false;
    }
    final ids = uri.queryParametersAll['taskId'];
    if (ids == null || ids.length != 1 || ids.single.trim().isEmpty) {
      return false;
    }
    final taskId = ids.single;
    if (!_completing.add(taskId)) return false;
    try {
      final rows = await planning.database.database.query(
        'tasks',
        columns: ['id', 'status'],
        where: 'id = ?',
        whereArgs: [taskId],
        limit: 1,
      );
      if (rows.isEmpty ||
          !const {'planned', 'quick'}.contains(rows.single['status'])) {
        return false;
      }
      await planning.complete(taskId);
      await refresh();
      return true;
    } finally {
      _completing.remove(taskId);
    }
  }
}
