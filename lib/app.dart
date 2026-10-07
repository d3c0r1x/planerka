import 'package:flutter/material.dart';

import 'core/app_database.dart';

class PlanerkaApp extends StatelessWidget {
  const PlanerkaApp({super.key, this.database});

  final AppDatabase? database;

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
        appBar: AppBar(title: const Text('Планерка')),
        body: const Center(child: Text('Ваш день начинается здесь')),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          tooltip: 'Добавить',
          child: const Icon(Icons.add_rounded),
        ),
      ),
    );
  }
}
