import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/ai/model/model_downloader.dart';
import 'package:planerka/features/ai/model/model_screen.dart';
import 'package:planerka/features/ai/model/model_store.dart';

void main() {
  testWidgets('shows local model source, size and download action', (
    tester,
  ) async {
    final store = ModelStore(MemoryModelFileStore());
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ModelScreen(
          modelStore: store,
          downloader: ModelDownloader(_EmptyTransport(), store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Qwen3 · 0.6B'), findsOneWidget);
    expect(find.text('484 МБ'), findsOneWidget);
    expect(find.text('Скачать модель'), findsOneWidget);
    expect(find.byKey(const ValueKey('model-not-installed-banner')), findsOneWidget);
  });
}

class _EmptyTransport implements ModelTransport {
  @override
  Future<ModelResponse> get(Uri uri, {int? rangeStart}) async => ModelResponse(
    statusCode: 200,
    contentLength: 0,
    bytes: const Stream.empty(),
  );
}
