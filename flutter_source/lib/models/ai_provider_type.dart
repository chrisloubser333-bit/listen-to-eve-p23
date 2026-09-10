/// Supported AI providers in Listen to Eve.
///
/// Provides vendor abstraction so the application's conversational engine,
/// character personas, memories, and voice remain decoupled from any single AI vendor.
enum AiProviderType {
  xai,
  gemini;

  String get id => name;

  String get displayName {
    switch (this) {
      case AiProviderType.xai:
        return 'xAI Grok';
      case AiProviderType.gemini:
        return 'Google Gemini';
    }
  }

  /// Default model used for standard conversational tasks.
  String get defaultModel {
    switch (this) {
      case AiProviderType.xai:
        return 'grok-4.6';
      case AiProviderType.gemini:
        return 'gemini-3.6-flash';
    }
  }

  static AiProviderType fromString(String? value) {
    if (value == null) return AiProviderType.xai;
    for (final type in AiProviderType.values) {
      if (type.name.toLowerCase() == value.toLowerCase()) {
        return type;
      }
    }
    return AiProviderType.xai;
  }
}
