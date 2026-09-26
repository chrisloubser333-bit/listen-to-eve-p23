import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/memory_item.dart';
import '../models/message.dart';
import 'local_image_storage_manager.dart';

/// Production storage service for Listen to Eve.
///
/// Hardened for commercial scaling:
/// - Deprecates persistent plain on-device API keys in favor of short-lived ephemeral session tokens.
/// - Supports gateway authorization tokens with ISO-8601 expiration checks.
/// - Protects SharedPreferences by enforcing local filesystem image caching for large Base64 blobs.
class StorageService {
  static const _keyApiKey = 'xai_api_key';
  static const _keyProviderPrefix = 'api_key_';
  static const _keyActiveProvider = 'active_ai_provider';
  static const _keySessionToken = 'auth_session_token';
  static const _keySessionTokenExpiry = 'auth_session_token_expiry';
  static const _keyAuthGatewayEndpoint = 'auth_gateway_endpoint';
  static const _keyLanguage = 'preferred_language';
  static const _keyVoiceId = 'selected_voice_id';
  static const _keySpeechSpeed = 'speech_speed_multiplier';
  static const _keyCharacterId = 'selected_character_id';
  static const _keyDarkMode = 'dark_mode';
  static const _keyMessages = 'chat_messages';
  static const _keyMessagesByCharacterPrefix = 'chat_messages_character_';
  static const _keyMessagesMigrationDone =
      'chat_messages_character_migration_v1';
  static const _keyMemories = 'persisted_memories';
  static const _keySearchProxyEndpoint = 'search_proxy_endpoint';
  static const _keyImageProxyEndpoint = 'image_proxy_endpoint';
  static const _keyAudioProxyEndpoint = 'audio_proxy_endpoint';
  static const _keyServerBaseUrl = 'server_base_url';
  static const _keySilencePause = 'silence_pause_seconds';
  static const _keyAutoVoiceReply = 'auto_voice_reply';

  /// Production Cloud Run root server URL used when no custom endpoint has been saved.
  static const defaultProductionServerBaseUrl =
      'https://listen-to-eve-416279068095.africa-south1.run.app';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ==========================================
  // Ephemeral Session Token Management (Commercial V8)
  // ==========================================

  /// Persists a short-lived ephemeral session token provided by an external auth gateway.
  Future<void> saveSessionToken(String token, {DateTime? expiresAt}) async {
    await _prefs.setString(_keySessionToken, token.trim());
    if (expiresAt != null) {
      await _prefs.setString(
          _keySessionTokenExpiry, expiresAt.toIso8601String());
    } else {
      await _prefs.remove(_keySessionTokenExpiry);
    }
  }

  /// Retrieves the active ephemeral session token, verifying validity if an expiration is recorded.
  Future<String?> getSessionToken() async {
    final token = _prefs.getString(_keySessionToken);
    if (token == null || token.isEmpty) return null;

    final expiryRaw = _prefs.getString(_keySessionTokenExpiry);
    if (expiryRaw != null && expiryRaw.isNotEmpty) {
      try {
        final expiry = DateTime.parse(expiryRaw);
        if (DateTime.now().isAfter(expiry)) {
          debugPrint('[StorageService] Ephemeral session token has expired.');
          await clearSessionToken();
          return null;
        }
      } catch (_) {}
    }
    return token;
  }

  /// Checks if an unexpired session token currently exists.
  Future<bool> isSessionTokenValid() async {
    final token = await getSessionToken();
    return token != null && token.isNotEmpty;
  }

  /// Clears active session tokens on logout or token revocation.
  Future<void> clearSessionToken() async {
    await _prefs.remove(_keySessionToken);
    await _prefs.remove(_keySessionTokenExpiry);
  }

  /// Auth Gateway Endpoint (e.g. https://run.app/api/auth/token)
  Future<void> saveAuthGatewayEndpoint(String endpoint) async {
    await _prefs.setString(_keyAuthGatewayEndpoint, endpoint.trim());
  }

