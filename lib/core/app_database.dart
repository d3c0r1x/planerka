import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

class AppDatabase {
  AppDatabase(this.database);

  final Database database;
  Future<void> Function()? onRemindersChanged;

  Future<void> remindersChanged() async => await onRemindersChanged?.call();

  static Future<AppDatabase> open(
    String path, {
    DatabaseFactory? factory,
  }) async {
    final source = factory ?? sqflite.databaseFactory;
    final database = await source.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 8,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE projects (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              goal_id TEXT,
              created_at TEXT NOT NULL,
              archived_at TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE tasks (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              notes TEXT NOT NULL DEFAULT '',
              status TEXT NOT NULL DEFAULT 'inbox',
              project_id TEXT REFERENCES projects(id) ON DELETE SET NULL,
              parent_task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,
              due_at TEXT,
              scheduled_at TEXT,
              estimated_minutes INTEGER,
              remind_at TEXT,
              scheduled_date TEXT,
              completed_at TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('CREATE INDEX tasks_status_idx ON tasks(status)');
          await db.execute('CREATE INDEX tasks_due_idx ON tasks(due_at)');
          await db.execute(
            'CREATE INDEX tasks_day_idx ON tasks(scheduled_date)',
          );
          await db.execute('''
            CREATE TABLE goals (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              unit TEXT NOT NULL DEFAULT '',
              target REAL,
              progress REAL NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE habits (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              target_per_week INTEGER NOT NULL DEFAULT 7,
              created_at TEXT NOT NULL,
              archived_at TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE habit_logs (
              id TEXT PRIMARY KEY,
              habit_id TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
              date TEXT NOT NULL,
              value INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              UNIQUE(habit_id, date)
            )
          ''');
          await db.execute('''
            CREATE TABLE journal_entries (
              id TEXT PRIMARY KEY,
              text TEXT NOT NULL,
              mood INTEGER,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE timer_sessions (
              id TEXT PRIMARY KEY,
              kind TEXT NOT NULL,
              task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
              duration_seconds INTEGER NOT NULL,
              started_at TEXT NOT NULL,
              ended_at TEXT,
              status TEXT NOT NULL,
              outcome TEXT,
              deadline_at TEXT,
              remaining_seconds INTEGER,
              elapsed_seconds INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE timer_settings (
              key TEXT PRIMARY KEY,
              value INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE app_metadata (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await _createGamificationTables(db);
          await _createTaskGoalLinks(db);
          await db.execute(
            'CREATE INDEX tasks_parent_idx ON tasks(parent_task_id)',
          );
          await _createShiftTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'ALTER TABLE timer_sessions ADD COLUMN deadline_at TEXT',
            );
            await db.execute(
              'ALTER TABLE timer_sessions ADD COLUMN remaining_seconds INTEGER',
            );
            await db.execute(
              'ALTER TABLE timer_sessions ADD COLUMN elapsed_seconds INTEGER',
            );
            await db.execute(
              'CREATE TABLE timer_settings (key TEXT PRIMARY KEY, value INTEGER NOT NULL)',
            );
          }
          if (oldVersion < 3) {
            await db.execute(
              'CREATE TABLE app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
          }
          if (oldVersion < 4) await _createGamificationTables(db);
          if (oldVersion < 5) {
            final tables = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('tasks', 'goals')",
            );
            if (tables.length == 2) await _createTaskGoalLinks(db);
          }
          if (oldVersion < 6) {
            final tables = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'tasks'",
            );
            if (tables.isNotEmpty) {
              await db.execute(
                'ALTER TABLE tasks ADD COLUMN parent_task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE',
              );
              await db.execute(
                'CREATE INDEX tasks_parent_idx ON tasks(parent_task_id)',
              );
            }
          }
          if (oldVersion < 7) await _createShiftTables(db);
          if (oldVersion < 8) {
            final taskTable = await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'tasks'",
            );
            if (taskTable.isNotEmpty) {
              await db.execute(
                'ALTER TABLE tasks ADD COLUMN scheduled_at TEXT',
              );
              await db.execute(
                'ALTER TABLE tasks ADD COLUMN estimated_minutes INTEGER',
              );
              await db.execute(
                'CREATE INDEX tasks_scheduled_at_idx ON tasks(scheduled_at)',
              );
            }
          }
        },
      ),
    );
    return AppDatabase(database);
  }

  Future<void> close() => database.close();

  static Future<void> _createTaskGoalLinks(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE task_goal_links (
        task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
        goal_id TEXT NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
        source TEXT NOT NULL DEFAULT 'manual' CHECK(source IN ('manual', 'ai')),
        created_at TEXT NOT NULL,
        PRIMARY KEY(task_id, goal_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX task_goal_links_goal_idx ON task_goal_links(goal_id)',
    );
  }

  static Future<void> _createGamificationTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE xp_events (
        event_id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        points INTEGER NOT NULL CHECK(points > 0),
        occurred_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE game_quests (
        id TEXT PRIMARY KEY,
        period TEXT NOT NULL,
        period_start TEXT NOT NULL,
        quest_key TEXT NOT NULL,
        title TEXT NOT NULL,
        target INTEGER NOT NULL,
        progress INTEGER NOT NULL DEFAULT 0,
        reward_xp INTEGER NOT NULL,
        completed_at TEXT,
        UNIQUE(period, period_start, quest_key)
      )
    ''');
    await db.execute('''
      CREATE TABLE game_achievements (
        key TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        unlocked_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE custom_rewards (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        redeemed_at TEXT
      )
    ''');
  }

  static Future<void> _createShiftTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE shift_teams (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        leader_name TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        phase_offset_days INTEGER NOT NULL CHECK(phase_offset_days IN (0, 2, 4, 6)),
        attends INTEGER NOT NULL DEFAULT 1 CHECK(attends IN (0, 1))
      )
    ''');
    await db.execute('''
      CREATE TABLE shift_settings (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        anchor_date TEXT NOT NULL,
        commute_before_minutes INTEGER NOT NULL DEFAULT 60 CHECK(commute_before_minutes >= 0),
        commute_after_minutes INTEGER NOT NULL DEFAULT 90 CHECK(commute_after_minutes >= 0),
        reminder_lead_minutes INTEGER NOT NULL DEFAULT 30 CHECK(reminder_lead_minutes >= 0),
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE shift_overrides (
        team_id TEXT NOT NULL REFERENCES shift_teams(id) ON DELETE CASCADE,
        date TEXT NOT NULL,
        phase TEXT NOT NULL CHECK(phase IN ('day', 'preNightRest', 'night', 'recovery', 'rest')),
        work_start TEXT,
        work_end TEXT,
        cancelled INTEGER NOT NULL DEFAULT 0 CHECK(cancelled IN (0, 1)),
        PRIMARY KEY(team_id, date)
      )
    ''');
    await db.execute('''
      CREATE TABLE shift_adjustments (
        team_id TEXT NOT NULL REFERENCES shift_teams(id) ON DELETE CASCADE,
        effective_date TEXT NOT NULL,
        delta_days INTEGER NOT NULL,
        PRIMARY KEY(team_id, effective_date)
      )
    ''');
    await db.execute('''
      CREATE TABLE shift_attendance (
        team_id TEXT NOT NULL REFERENCES shift_teams(id) ON DELETE CASCADE,
        date TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('attended', 'missed')),
        PRIMARY KEY(team_id, date)
      )
    ''');
    await db.execute(
      'CREATE INDEX shift_overrides_date_idx ON shift_overrides(date)',
    );
    await db.execute(
      'CREATE INDEX shift_adjustments_date_idx ON shift_adjustments(effective_date)',
    );
  }
}
