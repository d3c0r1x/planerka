import 'package:sqflite_common/sqlite_api.dart';

import '../../core/app_database.dart';
import 'secure_ai_store.dart';

enum AiProviderMode { local, cloud }

class AiProviderSettings {
  const AiProviderSettings({
    required this.mode,
    required this.provider,
    required this.endpoint,
    required this.model,
    required this.allowCloudContext,
    required this.includeDiary,
  });

  factory AiProviderSettings.defaults() => const AiProviderSettings(
    mode: AiProviderMode.local,
    provider: '',
    endpoint: '',
    model: '',
    allowCloudContext: false,
    includeDiary: false,
  );

  final AiProviderMode mode;
  final String provider;
  final String endpoint;
  final String model;
  final bool allowCloudContext;
  final bool includeDiary;

  AiProviderSettings copyWith({
    AiProviderMode? mode,
    String? provider,
    String? endpoint,
    String? model,
    bool? allowCloudContext,
    bool? includeDiary,
  }) =>
      AiProviderSettings(
        mode: mode ?? this.mode,
        provider: provider ?? this.provider,
        endpoint: endpoint ?? this.endpoint,
        model: model ?? this.model,
        allowCloudContext: allowCloudContext ?? this.allowCloudContext,
        includeDiary: includeDiary ?? this.includeDiary,
      );
}

class AiProviderSettingsStore {
  const AiProviderSettingsStore(this.database, this.secrets);

  static const apiKeyName = 'ai_provider_api_key';
  final AppDatabase database;
  final SecureAiStore secrets;

  Future<AiProviderSettings> load() async {
    final rows = await database.database.query('app_metadata');
    final values = {for (final row in rows) row['key'] as String: row['value'] as String};
    return AiProviderSettings(
      mode: AiProviderMode.values.byName(
        values['ai_provider_mode'] ?? AiProviderMode.local.name,
      ),
      provider: values['ai_provider_name'] ?? '',
      endpoint: values['ai_provider_endpoint'] ?? '',
      model: values['ai_provider_model'] ?? '',
      allowCloudContext: values['ai_cloud_context_allowed'] == 'true',
      includeDiary: values['ai_include_diary'] == 'true',
    );
  }

  Future<void> save(AiProviderSettings settings, {String? apiKey}) async {
    await database.database.transaction((tx) async {
      final values = <String, String>{
        'ai_provider_mode': settings.mode.name,
        'ai_provider_name': settings.provider.trim(),
        'ai_provider_endpoint': settings.endpoint.trim(),
        'ai_provider_model': settings.model.trim(),
        'ai_cloud_context_allowed': settings.allowCloudContext.toString(),
        'ai_include_diary': settings.includeDiary.toString(),
      };
      for (final entry in values.entries) {
        await tx.insert('app_metadata', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      await secrets.write(apiKeyName, apiKey.trim());
    }
  }

  Future<void> deleteApiKey() => secrets.delete(apiKeyName);
  Future<bool> hasApiKey() async =>
      (await secrets.read(apiKeyName))?.isNotEmpty ?? false;
}
