import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/memory_item.dart';
import '../models/message.dart';

class StorageService {
  static const _keyApiKey = 'xai_api_key';
  static const _keyProviderPrefix = 'api_key_';
  static const _keyActiveProvider = 'active_ai_provider';
  static const _keyLanguage = 'preferred_language';
  static const _keyVoiceId = 'selected_voice_id';
  static const _keySpeechSpeed = 'speech_speed_multiplier';
  static const _keyCharacterId = 'selected_character_id';
  static const _keyDarkMode = 'dark_mode';
  static const _keyMessages = 'chat_messages';
  static const _keyMemories = 'persisted_memories';
  static const _keySearchProxyEndpoint = 'search_proxy_endpoint';
  static const _keySilencePause = 'silence_pause_seconds';
  static const _keyAutoVoiceReply = 'auto_voice_reply';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Active AI Provider ('xai' or 'gemini')
  Future<void> saveActiveAiProvider(String providerId) async {
    await _prefs.setString(_keyActiveProvider, providerId);
  }

  Future<String> getActiveAiProvider() async {
    return _prefs.getString(_keyActiveProvider) ?? 'xai';
  }

  // Provider-specific API Keys
  Future<void> saveApiKeyForProvider(String providerId, String key) async {
    await _prefs.setString('$_keyProviderPrefix$providerId', key);
    // Maintain backwards compatibility with the legacy xAI key slot
    if (providerId == 'xai') {
      await _prefs.setString(_keyApiKey, key);
    }
  }

  Future<String?> getApiKeyForProvider(String providerId) async {
    final key = _prefs.getString('$_keyProviderPrefix$providerId');
    if (key != null && key.isNotEmpty) return key;
    // Fallback to legacy key for xAI
    if (providerId == 'xai') {
      return _prefs.getString(_keyApiKey);
    }
    return null;
  }

  // Legacy / Convenience API Key
  Future<void> saveApiKey(String key) async {
    await saveApiKeyForProvider('xai', key);
  }

  Future<String?> getApiKey() async {
    return getApiKeyForProvider('xai');
  }

  // Search Proxy Endpoint (Non-sensitive proxy URL, e.g. http://10.0.2.2:3000/api/search or /api/search)
  Future<void> saveSearchProxyEndpoint(String endpoint) async {
    await _prefs.setString(_keySearchProxyEndpoint, endpoint.trim());
  }

  Future<String?> getSearchProxyEndpoint() async {
    final endpoint = _prefs.getString(_keySearchProxyEndpoint);
    return (endpoint != null && endpoint.trim().isNotEmpty) ? endpoint.trim() : null;
  }

  // Language: 'en' or 'af'
  Future<void> saveLanguage(String lang) async {
    await _prefs.setString(_keyLanguage, lang);
  }

  Future<String> getLanguage() async {
    return _prefs.getString(_keyLanguage) ?? 'en';
  }

  // Speech Speed multiplier (0.5x to 1.5x, default 0.85x for calm human pacing)
  Future<void> saveSpeechSpeed(double speed) async {
    await _prefs.setDouble(_keySpeechSpeed, speed);
  }

  Future<double> getSpeechSpeed() async {
    return _prefs.getDouble(_keySpeechSpeed) ?? 0.85;
  }

  // Voice
  Future<void> saveVoiceId(String voiceId) async {
    await _prefs.setString(_keyVoiceId, voiceId);
  }

  Future<String> getVoiceId() async {
    return _prefs.getString(_keyVoiceId) ?? 'eve';
  }

  // Character / Persona
  Future<void> saveCharacterId(String characterId) async {
    await _prefs.setString(_keyCharacterId, characterId);
  }

  Future<String> getCharacterId() async {
    return _prefs.getString(_keyCharacterId) ?? 'eve';
  }

  // Dark mode
  Future<void> saveDarkMode(bool value) async {
    await _prefs.setBool(_keyDarkMode, value);
  }

  Future<bool> getDarkMode() async {
    return _prefs.getBool(_keyDarkMode) ?? true;
  }

  // Chat history (simple local persistence)
  Future<void> saveMessages(List<ChatMessage> messages) async {
    final list = messages.map((m) => m.toJson()).toList();
    await _prefs.setString(_keyMessages, jsonEncode(list));
  }

  Future<List<ChatMessage>> loadMessages() async {
    final raw = _prefs.getString(_keyMessages);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearMessages() async {
    await _prefs.remove(_keyMessages);
  }

  // Memory persistence
  Future<void> saveMemories(List<MemoryItem> memories) async {
    final list = memories.map((m) => m.toJson()).toList();
    await _prefs.setString(_keyMemories, jsonEncode(list));
  }

  Future<List<MemoryItem>> loadMemories() async {
    final raw = _prefs.getString(_keyMemories);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => MemoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // Voice silence pause duration (default 1.8s, range 1.0s - 3.0s)
  Future<void> saveSilencePauseSeconds(double seconds) async {
    await _prefs.setDouble(_keySilencePause, seconds);
  }

  Future<double> getSilencePauseSeconds() async {
    return _prefs.getDouble(_keySilencePause) ?? 1.8;
  }

  // Auto Voice Reply (read character responses aloud automatically)
  Future<void> saveAutoVoiceReply(bool enabled) async {
    await _prefs.setBool(_keyAutoVoiceReply, enabled);
  }

  Future<bool> getAutoVoiceReply() async {
    return _prefs.getBool(_keyAutoVoiceReply) ?? true;
  }

  Future<void> clearMemories() async {
    await _prefs.remove(_keyMemories);
  }
}
