import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/app.dart';

void main() {
  testWidgets('app opens to a clear empty day', (tester) async {
    await tester.pumpWidget(const PlanerkaApp());

    expect(find.text('Планерка'), findsOneWidget);
    expect(find.text('Ваш день начинается здесь'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  testWidgets('theme selection switches to dark mode', (tester) async {
    await tester.pumpWidget(const PlanerkaApp());
    await tester.pump();

    await tester.tap(find.byTooltip('Тема'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Тёмная тема'), findsOneWidget);
    await tester.tap(find.text('Тёмная тема'));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });
}
