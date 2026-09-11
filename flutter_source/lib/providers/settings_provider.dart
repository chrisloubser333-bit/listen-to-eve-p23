import 'package:flutter/foundation.dart';
import '../models/ai_provider_type.dart';
import '../models/character_profile.dart';
import '../models/voice_option.dart';
import '../services/storage_service.dart';
import '../services/switchable_ai_service.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;
  final SwitchableAiService? _switchableAiService;

  String _language = 'en'; // 'en' or 'af'
  String _voiceId = 'eve';
  String _characterId = 'eve';
  bool _darkMode = true;
  String _aiProvider = 'xai'; // 'xai' or 'gemini'
  List<VoiceOption> _customVoices = [];

  SettingsProvider(this._storage, [this._switchableAiService]) {
    _load();
  }

  String get language => _language;
  String get voiceId => _voiceId;
  String get characterId => _characterId;
  bool get darkMode => _darkMode;
  String get aiProvider => _aiProvider;
  AiProviderType get activeAiProviderType =>
      AiProviderType.fromString(_aiProvider);
  List<VoiceOption> get customVoices => _customVoices;

  CharacterProfile get activeCharacter =>
      CharacterRegistry.getById(_characterId);

  List<VoiceOption> get allVoices => [
        ...VoiceOption.defaults,
        ..._customVoices,
      ];

  VoiceOption get selectedVoice {
    return allVoices.firstWhere(
      (v) => v.id == _voiceId,
      orElse: () => VoiceOption.defaults.first,
    );
  }

  Future<void> _load() async {
    _language = await _storage.getLanguage();
    _voiceId = await _storage.getVoiceId();
    _characterId = await _storage.getCharacterId();
    _darkMode = await _storage.getDarkMode();
    _aiProvider = await _storage.getActiveAiProvider();
    _switchableAiService?.setActiveProvider(activeAiProviderType);
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

  Future<void> setCharacterId(String id, {bool syncVoice = true}) async {
    _characterId = id;
    await _storage.saveCharacterId(id);
    if (syncVoice) {
      final character = CharacterRegistry.getById(id);
      await setVoiceId(character.defaultVoiceId);
    } else {
      notifyListeners();
    }
  }

  Future<void> setVoiceId(String id) async {
    _voiceId = id;
    await _storage.saveVoiceId(id);
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _darkMode = value;
    await _storage.saveDarkMode(value);
    notifyListeners();
  }

  void addCustomVoice(VoiceOption voice) {
    _customVoices = [..._customVoices, voice];
    notifyListeners();
  }

  
  Future<void> setActiveCharacter(CharacterProfile character, {bool syncVoice = true}) async {
    await setCharacterId(character.id, syncVoice: syncVoice);
  }
String get systemPrompt => activeCharacter.getSystemPrompt(_language);
}
