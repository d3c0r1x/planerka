import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'model_downloader.dart';
import 'model_manifest.dart';
import 'model_store.dart';
import 'local_ai_engine.dart';
import 'local_ai_screen.dart';
import '../../../core/app_database.dart';
import '../planning/ai_recommendation_service.dart';

class ModelScreen extends StatefulWidget {
  const ModelScreen({
    super.key,
    this.downloader,
    this.modelStore,
    this.database,
  });
  final ModelDownloader? downloader;
  final ModelStore? modelStore;
  final AppDatabase? database;

  @override
  State<ModelScreen> createState() => _ModelScreenState();
}

class _ModelScreenState extends State<ModelScreen> {
  ModelDownloader? _downloader;
  ModelStore? _store;
  StreamSubscription<ModelDownloadState>? _subscription;
  ModelDownloadState _state = const ModelDownloadState(
    ModelDownloadStatus.checking,
  );
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final store =
        widget.modelStore ??
        ModelStore(
          LocalModelFileStore(
            Directory(
              '${(await getApplicationSupportDirectory()).path}/models',
            ),
          ),
        );
    final downloader =
        widget.downloader ?? ModelDownloader(IoModelTransport(), store);
    final ready = await store.verifiedModel(Qwen3ModelManifest.manifest);
    if (!mounted) return;
    setState(() {
      _store = store;
      _downloader = downloader;
      _loading = false;
      _state = ready == null
          ? const ModelDownloadState(ModelDownloadStatus.paused)
          : const ModelDownloadState(
              ModelDownloadStatus.ready,
              receivedBytes: Qwen3ModelManifest.expectedBytes,
              totalBytes: Qwen3ModelManifest.expectedBytes,
            );
    });
  }

  Future<void> _start() async {
    final downloader = _downloader;
    if (downloader == null) return;
    await _subscription?.cancel();
    _subscription = downloader.download(Qwen3ModelManifest.manifest).listen((
      state,
    ) {
      if (mounted) setState(() => _state = state);
    });
  }

  Future<void> _remove() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить модель?'),
        content: const Text('Модель можно будет скачать снова.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    await _store?.remove(Qwen3ModelManifest.manifest);
    if (mounted) {
      setState(
        () => _state = const ModelDownloadState(ModelDownloadStatus.paused),
      );
    }
  }

  Future<void> _cancel() async {
    await _subscription?.cancel();
    await _store?.remove(Qwen3ModelManifest.manifest);
    if (mounted) {
      setState(
        () => _state = const ModelDownloadState(ModelDownloadStatus.paused),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _downloader?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _state.status == ModelDownloadStatus.ready;
    final downloading = _state.status == ModelDownloadStatus.downloading;
    return Scaffold(
      appBar: AppBar(title: const Text('Локальный ИИ')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.smart_toy_rounded, size: 42),
                        const SizedBox(height: 12),
                        Text(
                          'Qwen3 · 0.6B',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Работает на телефоне. Задачи и дневник остаются на устройстве.',
                        ),
                        if (!ready) ...[
                          const SizedBox(height: 12),
                          Container(
                            key: const ValueKey('model-not-installed-banner'),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(children: [
                              Icon(Icons.cloud_download_rounded),
                              SizedBox(width: 10),
                              Expanded(child: Text('Локальная модель ещё не установлена. Скачайте её, чтобы включить ИИ.')),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 18),
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Размер'),
                          trailing: Text('484 МБ'),
                        ),
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Источник'),
                          subtitle: Text('Hugging Face · QuantFactory'),
                        ),
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Проверка файла'),
                          subtitle: Text(
                            'SHA-256 при загрузке и перед каждым запуском',
                          ),
                        ),
                        if (_state.status == ModelDownloadStatus.downloading ||
                            _state.status == ModelDownloadStatus.paused &&
                                _state.receivedBytes > 0) ...[
                          LinearProgressIndicator(value: _state.progress),
                          const SizedBox(height: 8),
                          Text('Загрузка продолжается, даже если закрыть этот экран.'),
                          const SizedBox(height: 8),
                          Text(
                            '${(_state.receivedBytes / 1000000).toStringAsFixed(0)} / ${(_state.totalBytes / 1000000).toStringAsFixed(0)} МБ',
                          ),
                        ],
                        if (_state.status == ModelDownloadStatus.failed)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _state.message ?? 'Не удалось загрузить модель',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        if (ready)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FilledButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => LocalAiScreen(
                                      engine: LocalAiEngine(
                                        store: _store!,
                                        manifest: Qwen3ModelManifest.manifest,
                                      ),
                                      recommendations: widget.database == null
                                          ? null
                                          : AiRecommendationService(
                                              widget.database!,
                                              LocalAiEngine(
                                                store: _store!,
                                                manifest:
                                                    Qwen3ModelManifest.manifest,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.auto_awesome_rounded),
                                label: const Text('Открыть помощника'),
                              ),
                              TextButton.icon(
                                onPressed: _remove,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Удалить модель'),
                              ),
                            ],
                          )
                        else if (downloading)
                          OutlinedButton.icon(
                            onPressed: () {
                              _downloader?.pause();
                              setState(
                                () => _state = ModelDownloadState(
                                  ModelDownloadStatus.paused,
                                  receivedBytes: _state.receivedBytes,
                                  totalBytes: _state.totalBytes,
                                ),
                              );
                            },
                            icon: const Icon(Icons.pause),
                            label: const Text('Пауза'),
                          )
                        else ...[
                          FilledButton.icon(
                            onPressed: _start,
                            icon: const Icon(Icons.download_rounded),
                            label: Text(
                              _state.receivedBytes > 0
                                  ? 'Продолжить загрузку'
                                  : 'Скачать модель',
                            ),
                          ),
                          if (_state.receivedBytes > 0)
                            TextButton(
                              onPressed: _cancel,
                              child: const Text(
                                'Отменить и удалить частичную загрузку',
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Для первой загрузки нужно подключение к интернету и около 500 МБ свободного места. После проверки модель доступна без сети.',
                ),
              ],
            ),
    );
  }
}
