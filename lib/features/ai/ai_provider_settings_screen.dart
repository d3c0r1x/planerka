import 'package:flutter/material.dart';

import '../../core/app_database.dart';
import 'ai_provider_router.dart';
import 'ai_provider_settings.dart';
import 'gemini_rest_provider.dart';
import 'secure_ai_store.dart';

class AiProviderSettingsScreen extends StatefulWidget {
  const AiProviderSettingsScreen({
    super.key,
    required this.database,
    this.settingsStore,
    this.modelCatalog,
  });
  final AppDatabase database;
  final AiProviderSettingsStore? settingsStore;
  final GeminiModelCatalog? modelCatalog;

  @override
  State<AiProviderSettingsScreen> createState() =>
      _AiProviderSettingsScreenState();
}

class _AiProviderSettingsScreenState extends State<AiProviderSettingsScreen> {
  late final _store =
      widget.settingsStore ??
      AiProviderSettingsStore(widget.database, SecureAiStore());
  late final GeminiModelCatalog _modelCatalog =
      widget.modelCatalog ?? GeminiRestProvider();
  late final _endpoint = TextEditingController();
  late final _model = TextEditingController();
  late final _apiKey = TextEditingController();
  late final Future<void> _load;
  AiProviderSettings _settings = AiProviderSettings.defaults();
  String _selectedProvider = AiProviderRouter.openAiCompatibleProviderName;
  String? _openAiEndpoint;
  String? _openAiModel;
  List<GeminiModelInfo> _availableModels = [];
  bool _hasKey = false;
  bool _saving = false;
  bool _discoveringModels = false;
  String? _message;
  String? _catalogMessage;

  static const _openAiDefaultEndpoint =
      'https://api.openai.com/v1/chat/completions';
  static const _openAiDefaultModel = 'gpt-4o-mini';

  @override
  void initState() {
    super.initState();
    _load = _loadSettings();
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _settings = await _store.load();
    _selectedProvider =
        _settings.provider == AiProviderRouter.geminiProviderName
        ? AiProviderRouter.geminiProviderName
        : AiProviderRouter.openAiCompatibleProviderName;
    _endpoint.text = _settings.endpoint;
    _model.text = _settings.model;
    if (_selectedProvider == AiProviderRouter.geminiProviderName) {
      if (_endpoint.text.isEmpty) {
        _endpoint.text = GeminiRestProvider.defaultEndpoint;
      }
      if (_model.text.isEmpty) {
        _model.text = GeminiRestProvider.recommendedModelId;
      }
    } else {
      _openAiEndpoint = _settings.endpoint.isEmpty
          ? _openAiDefaultEndpoint
          : _settings.endpoint;
      _openAiModel = _settings.model.isEmpty
          ? _openAiDefaultModel
          : _settings.model;
      _endpoint.text = _openAiEndpoint!;
      _model.text = _openAiModel!;
    }
    _hasKey = await _store.hasApiKey();
  }

  void _selectProvider(String? provider) {
    if (provider == null || provider == _selectedProvider) return;
    setState(() {
      if (_selectedProvider == AiProviderRouter.openAiCompatibleProviderName) {
        _openAiEndpoint = _endpoint.text;
        _openAiModel = _model.text;
      }
      _selectedProvider = provider;
      _availableModels = [];
      _catalogMessage = null;
      if (provider == AiProviderRouter.geminiProviderName) {
        _endpoint.text = GeminiRestProvider.defaultEndpoint;
        _model.text = GeminiRestProvider.recommendedModelId;
      } else {
        _endpoint.text = _openAiEndpoint ?? _openAiDefaultEndpoint;
        _model.text = _openAiModel ?? _openAiDefaultModel;
      }
    });
  }

