/// Abstract interface for AI providers in Listen to Eve.
///
/// Decouples conversation orchestration and memory from any single AI vendor
/// (e.g. xAI Grok, Gemini, OpenAI).
abstract class AiService {
  /// Sets or updates the active API key for this provider.
  void setApiKey(String key);

  /// Whether a valid API key is currently configured for this provider.
  bool get hasApiKey;

  /// Generates a conversational chat completion response.
  ///
  /// [messages] is the list of previous turns formatted as role-content maps.
  /// [systemPrompt] optionally specifies persona instructions or guidelines.
  Future<String> chatCompletion({
    required List<Map<String, String>> messages,
    String? systemPrompt,
  });

  /// Disconnects and cleans up any active realtime voice or streaming sessions.
  void disconnectRealtime();
}