  Future<String?> getAuthGatewayEndpoint() async {
    final ep = _prefs.getString(_keyAuthGatewayEndpoint);
    return (ep != null && ep.trim().isNotEmpty) ? ep.trim() : null;
  }

  // ==========================================
  // Provider API Keys (Legacy / Direct Client Access)
  // ==========================================

  // Active AI Provider ('xai' or 'gemini')
  Future<void> saveActiveAiProvider(String providerId) async {
    await _prefs.setString(_keyActiveProvider, providerId);
  }

  Future<String> getActiveAiProvider() async {
    return _prefs.getString(_keyActiveProvider) ?? 'xai';
  }

  /// @deprecated Deprecated for commercial multi-user scaling.
  /// Use ephemeral session tokens via [saveSessionToken] or server gateway proxy authorization
  /// instead of storing persistent client-side API credentials.
  @deprecated
  Future<void> saveApiKeyForProvider(String providerId, String key) async {
    await _prefs.setString('$_keyProviderPrefix$providerId', key);
    if (providerId == 'xai') {
      await _prefs.setString(_keyApiKey, key);
    }
  }

  /// @deprecated Deprecated for commercial multi-user scaling.
  /// Retrieve ephemeral session tokens via [getSessionToken] or server gateway proxy authorization.
  @deprecated
  Future<String?> getApiKeyForProvider(String providerId) async {
    // 1. Check for ephemeral session token first
    final sessionToken = await getSessionToken();
    if (sessionToken != null && sessionToken.isNotEmpty) {
      return sessionToken;
    }

    // 2. Fallback to direct client key slot
    final key = _prefs.getString('$_keyProviderPrefix$providerId');
    if (key != null && key.isNotEmpty) return key;

    if (providerId == 'xai') {
      return _prefs.getString(_keyApiKey);
    }
    return null;
  }

  /// @deprecated Deprecated for commercial multi-user scaling. Use [saveSessionToken].
  @deprecated
  Future<void> saveApiKey(String key) async {
    await saveApiKeyForProvider('xai', key);
  }

  /// @deprecated Deprecated for commercial multi-user scaling. Use [getSessionToken].
  @deprecated
  Future<String?> getApiKey() async {
    return getApiKeyForProvider('xai');
  }

  // ==========================================
  // Proxy Endpoints
  // ==========================================

  // Server Base URL (e.g. https://your-server.run.app or http://192.168.1.50:3000)
  Future<void> saveServerBaseUrl(String url) async {
    await _prefs.setString(_keyServerBaseUrl, url.trim());
  }

  Future<String?> getServerBaseUrl() async {
    final url = _prefs.getString(_keyServerBaseUrl);
    if (url != null && url.trim().isNotEmpty) {
      return url.trim();
    }
    return defaultProductionServerBaseUrl;
  }

  // Search Proxy Endpoint
  Future<void> saveSearchProxyEndpoint(String endpoint) async {
    await _prefs.setString(_keySearchProxyEndpoint, endpoint.trim());
  }

  Future<String?> getSearchProxyEndpoint() async {
    final endpoint = _prefs.getString(_keySearchProxyEndpoint);
    return (endpoint != null && endpoint.trim().isNotEmpty)
        ? endpoint.trim()
        : null;
  }

  // Image Proxy Endpoint
  Future<void> saveImageProxyEndpoint(String endpoint) async {
    await _prefs.setString(_keyImageProxyEndpoint, endpoint.trim());
  }

  Future<String?> getImageProxyEndpoint() async {
    final endpoint = _prefs.getString(_keyImageProxyEndpoint);
    return (endpoint != null && endpoint.trim().isNotEmpty)
        ? endpoint.trim()
        : null;
  }

  // Audio Streaming Proxy Endpoint
  Future<void> saveAudioProxyEndpoint(String endpoint) async {
    await _prefs.setString(_keyAudioProxyEndpoint, endpoint.trim());
  }