  Future<void> _discoverModels() async {
    if (_discoveringModels ||
        _selectedProvider != AiProviderRouter.geminiProviderName) {
      return;
    }
    setState(() {
      _discoveringModels = true;
      _catalogMessage = null;
    });
    try {
      final typedKey = _apiKey.text.trim();
      final apiKey = typedKey.isNotEmpty
          ? typedKey
          : await _store.secrets.read(AiProviderSettingsStore.apiKeyName);
      if (apiKey == null || apiKey.trim().isEmpty) {
        if (mounted) {
          setState(() => _catalogMessage = 'Сначала введи ключ API');
        }
        return;
      }

      // Model discovery receives only the key; planner context is never built here.
      final models = await _modelCatalog.listModels(apiKey: apiKey.trim());
      if (!mounted) return;
      setState(() {
        _availableModels = models;
        if (models.any(
          (model) => model.id == GeminiRestProvider.recommendedModelId,
        )) {
          _model.text = GeminiRestProvider.recommendedModelId;
        } else if (models.isNotEmpty &&
            !models.any((model) => model.id == _model.text.trim())) {
          _model.text = models.first.id;
        }
        _catalogMessage = models.isEmpty
            ? 'Модели для генерации не найдены'
            : 'Найдено моделей: ${models.length}. Выбери вариант или введи свой.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _catalogMessage = 'Не удалось загрузить список моделей');
      }
    } finally {
      if (mounted) setState(() => _discoveringModels = false);
    }
  }

  Future<void> _previewAndAllowContext(bool value) async {
    if (!value) {
      setState(() => _settings = _settings.copyWith(allowCloudContext: false));
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Что может увидеть облачный ИИ'),
        content: const SingleChildScrollView(
          child: Text(
            'Если выбрать облачный режим и сохранить это разрешение, провайдер сможет получать сформированный для запроса контекст:\n\n'
            '• задачи: внутренние ID, названия, заметки, статусы, сроки и запланированное время;\n'
            '• цели: внутренние ID, названия и прогресс;\n'
            '• график выбранных смен и занятые временные блоки;\n'
            '• ответы на интервью о пропущенной задаче, если ты запустил этот разбор;\n'
            '• настроение и заметки дневника — только если включён отдельный переключатель ниже.\n\n'
            'Отправка заблокирована, пока ты не выберешь облачный режим, не сохранишь endpoint и ключ и не подтвердишь это разрешение.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Оставить выключенным'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Разрешить контекст'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) {
      setState(() => _settings = _settings.copyWith(allowCloudContext: true));
    }
  }

  Future<void> _removeKey() async {
    await _store.deleteApiKey();
    if (mounted) setState(() => _hasKey = false);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final settings = _settings.copyWith(
        provider: _selectedProvider,
        endpoint: _endpoint.text.trim(),
        model: _model.text.trim(),
      );
      await _store.save(settings, apiKey: _apiKey.text);
      _apiKey.clear();
      final hasKey = await _store.hasApiKey();
      if (mounted) {
        setState(() {
          _settings = settings;
          _hasKey = hasKey;
          _message = 'Настройки сохранены на устройстве';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Не удалось сохранить настройки');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Настройки ИИ')),
    body: FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Не удалось открыть настройки ИИ'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Локальный режим — основной и не требует отправки данных. Облачный режим работает только после ручной настройки и разрешения контекста.',
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Поиск моделей отправляет Google только API-ключ — без задач и данных планировщика.',
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Ключ хранится в Android Secure Storage, не в APK. Google предупреждает, что ключ клиента можно извлечь, и рекомендует прокси-сервер.',
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Google может использовать запросы бесплатного тарифа для улучшения продуктов.',
                    ),
                  ],
                ),
              ),
            ),
            RadioGroup<AiProviderMode>(
              groupValue: _settings.mode,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _settings = _settings.copyWith(mode: value));
                }
              },
              child: Column(
                children: [
                  RadioListTile<AiProviderMode>(
                    value: AiProviderMode.local,
                    title: const Text('Локальная модель'),
                    subtitle: const Text('Обработка на телефоне'),
                  ),
                  RadioListTile<AiProviderMode>(
                    value: AiProviderMode.cloud,
                    title: const Text('Облачный провайдер'),
                    subtitle: const Text('Требует HTTPS, ключ и разрешение'),
                  ),
                ],
              ),
            ),
            if (_settings.mode == AiProviderMode.cloud) ...[
              DropdownButtonFormField<String>(
                key: const Key('ai-provider-selector'),
                initialValue: _selectedProvider,
                decoration: const InputDecoration(labelText: 'Провайдер'),
                items: const [
                  DropdownMenuItem(
                    value: AiProviderRouter.geminiProviderName,
                    child: Text(AiProviderRouter.geminiProviderName),
                  ),
                  DropdownMenuItem(
                    value: AiProviderRouter.openAiCompatibleProviderName,
                    child: Text(AiProviderRouter.openAiCompatibleProviderName),
                  ),
                ],
                onChanged: _selectProvider,
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('ai-endpoint-field'),
                controller: _endpoint,
                readOnly:
                    _selectedProvider == AiProviderRouter.geminiProviderName,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'HTTPS endpoint',
                  hintText: 'https://provider.example/v1/chat/completions',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('ai-model-field'),
                controller: _model,
                decoration: const InputDecoration(labelText: 'Название модели'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('ai-api-key-field'),
                controller: _apiKey,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Ключ API',
                  hintText: _hasKey ? 'Ключ сохранён защищённо' : 'Не сохранён',
                ),
              ),
              if (_selectedProvider == AiProviderRouter.geminiProviderName) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('discover-gemini-models'),
                  onPressed: _discoveringModels ? null : _discoverModels,
                  icon: _discoveringModels
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.manage_search_rounded),
                  label: Text(
                    _discoveringModels ? 'Загружаю модели…' : 'Найти модели',
                  ),
                ),
                if (_catalogMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(_catalogMessage!),
                ],
                if (_availableModels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final model in _availableModels)
                        ActionChip(
                          label: Text(model.id),
                          tooltip: model.displayName,
                          onPressed: () =>
                              setState(() => _model.text = model.id),
                        ),
                    ],
                  ),
                ],
              ],
              if (_hasKey)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _removeKey,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Удалить сохранённый ключ'),
                  ),
                ),
              SwitchListTile(
                key: const Key('cloud-context-consent'),
                value: _settings.allowCloudContext,
                onChanged: _previewAndAllowContext,
                title: const Text('Разрешить контекст после просмотра'),
                subtitle: const Text('Без этого облачные запросы блокируются'),
              ),
            ],
            SwitchListTile(
              key: const Key('ai-diary-consent'),
              value: _settings.includeDiary,
              onChanged: (value) => setState(
                () => _settings = _settings.copyWith(includeDiary: value),
              ),
              title: const Text('Учитывать дневник настроения'),
              subtitle: const Text('По умолчанию выключено'),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              key: const Key('save-ai-provider-settings'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Сохранить настройки'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(_message!, textAlign: TextAlign.center),
            ],
          ],
        );
      },
    ),
  );
}
