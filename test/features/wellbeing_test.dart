import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:planerka/core/app_database.dart';
import 'package:planerka/features/wellbeing/wellbeing_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late AppDatabase database;
  late WellbeingRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('planerka_wellbeing_');
    database = await AppDatabase.open(
      p.join(directory.path, 'app.db'),
      factory: databaseFactoryFfi,
    );
    repository = WellbeingRepository(
      database,
      now: () => DateTime.utc(2026, 10, 8),
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('habit check-in is idempotent, tracks week and streak', () async {
    final habit = await repository.addHabit(
      'Вымышленная привычка',
      targetPerWeek: 3,
    );
    await repository.checkIn(habit.id, DateTime(2026, 10, 6));
    await repository.checkIn(habit.id, DateTime(2026, 10, 7));
    await repository.checkIn(habit.id, DateTime(2026, 10, 8));
    await repository.checkIn(habit.id, DateTime(2026, 10, 8));
    final summary = await repository.summary(habit.id, DateTime(2026, 10, 8));
    expect(summary.weekCount, 3);
    expect(summary.streak, 3);
    expect(summary.todayDone, isTrue);
    await repository.uncheck(habit.id, DateTime(2026, 10, 8));
    final updated = await repository.summary(habit.id, DateTime(2026, 10, 8));
    expect(updated.weekCount, 2);
    expect(updated.todayDone, isFalse);
  });

  test(
    'habit streak stays active through the current day before check-in',
    () async {
      final habit = await repository.addHabit('Вымышленная привычка');
      await repository.checkIn(habit.id, DateTime(2026, 10, 6));
      await repository.checkIn(habit.id, DateTime(2026, 10, 7));

      final summary = await repository.summary(habit.id, DateTime(2026, 10, 8));

      expect(summary.todayDone, isFalse);
      expect(summary.streak, 2);
    },
  );

  test('journal can save, edit, list and delete private entries', () async {
    final entry = await repository.addJournal('Нейтральная запись', mood: 4);
    expect((await repository.listJournal()).single.text, 'Нейтральная запись');
    await repository.updateJournal(entry.id, 'Исправленная запись', mood: 3);
    expect((await repository.listJournal()).single.mood, 3);
    await repository.deleteJournal(entry.id);
    expect(await repository.listJournal(), isEmpty);
  });

  test('rejects invalid weekly target and mood', () async {
    await expectLater(
      repository.addHabit('Тест', targetPerWeek: 0),
      throwsArgumentError,
    );
    await expectLater(
      repository.addJournal('Тест', mood: 6),
      throwsArgumentError,
    );
  });
}
