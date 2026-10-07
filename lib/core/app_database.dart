import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

class AppDatabase {
  AppDatabase(this.database);

  final Database database;

  static Future<AppDatabase> open(
    String path, {
    DatabaseFactory? factory,
  }) async {
    final source = factory ?? sqflite.databaseFactory;
    final database = await source.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
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
              due_at TEXT,
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
              outcome TEXT
            )
          ''');
        },
      ),
    );
    return AppDatabase(database);
  }

  Future<void> close() => database.close();
}
