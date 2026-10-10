import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/core/widgets/pressable_panel.dart';

void main() {
  Widget buildPanel({required bool disableAnimations}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: PressablePanel(
            onTap: () {},
            decoration: const BoxDecoration(color: Colors.blue),
            child: const SizedBox(width: 180, height: 100),
          ),
        ),
      ),
    ),
  );

  testWidgets('press feedback scales when motion is allowed', (tester) async {
    await tester.pumpWidget(buildPanel(disableAnimations: false));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressablePanel)),
    );
    await tester.pump();

    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      0.975,
    );

    await gesture.up();
    await tester.pump();
  });

  testWidgets(
    'press feedback stays at full size when animations are disabled',
    (tester) async {
      await tester.pumpWidget(buildPanel(disableAnimations: true));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PressablePanel)),
      );
      await tester.pump();

      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
        Duration.zero,
      );

      await gesture.up();
      await tester.pump();
    },
  );
}
