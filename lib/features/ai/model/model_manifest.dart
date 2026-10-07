class ModelManifest {
  const ModelManifest({
    required this.url,
    required this.fileName,
    required this.expectedBytes,
    required this.sha256,
  });

  final String url;
  final String fileName;
  final int expectedBytes;
  final String sha256;

  Uri get uri => Uri.parse(url);
}

class Qwen3ModelManifest {
  static const fileName = 'qwen3-0.6b-q4_k_m.gguf';
  static const url =
      'https://huggingface.co/QuantFactory/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B.Q4_K_M.gguf';
  static const expectedBytes = 484220000;
  static const sha256 =
      '7af3fdf842f87b24672f8a7f1dd50404043f0bfb71093ff91c31d2b49df4631d';
  static const manifest = ModelManifest(
    url: url,
    fileName: fileName,
    expectedBytes: expectedBytes,
    sha256: sha256,
  );

  static const testFixture = ModelManifest(
    url: 'https://example.invalid/tiny.gguf',
    fileName: 'tiny.gguf',
    expectedBytes: 10,
    sha256: 'c767f1f0735e8eb2aa635ac2b0b3f5f570deb6014a932ac34a8a71f64a9dd70c',
  );
}
