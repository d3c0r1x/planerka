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
}
