#!/usr/bin/env python3
from pathlib import Path
import base64
ROOT=Path(__file__).resolve().parent.parent

def need(t, old, label):
    if old not in t: raise SystemExit(f"ABORT: expected source not found: {label}")

# Android identity
p=ROOT/'android/app/src/main/AndroidManifest.xml'; t=p.read_text(); t=t.replace('android:label="listen_with_eve"','android:label="Listen to Eve"'); p.write_text(t)

# Character-scoped storage
p=ROOT/'lib/services/storage_service.dart'; t=p.read_text()
old="  static const _keyMessages = 'chat_messages';"; need(t,old,'message key')
t=t.replace(old, old+"\n  static const _keyMessagesByCharacterPrefix = 'chat_messages_character_';\n  static const _keyMessagesMigrationDone = 'chat_messages_character_migration_v1';",1)
old="  Future<void> saveMessages(List<ChatMessage> messages) async {\n    final sanitizedMessages = messages.map((m) {"; need(t,old,'saveMessages')
new="  String _messagesKeyFor(String? characterId) {\n    final id = (characterId ?? _prefs.getString(_keyCharacterId) ?? 'eve').trim().toLowerCase();\n    return '$_keyMessagesByCharacterPrefix$id';\n  }\n\n  Future<void> saveMessages(List<ChatMessage> messages, {String? characterId}) async {\n    final sanitizedMessages = messages.map((m) {"
t=t.replace(old,new,1)
t=t.replace('await _prefs.setString(_keyMessages, jsonEncode(sanitizedMessages));','await _prefs.setString(_messagesKeyFor(characterId), jsonEncode(sanitizedMessages));',1)
old="  Future<List<ChatMessage>> loadMessages() async {\n    final raw = _prefs.getString(_keyMessages);\n    if (raw == null || raw.isEmpty) return [];"; need(t,old,'loadMessages')
new="""  Future<List<ChatMessage>> loadMessages({String? characterId}) async {
    final scopedKey = _messagesKeyFor(characterId);
    String? raw = _prefs.getString(scopedKey);
    if ((raw == null || raw.isEmpty) && !(_prefs.getBool(_keyMessagesMigrationDone) ?? false)) {
      final legacy = _prefs.getString(_keyMessages);
      if (legacy != null && legacy.isNotEmpty) {
        raw = legacy;
        await _prefs.setString(scopedKey, legacy);
      }
      await _prefs.setBool(_keyMessagesMigrationDone, true);
    }
    if (raw == null || raw.isEmpty) return [];"""
t=t.replace(old,new,1)
t=t.replace('_scheduleLazyImageMigration(messages);','_scheduleLazyImageMigration(messages, characterId: characterId);',1)
t=t.replace('void _scheduleLazyImageMigration(List<ChatMessage> messages) {','void _scheduleLazyImageMigration(List<ChatMessage> messages, {String? characterId}) {',1)
t=t.replace('await saveMessages(updated);','await saveMessages(updated, characterId: characterId);',1)
old="  Future<void> clearMessages() async {\n    await _prefs.remove(_keyMessages);\n  }"; need(t,old,'clearMessages')
t=t.replace(old,"  Future<void> clearMessages({String? characterId}) async {\n    await _prefs.remove(_messagesKeyFor(characterId));\n  }",1)
p.write_text(t)

# ChatProvider persona history switching
p=ROOT/'lib/providers/chat_provider.dart'; t=p.read_text()
t=t.replace('final saved = await _storage.loadMessages();','final saved = await _storage.loadMessages(characterId: _settings.characterId);',1)
t=t.replace('await _storage.saveMessages(_messages);','await _storage.saveMessages(_messages, characterId: _settings.characterId);')
t=t.replace('await _storage.clearMessages();','await _storage.clearMessages(characterId: _settings.characterId);')
old="""      if (_settings.characterId != lastObservedCharacterId) {
        lastObservedCharacterId = _settings.characterId;
        _voiceService.stopSpeaking();
        _actionLedger?.updateState(activeCharacterId: _settings.characterId);
      }"""; need(t,old,'character listener')
new="""      if (_settings.characterId != lastObservedCharacterId) {
        lastObservedCharacterId = _settings.characterId;
        _voiceService.stopSpeaking();
        _actionLedger?.updateState(activeCharacterId: _settings.characterId);
        _switchCharacterHistory(_settings.characterId);
      }"""
t=t.replace(old,new,1)
marker='  Future<void> setApiKey(String key) async {'; need(t,marker,'setApiKey marker')
method="""  Future<void> _switchCharacterHistory(String characterId) async {
    _messages.clear();
    _isLoading = false;
    _error = null;
    notifyListeners();
    final saved = await _storage.loadMessages(characterId: characterId);
    if (_settings.characterId != characterId) return;
    _messages
      ..clear()
      ..addAll(saved);
    notifyListeners();
  }

"""
t=t.replace(marker,method+marker,1); p.write_text(t)

# Memory screen follows active Material theme
p=ROOT/'lib/screens/memory_screen.dart'; t=p.read_text()
for a,b in {
 'AppTheme.background':'Theme.of(context).scaffoldBackgroundColor',
 'AppTheme.textPrimary':'Theme.of(context).colorScheme.onSurface',
 'AppTheme.textSecondary':'Theme.of(context).colorScheme.onSurfaceVariant',
 'AppTheme.surface':'Theme.of(context).colorScheme.surface',
 'AppTheme.border':'Theme.of(context).dividerColor',
}.items(): t=t.replace(a,b)
t=t.replace('const TextStyle(', 'TextStyle(')
t=t.replace('const Icon(Icons.more_horiz_rounded,\n                color: Theme.of(context).colorScheme.onSurfaceVariant)', 'Icon(Icons.more_horiz_rounded,\n                color: Theme.of(context).colorScheme.onSurfaceVariant)')
p.write_text(t)

print('Acceptance repairs applied successfully. Launcher artwork is installed separately by the build step.')
