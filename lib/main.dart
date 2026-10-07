import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'core/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final databasePath = p.join(await getDatabasesPath(), 'planerka.db');
  final database = await AppDatabase.open(databasePath);
  runApp(PlanerkaApp(database: database));
}
