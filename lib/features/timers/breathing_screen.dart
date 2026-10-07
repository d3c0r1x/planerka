import 'dart:async';

import 'package:flutter/material.dart';

import 'timer_engine.dart';

class BreathingScreen extends StatefulWidget {
  const BreathingScreen({super.key});

  @override
  State<BreathingScreen> createState() => _BreathingScreenState();
}

class _BreathingScreenState extends State<BreathingScreen> {
  final Stopwatch _watch = Stopwatch()..start();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = BreathingCycle.phaseAt(_watch.elapsed);
    final (label, seconds, icon) = switch (phase) {
      BreathingPhase.inhale => ('Вдох', 4, Icons.air_rounded),
      BreathingPhase.hold => ('Пауза', 6, Icons.pause_circle_outline_rounded),
      BreathingPhase.exhale => ('Выдох', 8, Icons.spa_rounded),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Дыхание 4–6–8')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 88, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 24),
            Text(label, style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 8),
            Text(
              '$seconds секунд',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            const Text('Повторяйте цикл столько, сколько комфортно.'),
          ],
        ),
      ),
    );
  }
}
