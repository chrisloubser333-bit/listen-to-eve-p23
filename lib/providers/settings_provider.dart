import 'package:flutter/foundation.dart';
import '../models/ai_provider_type.dart';
import '../models/character_profile.dart';
import '../services/intelligence_orchestrator.dart';
import '../services/storage_service.dart';
import '../services/switchable_ai_service.dart';
import '../services/web_search_tool.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;
  final SwitchableAiService? _switchableAiService;
  final IntelligenceOrchestrator? _orchestrator;

  String _language = 'en'; // 'en' or 'af'
  String _characterId = 'eve';
  bool _darkMode = true;
  double _silencePauseSeconds = 1.8;
  bool _autoVoiceReply = true;
  double _speechSpeed = 0.85; // Natural, calm human cadence (0.5x - 1.5x)
  String _aiProvider = 'xai'; // 'xai' or 'gemini'
  String? _searchProxyEndpoint;
  String? _imageProxyEndpoint;
  String? _serverBaseUrl;

  SettingsProvider(
    this._storage, [
    this._switchableAiService,
    this._orchestrator,
  ]) {
    _load();
  }

  String get language => _language;
  String get characterId => _characterId;
  bool get darkMode => _darkMode;
  double get silencePauseSeconds => _silencePauseSeconds;
  bool get autoVoiceReply => _autoVoiceReply;
  double get speechSpeed => _speechSpeed;
  String get aiProvider => _aiProvider;
  String? get searchProxyEndpoint => _searchProxyEndpoint;
  String? get imageProxyEndpoint => _imageProxyEndpoint;
  String? get serverBaseUrl => _serverBaseUrl;
  AiProviderType get activeAiProviderType =>
      AiProviderType.fromString(_aiProvider);

  CharacterProfile get activeCharacter =>
      CharacterRegistry.getById(_characterId);

  Future<void> _load() async {
    _language = await _storage.getLanguage();
    _characterId = await _storage.getCharacterId();
    _darkMode = await _storage.getDarkMode();
    _silencePauseSeconds = await _storage.getSilencePauseSeconds();
    _autoVoiceReply = await _storage.getAutoVoiceReply();
    _speechSpeed = await _storage.getSpeechSpeed();
    _aiProvider = await _storage.getActiveAiProvider();
    _serverBaseUrl = await _storage.getServerBaseUrl();
    _searchProxyEndpoint = await _storage.getSearchProxyEndpoint();
    _imageProxyEndpoint = await _storage.getImageProxyEndpoint();
    _switchableAiService?.setActiveProvider(activeAiProviderType);
    _switchableAiService?.imageProxyTransport?.setServerBaseUrl(_serverBaseUrl);
    _switchableAiService?.imageProxyTransport
        ?.setProxyEndpoint(_imageProxyEndpoint);
    _switchableAiService?.imageProxyTransport
        ?.setFallbackServerUrl(_serverBaseUrl ?? _searchProxyEndpoint);
    _orchestrator
        ?.getTool<WebSearchTool>()
        ?.updateProxyEndpoint(_searchProxyEndpoint ?? _serverBaseUrl);
    notifyListeners();
  }

  Future<void> setServerBaseUrl(String url) async {
    _serverBaseUrl = url.trim().isEmpty ? null : url.trim();
    await _storage.saveServerBaseUrl(url);
    _switchableAiService?.imageProxyTransport?.setServerBaseUrl(_serverBaseUrl);
    _switchableAiService?.imageProxyTransport
        ?.setFallbackServerUrl(_serverBaseUrl ?? _searchProxyEndpoint);
    _orchestrator
        ?.getTool<WebSearchTool>()
        ?.updateProxyEndpoint(_searchProxyEndpoint ?? _serverBaseUrl);
    notifyListeners();
  }

  Future<void> setSearchProxyEndpoint(String endpoint) async {
    _searchProxyEndpoint = endpoint.trim().isEmpty ? null : endpoint.trim();
    await _storage.saveSearchProxyEndpoint(endpoint);
    _orchestrator
        ?.getTool<WebSearchTool>()
        ?.updateProxyEndpoint(_searchProxyEndpoint);
    _switchableAiService?.imageProxyTransport
        ?.setFallbackServerUrl(_searchProxyEndpoint);
    notifyListeners();
  }

  Future<void> setImageProxyEndpoint(String endpoint) async {
    _imageProxyEndpoint = endpoint.trim().isEmpty ? null : endpoint.trim();
    await _storage.saveImageProxyEndpoint(endpoint);
    _switchableAiService?.imageProxyTransport
        ?.setProxyEndpoint(_imageProxyEndpoint);
    notifyListeners();
  }

  Future<void> setAiProvider(String id) async {
    _aiProvider = id;
    await _storage.saveActiveAiProvider(id);
    _switchableAiService?.setActiveProvider(activeAiProviderType);
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    _language = lang;
    await _storage.saveLanguage(lang);
    notifyListeners();
  }

  Future<void> setCharacterId(String id) async {
    _characterId = id;
    await _storage.saveCharacterId(id);
    notifyListeners();
  }

  Future<void> setSilencePauseSeconds(double seconds) async {
    _silencePauseSeconds = seconds.clamp(1.0, 3.0);
    await _storage.saveSilencePauseSeconds(_silencePauseSeconds);
    notifyListeners();
  }

  Future<void> setSpeechSpeed(double speed) async {
    _speechSpeed = speed;
    await _storage.saveSpeechSpeed(speed);
    notifyListeners();
  }

  Future<void> setAutoVoiceReply(bool value) async {
    _autoVoiceReply = value;
    await _storage.saveAutoVoiceReply(value);
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    await _storage.saveDarkMode(value);
    notifyListeners();
  }

  Future<void> setActiveCharacter(CharacterProfile character) async {
    await setCharacterId(character.id);
  }

  String get systemPrompt => activeCharacter.getSystemPrompt(_language);
}
