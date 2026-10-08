import 'dart:async';

import 'package:flutter/services.dart';

import 'model_manifest.dart';
import 'model_store.dart';

abstract interface class AiTextGenerator {
  Future<String> generate(String prompt, {int maxTokens = 256});
}

class LocalAiEngine implements AiTextGenerator {
  const LocalAiEngine({
    required this.store,
    this.manifest = Qwen3ModelManifest.manifest,
    this.channel = const MethodChannel('planerka/local_ai'),
    this.timeout = const Duration(minutes: 2),
  });

  final ModelStore store;
  final ModelManifest manifest;
  final MethodChannel channel;
  final Duration timeout;

  Future<bool> load() async {
    final modelPath = await store.verifiedModel(manifest);
    if (modelPath == null) {
      throw StateError('Verified local model is not installed');
    }
    return await channel.invokeMethod<bool>('loadModel', {
          'modelPath': modelPath,
        }) ??
        false;
  }

  @override
  Future<String> generate(String prompt, {int maxTokens = 256}) async {
    if (prompt.trim().isEmpty) throw ArgumentError.value(prompt, 'prompt');
    final modelPath = await store.verifiedModel(manifest);
    if (modelPath == null) {
      throw StateError('Verified local model is not installed');
    }
    final modelLoaded = await channel.invokeMethod<bool>('loadModel', {
      'modelPath': modelPath,
    });
    if (modelLoaded != true) {
      throw StateError('The local model could not be loaded');
    }
    String? response;
    try {
      response = await channel
          .invokeMethod<String>('generate', {
            'modelPath': modelPath,
            'prompt': prompt,
            'maxTokens': maxTokens.clamp(1, 512),
          })
          .timeout(timeout);
    } on TimeoutException {
      await cancel();
      rethrow;
    }
    final userFacingResponse = _removeQwenThinking(response ?? '');
    if (userFacingResponse.isEmpty) {
      throw StateError('Local model returned no user-facing answer');
    }
    return userFacingResponse;
  }

  Future<void> cancel() => channel.invokeMethod<void>('cancel');

  Future<void> unload() => channel.invokeMethod<void>('unload');
}

String _removeQwenThinking(String response) {
  const startTag = '<think>';
  const endTag = '</think>';
  final visible = StringBuffer();
  var offset = 0;
  var insideThinking = false;

  while (offset < response.length) {
    if (insideThinking) {
      final end = response.indexOf(endTag, offset);
      if (end < 0) break;
      offset = end + endTag.length;
      insideThinking = false;
      continue;
    }

    final start = response.indexOf(startTag, offset);
    if (start < 0) {
      visible.write(response.substring(offset));
      break;
    }
    visible.write(response.substring(offset, start));
    offset = start + startTag.length;
    insideThinking = true;
  }

  return visible.toString().trim();
}
