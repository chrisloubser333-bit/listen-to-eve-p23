import '../services/offline_conversational_fallback.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/character_profile.dart';
import '../models/memory_item.dart';
import '../models/message.dart';
import '../models/tool_result.dart';
import '../services/ai_service.dart';
import '../services/intelligence_orchestrator.dart';
import '../services/memory_service.dart';
import '../services/storage_service.dart';
import 'settings_provider.dart';

class ChatProvider extends ChangeNotifier {
  final AiService _aiService;
  final SettingsProvider _settings;
  final StorageService _storage;
  final MemoryService? _memoryService;
  final IntelligenceOrchestrator? _orchestrator;
  final _uuid = const Uuid();

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  String? _error;
  int _memoryTopK = 4;

  ChatProvider(
    this._aiService,
    this._settings,
    this._storage, [
    this._memoryService,
    this._orchestrator,
  ]) {
    _loadHistory();
  }

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  String? get error => _error;
  bool get hasApiKey => _aiService.hasApiKey;
  MemoryService? get memoryService => _memoryService;
  IntelligenceOrchestrator? get orchestrator => _orchestrator;
  CharacterProfile get activeCharacter => _settings.activeCharacter;
  int get memoryTopK => _memoryTopK;

  set memoryTopK(int value) {
    _memoryTopK = value.clamp(1, 10);
    notifyListeners();
  }

  Future<void> _loadHistory() async {
    final saved = await _storage.loadMessages();
    _messages.addAll(saved);
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    _aiService.setApiKey(key);
    await _storage.saveApiKeyForProvider(_settings.aiProvider, key);
    notifyListeners();
  }

  Future<void> sendText(String text) async {
    if (text.trim().isEmpty) return;
    _error = null;

    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: text.trim(),
      timestamp: DateTime.now(),
    );
    _messages.add(userMsg);
    _isLoading = true;
    notifyListeners();

    try {
      const maxHistoryTurns = 30;
      final rawHistory = _messages
          .where((m) => m.role != MessageRole.system)
          .map((m) => {
                'role': m.role == MessageRole.user ? 'user' : 'assistant',
                'content': m.content,
              })
          .toList();

      final history = rawHistory.length > maxHistoryTurns
          ? rawHistory.sublist(rawHistory.length - maxHistoryTurns)
          : rawHistory;

      // 1. Retrieve relevant memories (bounded top-K, character-scoped)
      List<MemoryItem> recalledMemories = [];
      if (_memoryService != null) {
        try {
          recalledMemories = await _memoryService!.retrieveRelevantMemories(
            text,
            limit: _memoryTopK,
            characterId: _settings.characterId,
          );
        } catch (e) {
          debugPrint('Memory retrieval warning: $e');
        }
      }

      // 2. Context injection separating CHARACTER PERSONA, MEMORY CONTEXT, and EXTERNAL KNOWLEDGE
      final personaPrompt =
          _settings.activeCharacter.getSystemPrompt(_settings.language);

      final memoryContext = recalledMemories.isNotEmpty
          ? _formatMemoryContext(recalledMemories, _settings.language)
          : null;

      // 2.5 Provider-independent external knowledge/tool execution if needed
      ToolResult? toolResult;
      if (_orchestrator != null) {
        try {
          toolResult = await _orchestrator!.evaluateAndExecute(
            text,
            conversationHistory: history,
            parameters: {'language': _settings.language},
          );
        } catch (e) {
          debugPrint('Tool orchestration warning: $e');
        }
      }

      final toolContext = toolResult?.formatForPrompt(language: _settings.language);

      final fullSystemPrompt = [personaPrompt, memoryContext, toolContext]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join('\n\n');

      // 3. Generate response with bounded prompt context (with offline conversational fallback)
      String cleanReply;
      try {
        if (_aiService.hasApiKey) {
          final reply = await _aiService.chatCompletion(
            messages: history,
            systemPrompt: fullSystemPrompt,
          );
          cleanReply = reply.trim();
        } else {
          cleanReply = OfflineConversationalFallback.generateReply(
            userMessage: text,
            characterId: _settings.characterId,
            language: _settings.language,
            rememberedContext: memoryContext,
          );
        }
      } catch (providerError) {
        debugPrint('Provider error, using offline conversational fallback: $providerError');
        cleanReply = OfflineConversationalFallback.generateReply(
          userMessage: text,
          characterId: _settings.characterId,
          language: _settings.language,
          rememberedContext: memoryContext,
        );
      }

      if (cleanReply.isEmpty) {
        cleanReply = OfflineConversationalFallback.generateReply(
          userMessage: text,
          characterId: _settings.characterId,
          language: _settings.language,
          rememberedContext: memoryContext,
        );
      }

      final assistantMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: cleanReply,
        timestamp: DateTime.now(),
      );
      _messages.add(assistantMsg);

      // 4. Lightweight deterministic candidate detection (Zero extra AI network calls)
      if (_memoryService != null) {
        try {
          await _memoryService!.processUserMessage(
            text,
            characterId: _settings.characterId,
            language: _settings.language,
          );
        } catch (e) {
          debugPrint('Memory processing warning: $e');
        }
      }

      // Optionally speak the reply
      // await _speak(reply);

      await _storage.saveMessages(_messages);
    } catch (e, stack) {
      print('CHAT ERROR: $e');
      print(stack);
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    _messages.clear();
    await _storage.clearMessages();
    notifyListeners();
  }

  void setListening(bool value) {
    _isListening = value;
    notifyListeners();
  }

  void setSpeaking(bool value) {
    _isSpeaking = value;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Placeholder for full realtime voice loop
  // In a complete implementation this would:
  // 1. Start microphone stream
  // 2. Connect to xAI realtime WebSocket
  // 3. Stream audio chunks
  // 4. Play back response audio
  Future<void> startVoiceConversation() async {
    // TODO: implement full realtime pipeline
    // For now the UI will show that voice is coming
  }

  Future<void> stopVoiceConversation() async {
    _aiService.disconnectRealtime();
    setListening(false);
    setSpeaking(false);
  }

  /// Formats recalled memories into a concise, bounded system instruction.
  String _formatMemoryContext(List<MemoryItem> memories, String language) {
    final isAf = language == 'af';
    final header = isAf
        ? '[ONTHOUDE KONTEKS UIT VORIGE GESPREKKE]\nJy onthou die volgende relevante agtergrond en feite oor die gebruiker:'
        : '[REMEMBERED CONTEXT FROM PREVIOUS CONVERSATIONS]\nYou remember the following relevant background and facts about the user:';

    final items = memories.map((m) => '- ${m.content}').join('\n');

    final instruction = isAf
        ? 'Riglyn: Beskou hierdie as dinge wat jy natuurlik oor die gebruiker onthou uit vorige gesprekke (bv. "Ek onthou jy het genoem...", "Aangesien jy hou van...", of deur dit bloot in ag te neem). Onderskei duidelik tussen wat die gebruiker nou net gesê het en wat jy van tevore onthou. Moet nooit na \'n "geheuedatabasis", "herroepe konteks", "stelselinstruksie" of interne meganismes verwys nie. Moenie hierdie lys ongevra opsê nie.'
        : 'Guideline: Treat these as things you personally remember about the user from earlier interactions (e.g. "I remember you mentioned...", "Since you enjoy...", or by simply taking them into account). Clearly distinguish between what the user just said now versus background you remember from before. Never mention a "memory database", "recalled context", "system prompt", or internal mechanisms. Do not recite this list unprompted.';

    return '$header\n$items\n$instruction';
  }
}
