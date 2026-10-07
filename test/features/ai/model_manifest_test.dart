import 'package:flutter_test/flutter_test.dart';
import 'package:planerka/features/ai/model/model_manifest.dart';

void main() {
  test('pins approved Qwen model source, size, hash and private filename', () {
    expect(Qwen3ModelManifest.fileName, 'qwen3-0.6b-q4_k_m.gguf');
    expect(Qwen3ModelManifest.url, contains('QuantFactory/Qwen3-0.6B-GGUF'));
    expect(Qwen3ModelManifest.expectedBytes, 484220000);
    expect(
      Qwen3ModelManifest.sha256,
      '7af3fdf842f87b24672f8a7f1dd50404043f0bfb71093ff91c31d2b49df4631d',
    );
  });
}
