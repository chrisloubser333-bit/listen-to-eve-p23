import 'ai_service.dart';
import '../models/ai_provider_type.dart';

/// An [AiService] implementation that routes conversational requests to
/// whichever provider is currently selected by the user (e.g. xAI or Gemini).
///
/// Keeps [ChatProvider] completely decoupled from individual vendor SDKs and APIs.
class SwitchableAiService implements AiService {
  final Map<AiProviderType, AiService> _providers;
  AiProviderType _activeType;

  SwitchableAiService({
    required Map<AiProviderType, AiService> providers,
    AiProviderType initialType = AiProviderType.xai,
  })  : _providers = providers,
        _activeType = initialType;

  AiProviderType get activeType => _activeType;

  AiService get activeService =>
      _providers[_activeType] ?? _providers.values.first;

  void setActiveProvider(AiProviderType type) {
    if (_providers.containsKey(type)) {
      _activeType = type;
    }
  }

  AiService? getProvider(AiProviderType type) => _providers[type];

  @override
  void setApiKey(String key) {
    activeService.setApiKey(key);
  }

  void setApiKeyForProvider(AiProviderType type, String key) {
    _providers[type]?.setApiKey(key);
  }

  @override
  bool get hasApiKey => activeService.hasApiKey;

  bool hasApiKeyForProvider(AiProviderType type) =>
      _providers[type]?.hasApiKey ?? false;

  @override
  Future<String> chatCompletion({
    required List<Map<String, String>> messages,
    String? systemPrompt,
  }) {
    return activeService.chatCompletion(
      messages: messages,
      systemPrompt: systemPrompt,
    );
  }

  @override
  void disconnectRealtime() {
    for (final service in _providers.values) {
      try {
        service.disconnectRealtime();
      } catch (_) {}
    }
  }
}