  Future<String?> getAudioProxyEndpoint() async {
    final endpoint = _prefs.getString(_keyAudioProxyEndpoint);
    return (endpoint != null && endpoint.trim().isNotEmpty)
        ? endpoint.trim()
        : null;
  }

  // ==========================================
  // Personalization & Preferences
  // ==========================================

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

  // ==========================================
  // Chat Messages & Memory Persistence
  // ==========================================

  String _messagesKeyFor(String? characterId) {
    final id = (characterId ?? _prefs.getString(_keyCharacterId) ?? 'eve')
        .trim()
        .toLowerCase();
    return '$_keyMessagesByCharacterPrefix$id';
  }

  Future<void> saveMessages(List<ChatMessage> messages,
      {String? characterId}) async {
    final sanitizedMessages = messages.map((m) {
      if (m.imageUrl != null &&
          (m.imageUrl!.startsWith('data:image') ||
              LocalImageStorageManager.instance.isBase64Payload(m.imageUrl))) {
        final sanitized = m.toJson();
        sanitized['imageUrl'] = null;
        return sanitized;
      }
      return m.toJson();
    }).toList();

    await _prefs.setString(
        _messagesKeyFor(characterId), jsonEncode(sanitizedMessages));
  }

  Future<List<ChatMessage>> loadMessages({String? characterId}) async {
    final scopedKey = _messagesKeyFor(characterId);
    String? raw = _prefs.getString(scopedKey);
    if ((raw == null || raw.isEmpty) &&
        !(_prefs.getBool(_keyMessagesMigrationDone) ?? false)) {
      final legacy = _prefs.getString(_keyMessages);
      if (legacy != null && legacy.isNotEmpty) {
        raw = legacy;
        await _prefs.setString(scopedKey, legacy);
      }
      await _prefs.setBool(_keyMessagesMigrationDone, true);
    }
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final messages = list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();

      _scheduleLazyImageMigration(messages, characterId: characterId);
      return messages;
    } catch (e) {
      debugPrint('[StorageService] Error decoding stored messages: $e');
      return [];
    }
  }

  void _scheduleLazyImageMigration(List<ChatMessage> messages,
      {String? characterId}) {
    if (kIsWeb) return;
    final hasLegacyImages = messages.any((m) =>
        m.imageUrl != null &&
        (m.imageUrl!.startsWith('data:image') ||
            LocalImageStorageManager.instance.isBase64Payload(m.imageUrl)));

    if (!hasLegacyImages) return;

    Future.microtask(() async {
      try {
        bool changed = false;
        final updated = <ChatMessage>[];
        for (final m in messages) {
          if (m.imageUrl != null &&
              (m.imageUrl!.startsWith('data:image') ||
                  LocalImageStorageManager.instance
                      .isBase64Payload(m.imageUrl))) {
            try {
              final localPath =
                  await LocalImageStorageManager.instance.persistImagePayload(
                m.imageUrl!,
                imageId: m.id,
                prefix: 'migrated',
              );
              if (localPath.isNotEmpty && localPath != m.imageUrl) {
                updated.add(m.copyWith(imageUrl: localPath));
                changed = true;
                continue;
              }
            } catch (err) {
              debugPrint(
                  '[StorageService] Lazy migration failed for msg ${m.id}: $err');
            }
          }
          updated.add(m);
        }
        if (changed) {
          await saveMessages(updated, characterId: characterId);
        }
      } catch (e) {
        debugPrint(
            '[StorageService] Exception during lazy image migration: $e');
      }
    });
  }

  Future<void> clearMessages({String? characterId}) async {
    await _prefs.remove(_messagesKeyFor(characterId));
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

  Future<void> saveSilencePauseSeconds(double seconds) async {
    await _prefs.setDouble(_keySilencePause, seconds);
  }

  Future<double> getSilencePauseSeconds() async {
    return _prefs.getDouble(_keySilencePause) ?? 1.8;
  }

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
