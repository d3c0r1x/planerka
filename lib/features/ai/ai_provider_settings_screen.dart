import 'package:flutter/material.dart';

import '../../core/app_database.dart';
import 'ai_provider_settings.dart';
import 'secure_ai_store.dart';

class AiProviderSettingsScreen extends StatefulWidget {
  const AiProviderSettingsScreen({
    super.key,
    required this.database,
    this.settingsStore,
  });
  final AppDatabase database;
  final AiProviderSettingsStore? settingsStore;

  @override
  State<AiProviderSettingsScreen> createState() =>
      _AiProviderSettingsScreenState();
}

class _AiProviderSettingsScreenState extends State<AiProviderSettingsScreen> {
  late final _store = widget.settingsStore ??
      AiProviderSettingsStore(widget.database, SecureAiStore());
  late final _provider = TextEditingController();
  late final _endpoint = TextEditingController();
  late final _model = TextEditingController();
  late final _apiKey = TextEditingController();
  late final Future<void> _load;
  AiProviderSettings _settings = AiProviderSettings.defaults();
  bool _hasKey = false;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load = _loadSettings();
  }

  @override
  void dispose() {
    _provider.dispose();
    _endpoint.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _settings = await _store.load();
    _provider.text = _settings.provider;
    _endpoint.text = _settings.endpoint;
    _model.text = _settings.model;
    _hasKey = await _store.hasApiKey();
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
            '• задачи: названия, заметки, метки и сроки;\n'
            '• цели: названия и прогресс;\n'
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
        provider: _provider.text.trim(),
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
                child: Text(
                  'Локальный режим — основной и не требует отправки данных. Облачный режим работает только после ручной настройки и разрешения контекста.',
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
              TextField(
                controller: _provider,
                decoration: const InputDecoration(
                  labelText: 'Название провайдера',
                  hintText: 'OpenAI compatible',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _endpoint,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'HTTPS endpoint',
                  hintText: 'https://provider.example/v1/chat/completions',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _model,
                decoration: const InputDecoration(labelText: 'Название модели'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _apiKey,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Ключ API',
                  hintText: _hasKey ? 'Ключ сохранён защищённо' : 'Не сохранён',
                ),
              ),
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
