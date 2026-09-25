import '../services/action_ledger.dart';
import '../services/conversation_context_resolver.dart';
import '../services/response_verification_service.dart';
import '../models/resolved_conversation_context.dart';
import '../models/tool_execution_record.dart';
import '../services/voice_service.dart';
import '../services/offline_conversational_fallback.dart';
import '../services/local_image_storage_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/character_profile.dart';
import '../models/image_reference.dart';
import '../models/memory_item.dart';
import '../models/message.dart';
import '../models/tool_result.dart';
import '../services/ai_service.dart';
import '../services/switchable_ai_service.dart';
import '../services/intelligence_orchestrator.dart';
import '../services/memory_service.dart';
import '../services/storage_service.dart';
import 'settings_provider.dart';

class ChatProvider extends ChangeNotifier {
  final AiService _aiService;
  final SettingsProvider _settings;
  final StorageService _storage;
  final MemoryService? _memoryService;
  final VoiceService _voiceService = VoiceService();
  final IntelligenceOrchestrator? _orchestrator;
  final ActionLedger? _actionLedger;
  final ConversationContextResolver _contextResolver;
  final ResponseVerificationService _verificationService;
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
    this._actionLedger,
    this._contextResolver = const ConversationContextResolver(),
    this._verificationService = const ResponseVerificationService(),
  ]) {
    // Initialize ActionLedger with the active character persona
    _actionLedger?.updateState(activeCharacterId: _settings.characterId);
    _loadHistory();
    _initVoiceService();
  }

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  VoiceService get voiceService => _voiceService;
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  String? get error => _error;
  bool get hasApiKey => _aiService.hasApiKey;
  MemoryService? get memoryService => _memoryService;
  IntelligenceOrchestrator? get orchestrator => _orchestrator;
  ActionLedger? get actionLedger => _actionLedger;
  CharacterProfile get activeCharacter => _settings.activeCharacter;
  int get memoryTopK => _memoryTopK;

  set memoryTopK(int value) {
    _memoryTopK = value.clamp(1, 10);
    notifyListeners();
  }

  Future<void> _loadHistory() async {
    final saved = await _storage.loadMessages();
    for (final m in saved) {
      if (m.content.contains('reached its spending limit') ||
          m.content.contains('bestedingslimiet') ||
          m.content.contains('spending limit') ||
          m.content.contains('Image creation is currently unavailable')) {
        debugPrint(
          '[HISTORICAL_ERROR_ONLY] Loaded historical image-generation error from persistent storage (id: ${m.id}, timestamp: ${m.timestamp}). This is a past error and does NOT reflect current image service availability.',
        );
      }
    }
    _messages.addAll(saved);
    notifyListeners();
  }

  Future<void> setApiKey(String key) async {
    _aiService.setApiKey(key);
    await _storage.saveApiKeyForProvider(_settings.aiProvider, key);
    notifyListeners();
  }


  void _initVoiceService() {
    _voiceService.setServerBaseUrl(_settings.serverBaseUrl ?? _settings.searchProxyEndpoint);

    String lastObservedCharacterId = _settings.characterId;
    _settings.addListener(() {
      // Immediate interruption if character switched anywhere in the app
      if (_settings.characterId != lastObservedCharacterId) {
        lastObservedCharacterId = _settings.characterId;
        _voiceService.stopSpeaking();
        _actionLedger?.updateState(activeCharacterId: _settings.characterId);
      }
      _voiceService.setServerBaseUrl(_settings.serverBaseUrl ?? _settings.searchProxyEndpoint);
    });

    _voiceService.onListeningStateChanged = (listening) {
      _isListening = listening;
      notifyListeners();
    };
    _voiceService.onSpeakingStateChanged = (speaking) {
      _isSpeaking = speaking;
      notifyListeners();
    };
    _voiceService.onSpeechCompleted = (recognizedText) {
      if (recognizedText.trim().isNotEmpty) {
        sendText(recognizedText.trim());
      }
    };
  }

  /// Toggles speech recognition using user configured pause duration
  Future<void> toggleListening({Function(String partial)? onPartialText}) async {
    if (_isListening) {
      await _voiceService.stopListening();
    } else {
      if (_isSpeaking) {
        await _voiceService.stopSpeaking();
      }
      _voiceService.onPartialText = onPartialText;
      await _voiceService.startListening(
        language: _settings.language,
        pauseDurationSeconds: _settings.silencePauseSeconds,
      );
    }
  }

  Future<void> stopSpeaking() async {
    await _voiceService.stopSpeaking();
  }

  Future<void> sendText(String text) async {
    if (text.trim().isEmpty) return;
    _error = null;

    // Barge-in / interruption: stop any in-flight speaking or active request
    if (_isSpeaking) {
      await _voiceService.stopSpeaking();
    }

    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: text.trim(),
      timestamp: DateTime.now(),
    );
    _messages.add(userMsg);
    _actionLedger?.incrementTurn(activeCharacterId: _settings.characterId);
    _isLoading = true;
    notifyListeners();

    try {
      const maxHistoryTurns = 30;
      final historicalErrors = _messages.where((m) =>
          m.role != MessageRole.system &&
          (m.content.contains('reached its spending limit') ||
              m.content.contains('bestedingslimiet') ||
              m.content.contains('spending limit') ||
              m.content.contains('Image creation is currently unavailable'))).toList();
      if (historicalErrors.isNotEmpty) {
        debugPrint(
          '[HISTORICAL_ERROR_ONLY] Filtered ${historicalErrors.length} historical image generation error(s) from LLM context to prevent false hallucinated downtime.',
        );
      }

      final rawHistory = _messages
          .where((m) => m.role != MessageRole.system)
          .where((m) =>
              !m.content.contains('reached its spending limit') &&
              !m.content.contains('bestedingslimiet') &&
              !m.content.contains('spending limit') &&
              !m.content.contains('Image creation is currently unavailable'))
          .map((m) => {
                'role': m.role == MessageRole.user ? 'user' : 'assistant',
                'content': m.content,
              })
          .toList();

      final history = rawHistory.length > maxHistoryTurns
          ? rawHistory.sublist(rawHistory.length - maxHistoryTurns)
          : rawHistory;

      // 0. Image Generation Intent Detection (per AGENTS.md Rule 11 & Character Identity Architecture)
      final imageDetection = detectImageIntent(text);

      if (imageDetection != null && imageDetection.isIntent) {
        final targetCharId = imageDetection.explicitCharacterId ?? _settings.characterId;
        final targetProfile = CharacterRegistry.getById(targetCharId);
        final proxyEndpoint = _aiService is SwitchableAiService
            ? (_aiService as SwitchableAiService).imageProxyTransport?.proxyUri?.toString()
            : null;

        debugPrint('========================================');
        debugPrint('[IMAGE_INTENT_DETECTED]');
        debugPrint('  - Original user prompt: "$text"');
        debugPrint('  - Detected intent: ${imageDetection.isSelfReference ? "Character Portrait/Selfie" : "Generic/Landscape Image"}');
        debugPrint('  - Clean extracted subject: "${imageDetection.rawPrompt}"');
        debugPrint('  - Character target: $targetCharId (${targetProfile.name})');
        debugPrint('  - Specific scene: "${imageDetection.specificScene ?? 'none'}"');
        debugPrint('  - Selected provider: ${_settings.aiProvider}');
        debugPrint('========================================');

        debugPrint('[IMAGE_GENERATION_INVOKED]');
        debugPrint('  - Original user prompt: "$text"');
        debugPrint('  - Detected intent: ${imageDetection.isSelfReference ? "Character Portrait/Selfie" : "Generic/Landscape Image"}');
        debugPrint('  - Selected provider: ${_settings.aiProvider}');
        debugPrint('  - generateImage() called: true');
        debugPrint('  - Proxy endpoint: ${proxyEndpoint ?? "direct vendor API"}');

        String promptToGenerate;
        List<ImageReference>? referenceImages;

        if (imageDetection.isSelfReference) {
          // Multimodal reference image conditioning per character identity architecture
          final assetBytes = await targetProfile.loadCanonicalAssetBytes();
          if (assetBytes != null && assetBytes.isNotEmpty) {
            referenceImages = [
              ImageReference(
                bytes: assetBytes,
                mimeType: 'image/jpeg',
                characterId: targetProfile.id,
                description: '${targetProfile.name} canonical portrait reference',
              ),
            ];
          }

          promptToGenerate = targetProfile.buildImagePrompt(
            sceneOrRequest: imageDetection.specificScene,
            isPhotorealistic: imageDetection.isPhotoOrSelfie,
            isFullBody: imageDetection.isFullBody,
            isArtistic: imageDetection.isArtistic,
            hasReferenceImage: referenceImages != null && referenceImages.isNotEmpty,
          );
        } else {
          // Generic image request (e.g. "a lion", "Cape Town at sunset")
          if (imageDetection.isArtistic) {
            promptToGenerate =
                'A detailed artistic illustration of ${imageDetection.rawPrompt}, fine art, expressive details, no watermarks, no logos.';
          } else if (imageDetection.isPhotoOrSelfie) {
            promptToGenerate =
                'A high-end 8k realistic color photograph of ${imageDetection.rawPrompt}, natural cinematic lighting, authentic textures, photorealistic, no watermarks, no logos.';
          } else {
            promptToGenerate =
                '${imageDetection.rawPrompt}, high detail, vibrant colors, cinematic lighting, 8k quality, no watermarks, no logos';
          }
        }

        final isAf = _settings.language == 'af';
        final displayLabel = imageDetection.isSelfReference
            ? (imageDetection.specificScene != null &&
                    imageDetection.specificScene!.trim().isNotEmpty
                ? '${targetProfile.name} ${imageDetection.specificScene!.trim()}'
                : '${targetProfile.name} Portrait')
            : imageDetection.rawPrompt;

        // Ground image prompts with real-world context if environmental cues are detected
        final lowerText = text.toLowerCase();
        final hasEnvCue = lowerText.contains('weather') ||
            lowerText.contains('today') ||
            lowerText.contains('tonight') ||
            lowerText.contains('now') ||
            lowerText.contains('current') ||
            lowerText.contains('time of day');
        if (hasEnvCue && _orchestrator != null) {
          try {
            final toolResult = await _orchestrator!.evaluateAndExecute(text);
            if (toolResult != null && toolResult.snippet.trim().isNotEmpty) {
              promptToGenerate += ' [Environmental Context: ${toolResult.snippet.trim()}]';
            }
          } catch (_) {}
        }

        debugPrint(
          '[IMAGE_GENERATION_REQUEST] Requesting image generation (Prompt: "$promptToGenerate", Refs: ${referenceImages?.length ?? 0}, Provider: ${_settings.aiProvider})',
        );

        try {
          final rawImagePayload = await _aiService.generateImage(
            promptToGenerate,
            referenceImages: referenceImages,
          );

          if (rawImagePayload.isEmpty ||
              rawImagePayload.toLowerCase().contains('pollinations.ai')) {
            throw const ImageGenerationException(
                'Invalid or watermarked image URL returned.');
          }

          final String imageMsgId = _uuid.v4();
          String finalImageUrl = rawImagePayload;

          // Production Hardening (Phase 1-2): If the payload is a Base64 string or data URI,
          // decode in background isolate and persist to local binary file.
          // This prevents SharedPreferences bloat, JSON stalls, and high startup memory.
          if (rawImagePayload.startsWith('data:image') ||
              LocalImageStorageManager.instance.isBase64Payload(rawImagePayload)) {
            try {
              finalImageUrl = await LocalImageStorageManager.instance.persistImagePayload(
                rawImagePayload,
                imageId: imageMsgId,
                prefix: 'chat',
              );
              debugPrint('[IMAGE_PERSISTED] Successfully saved image to binary file: $finalImageUrl');
            } catch (persistErr) {
              debugPrint('[IMAGE_PERSIST_WARNING] Local persistence failed, using raw payload: $persistErr');
              finalImageUrl = rawImagePayload;
            }
          } else if (rawImagePayload.startsWith('http://') || rawImagePayload.startsWith('https://')) {
            finalImageUrl = rawImagePayload;
          } else if (rawImagePayload.startsWith('/') || rawImagePayload.startsWith('file://')) {
            finalImageUrl = rawImagePayload;
          } else {
            debugPrint('[IMAGE_PAYLOAD_UNEXPECTED] Received unrecognized payload format.');
            throw const ImageGenerationException(
                'Unexpected image payload format returned by image provider.');
          }

          debugPrint('========================================');
          debugPrint('[IMAGE_GENERATION_SUCCESS]');
          debugPrint('  - Original user prompt: "$text"');
          debugPrint('  - Clean extracted subject: "${imageDetection.rawPrompt}"');
          debugPrint('  - Selected provider: ${_settings.aiProvider}');
          debugPrint('  - Success: true');
          debugPrint('  - Stored image reference: $finalImageUrl');
          debugPrint('  - Stored reference type: ${finalImageUrl.startsWith("/") ? "Local File Path" : (finalImageUrl.startsWith("http") ? "Remote URL" : "Data URI")}');
          debugPrint('========================================');

          final confirmationText = isAf
              ? 'Hier is die prent wat ek vir jou geskep het: "$displayLabel"'
              : 'Here is the image I created for you: "$displayLabel"';

          final imageMsg = ChatMessage(
            id: imageMsgId,
            role: MessageRole.assistant,
            content: confirmationText,
            timestamp: DateTime.now(),
            imageUrl: finalImageUrl,
            imagePrompt: displayLabel,
          );
          _messages.add(imageMsg);

          // Record image creation in ActionLedger
          _actionLedger?.recordExecution(
            toolName: 'image_generation',
            inputSummary: displayLabel,
            resultSummary: 'Image generated successfully: $finalImageUrl',
            status: ToolExecutionStatus.success,
            metadata: {
              'prompt': displayLabel,
              'imageUrl': finalImageUrl,
              'characterId': _settings.characterId,
            },
          );

          // Voice announce image creation if autoVoiceReply is active (Rule 12 compliant)
          if (_settings.autoVoiceReply) {
            try {
              _voiceService.speak(
                text: isAf ? 'Hier is jou prent!' : 'Here is your image!',
                characterId: _settings.characterId,
                language: _settings.language,
                speedMultiplier: _settings.speechSpeed,
              );
            } catch (voiceErr) {
              debugPrint('Voice announce error (non-fatal): $voiceErr');
            }
          }

          try {
            await _storage.saveMessages(_messages);
          } catch (storageErr) {
            debugPrint('Storage save error (non-fatal): $storageErr');
          }

          _isLoading = false;
          notifyListeners();
          return;
        } catch (imgErr) {
          debugPrint('========================================');
          debugPrint('[IMAGE_GENERATION_FAILURE]');
          debugPrint('  - Original user prompt: "$text"');
          debugPrint('  - Detected intent: ${imageDetection.isSelfReference ? "Character Portrait/Selfie" : "Generic/Landscape Image"}');
          debugPrint('  - Selected provider: ${_settings.aiProvider}');
          debugPrint('  - Success: false');
          debugPrint('  - Error: $imgErr (Type: ${imgErr.runtimeType})');
          debugPrint('  - Action: displaying concise actionable image-generation error (TERMINATING BRANCH - NO TEXT FALLBACK)');
          debugPrint('========================================');
          String failureText;
          if (imgErr is ImageGenerationException) {
            if (imgErr.isBillingIssue) {
              failureText = isAf
                  ? 'Prentskepping is tans nie beskikbaar nie omdat die beeldgenerering-diens sy bestedingslimiet bereik het. Probeer asseblief later weer of kies \'n ander beeldverskaffer.'
                  : 'Image creation is currently unavailable because the image-generation service has reached its spending limit. Please try again later or choose another image provider.';
            } else if (imgErr.isRateLimitIssue) {
              failureText = isAf
                  ? 'Jy het \'n paar prentversoeke kort na mekaar gemaak. Wag asseblief \'n oomblik voor jy weer probeer.'
                  : 'You\'ve made several image requests in a short time. Please wait a moment before trying again.';
            } else if (imgErr.isQuotaIssue) {
              failureText = isAf
                  ? 'Prentskepping het tans die API-dienskwota bereik. Probeer asseblief oor \'n kort rukkie weer.'
                  : 'Image creation has temporarily reached its API request quota. Please try again in a moment.';
            } else if (imgErr.isApiKeyIssue) {
              failureText = isAf
                  ? 'Prentskepping vereis \'n geldige API-sleutel in die instellings of \'n gekoppelde beeldbediener.'
                  : 'Image creation requires a valid API key configured in Settings or an active backend image proxy.';
            } else if (imgErr.isConnectionTimeout) {
              debugPrint('[IMAGE_GENERATION_TIMEOUT] Connection timed out before reaching image service.');
              failureText = isAf
                  ? 'Kon nie met die beelddiens koppel nie weens \'n netwerk-uitval. Gaan asseblief jou bedienerinstellings na.'
                  : 'Could not connect to the image service. Please check your internet connection or server settings.';
            } else if (imgErr.isGenerationTimeout) {
              debugPrint('[IMAGE_GENERATION_TIMEOUT] Image generation rendering timed out.');
              failureText = isAf
                  ? 'Prentgenerering het langer geneem as verwag om te voltooi. Probeer asseblief weer.'
                  : 'Image creation timed out while waiting for rendering. Please try again.';
            } else if (imgErr.isTimeout) {
              debugPrint('[IMAGE_GENERATION_TIMEOUT] Generic image generation timeout.');
              failureText = isAf
                  ? 'Prentskepping het uitgetel terwyl daar met die diens gekommunikeer is. Probeer asseblief weer.'
                  : 'Image creation timed out while connecting to the image service. Please try again.';
            } else if (imgErr.isNetworkIssue) {
              if (imgErr.message.contains('localhost') || (imgErr.sanitizedDetail != null && imgErr.sanitizedDetail!.contains('localhost'))) {
                failureText = isAf
                    ? 'Kan nie localhost vanaf \'n Android-toestel bereik nie. Voer asseblief jou rekenaar se Wi-Fi IP (bv. http://192.168.x.x:3000) in Instellings in, of voer "adb reverse tcp:3000 tcp:3000" uit.'
                    : 'Cannot reach localhost from an Android physical device. Please enter your computer\'s Wi-Fi IP (e.g. http://192.168.x.x:3000) in Settings, or run "adb reverse tcp:3000 tcp:3000".';
              } else {
                failureText = isAf
                    ? 'Netwerkfout tydens verbinding met die beelddiens. Gaan asseblief jou internetverbinding na.'
                    : 'Network error communicating with the image service. Please check your connection and try again.';
              }
            } else if (imgErr.category == ImageGenerationErrorCategory.validation) {
              if (imgErr.message.contains('Settings') || imgErr.message.contains('Instellings') || imgErr.message.contains('not configured')) {
                failureText = isAf
                    ? 'Die beeldbediener-eindpunt is nog nie vir hierdie toestel opgestel nie. Voer asseblief jou bediener-URL (bv. http://192.168.x.x:3000) in Instellings in.'
                    : 'The image generation server endpoint is not configured for this device. Please enter your server URL (e.g. http://192.168.x.x:3000) in Settings.';
              } else {
                failureText = isAf
                    ? 'Beeldversoek kon nie verwerk word nie: ${imgErr.message}'
                    : 'Image request could not be processed: ${imgErr.message}';
              }
            } else if (imgErr.isServerIssue) {
              failureText = isAf
                  ? 'Die beelddiens het \'n bedienerfout (${imgErr.statusCode ?? 500}) gerapporteer. Probeer asseblief weer oor \'n oomblik.'
                  : 'The image service reported a server error (${imgErr.statusCode ?? 500}). Please try again in a moment.';
            } else if (imgErr.isModelUnsupported) {
              failureText = isAf
                  ? 'Die gekose AI-verskaffer ondersteun nie hierdie beeldgenerering-funksie nie.'
                  : 'The selected AI provider does not support reference-image generation or this image mode.';
            } else {
              failureText = isAf
                  ? 'Ek kon ongelukkig nie die prent voltooi nie weens \'n diensfout: ${imgErr.message}'
                  : 'I was unable to complete that image generation due to an error: ${imgErr.message}';
            }
          } else {
            failureText = isAf
                ? 'Ek kon ongelukkig nie die prent voltooi nie. Probeer asseblief weer oor \'n oomblik.'
                : 'I was unable to create the requested image. Please try again in a moment.';
          }

          final failureMsg = ChatMessage(
            id: _uuid.v4(),
            role: MessageRole.assistant,
            content: failureText,
            timestamp: DateTime.now(),
          );
          _messages.add(failureMsg);

          // Record image failure in ActionLedger
          _actionLedger?.recordExecution(
            toolName: 'image_generation',
            inputSummary: text,
            resultSummary: 'Failed to generate image: $imgErr',
            status: ToolExecutionStatus.failure,
            metadata: {
              'prompt': text,
              'error': imgErr.toString(),
              'characterId': _settings.characterId,
            },
          );

          if (_settings.autoVoiceReply) {
            _voiceService.speak(
              text: isAf
                  ? 'Prentskepping kon nie voltooi word nie.'
                  : 'Image creation could not be completed.',
              characterId: _settings.characterId,
              language: _settings.language,
              speedMultiplier: _settings.speechSpeed,
            );
          }

          await _storage.saveMessages(_messages);
          _isLoading = false;
          notifyListeners();
          return;
        }
      } else {
        debugPrint('========================================');
        debugPrint('[IMAGE_INTENT_NOT_DETECTED]');
        debugPrint('  - Original user prompt: "$text"');
        debugPrint('[NORMAL_TEXT_GENERATION_INVOKED]');
        debugPrint('  - Selected provider: ${_settings.aiProvider}');
        debugPrint('  - Proceeding to memory retrieval & chat completion');
        debugPrint('========================================');
      }

      // 1. Process explicit user facts from the current message into long-term memory FIRST
      if (_memoryService != null) {
        try {
          await _memoryService.processUserMessage(
            text,
            characterId: _settings.characterId,
            language: _settings.language,
          );
        } catch (e) {
          debugPrint('Memory processing warning: $e');
        }
      }

      // 2. Retrieve relevant memories (bounded top-K, character-scoped, including freshly persisted facts)
      List<MemoryItem> recalledMemories = [];
      if (_memoryService != null) {
        try {
          recalledMemories = await _memoryService.retrieveRelevantMemories(
            text,
            limit: _memoryTopK,
            characterId: _settings.characterId,
          );
        } catch (e) {
          debugPrint('Memory retrieval warning: $e');
        }
      }

      // Resolve known user name from recalled or stored memories to guide search resolution
      String? knownUserName;
      if (_memoryService != null) {
        for (final mem in recalledMemories) {
          if (mem.topicKey == 'user_name') {
            final match = RegExp(r'(?:name is|naam is)\s+([^.(]+)', caseSensitive: false)
                .firstMatch(mem.content);
            if (match != null) {
              knownUserName = match.group(1)?.trim();
              break;
            }
          }
        }
        if (knownUserName == null || knownUserName.isEmpty) {
          for (final mem in _memoryService.memories) {
            if (mem.topicKey == 'user_name') {
              final match = RegExp(r'(?:name is|naam is)\s+([^.(]+)', caseSensitive: false)
                  .firstMatch(mem.content);
              if (match != null) {
                knownUserName = match.group(1)?.trim();
                break;
              }
            }
          }
        }
      }

      // 3. Resolve Conversational Context & Follow-Up Inquiries (Companion Core V1 Phase 2)
      final resolvedContext = _contextResolver.resolve(
        text,
        state: _actionLedger?.state,
        ledger: _actionLedger,
        conversationHistory: history,
      );

      _actionLedger?.updateState(
        activeTopic: resolvedContext.activeTopic,
        activeTask: resolvedContext.activeTask,
        lastUserIntent: resolvedContext.resolvedIntent,
        isFollowUp: resolvedContext.isFollowUp,
        activeEntities: resolvedContext.activeEntities,
        activeCharacterId: _settings.characterId,
      );

      // Context injection separating CHARACTER PERSONA, MEMORY CONTEXT, FOLLOW-UP CONTEXT, and EXTERNAL KNOWLEDGE
      final personaPrompt =
          _settings.activeCharacter.getSystemPrompt(_settings.language);

      final memoryContext = recalledMemories.isNotEmpty
          ? _formatMemoryContext(recalledMemories, _settings.language)
          : null;

      final followUpPrompt = resolvedContext.formatForPrompt(language: _settings.language);

      // 3.5 Provider-independent external knowledge/tool execution if needed
      // (Do NOT trigger a redundant new tool search if the user is asking for sources of a previous action)
      ToolResult? toolResult;
      if (!resolvedContext.isAskingForSources && _orchestrator != null) {
        try {
          toolResult = await _orchestrator.evaluateAndExecute(
            text,
            conversationHistory: history,
            parameters: {
              'language': _settings.language,
              'userName': knownUserName,
            },
          );
        } catch (e) {
          debugPrint('Tool orchestration warning: $e');
        }
      }

      final toolContext = toolResult?.formatForPrompt(language: _settings.language);

      final fullSystemPrompt = [personaPrompt, memoryContext, followUpPrompt, toolContext]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join('\n\n');

      // 4. Generate response with bounded prompt context (with offline conversational fallback)
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
            toolResult: toolResult,
            resolvedContext: resolvedContext,
          );
        }
      } catch (providerError) {
        debugPrint('Provider error, using offline conversational fallback: $providerError');
        cleanReply = OfflineConversationalFallback.generateReply(
          userMessage: text,
          characterId: _settings.characterId,
          language: _settings.language,
          rememberedContext: memoryContext,
          toolResult: toolResult,
          resolvedContext: resolvedContext,
        );
      }

      if (cleanReply.isEmpty) {
        cleanReply = OfflineConversationalFallback.generateReply(
          userMessage: text,
          characterId: _settings.characterId,
          language: _settings.language,
          rememberedContext: memoryContext,
          toolResult: toolResult,
          resolvedContext: resolvedContext,
        );
      }

      // 5. Response Verification & Evidence Grounding (Companion Core V1 Phase 3)
      final effectiveToolRecord = toolResult != null
          ? _actionLedger?.lastAction
          : resolvedContext.referencedToolExecution;

      final verificationResult = _verificationService.verifyAndRepair(
        generatedResponse: cleanReply,
        userMessage: text,
        resolvedContext: resolvedContext,
        toolRecord: effectiveToolRecord,
        characterId: _settings.characterId,
        language: _settings.language,
        userName: knownUserName,
      );

      final finalReply = verificationResult.verifiedResponse;

      _actionLedger?.updateState(
        lastAssistantClaim: finalReply.length > 200 ? '${finalReply.substring(0, 197)}...' : finalReply,
      );

      final assistantMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: finalReply,
        timestamp: DateTime.now(),
      );
      _messages.add(assistantMsg);

      // Speak the reply with character-specific humanized voice
      if (_settings.autoVoiceReply && finalReply.trim().isNotEmpty) {
        // Fire and let TTS speak without blocking the UI
        _voiceService.speak(
          text: finalReply,
          characterId: _settings.characterId,
          language: _settings.language,
          speedMultiplier: _settings.speechSpeed,
        );
      }

      await _storage.saveMessages(_messages);
    } catch (e, stack) {
      debugPrint('CHAT ERROR: $e');
      debugPrint('$stack');
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> clearHistory() async {
    _messages.clear();
    _actionLedger?.reset(activeCharacterId: _settings.characterId);
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

  /// Formats recalled memories into a concise, bounded system instruction adhering to Companion Core V1.
  String _formatMemoryContext(List<MemoryItem> memories, String language) {
    final isAf = language == 'af';
    final header = isAf
        ? '[ONTHOUDE KONTEKS UIT VORIGE GESPREKKE]\nJy onthou die volgende relevante agtergrond en feite oor die gebruiker:'
        : '[REMEMBERED CONTEXT FROM PREVIOUS CONVERSATIONS]\nYou remember the following relevant background and facts about the user:';

    final items = memories.map((m) => '- ${m.content}').join('\n');

    final instruction = isAf
        ? 'Riglyn (Companion Core V1): Beskou hierdie as dinge wat jy natuurlik oor die gebruiker onthou uit vorige gesprekke (bv. "Ek onthou jy het genoem...", "Laas het ons gepraat oor..."). As die gebruiker nou inligting gee wat bots met \'n ouer geheue, aanvaar die gebruiker se huidige stelling dadelik sonder om te stry. Moet nooit na \'n "geheuedatabasis", "herroepe konteks", of stelselmeganismes verwys nie. Moenie hierdie lys ongevra opsê nie — gebruik dit slegs wanneer dit natuurlik relevant is.'
        : 'Guideline (Companion Core V1): Treat these as things you personally remember about the user from earlier interactions (e.g. "I remember you mentioned...", "Last time we talked about..."). If the user provides information that conflicts with an older memory, always prefer the user’s current statement without arguing. Never mention a "memory database", "recalled context", or internal mechanisms. Do not recite this list unprompted; let it enrich conversation naturally rather than becoming the conversation.';

    return '$header\n$items\n$instruction';
  }

  /// Robust, conversational image intent detector and character prompt extractor.
  ///
  /// Matches requests such as:
  /// - "create a photo of yourself on a beach"
  /// - "show me what you look like"
  /// - "can you draw yourself?"
  /// - "create a selfie of yourself in Paris"
  /// - "generate a realistic photo of Eve in Cape Town"
  /// - "make a picture of yourself wearing a black dress"
  /// - "skep 'n foto van jouself op die strand"
  /// - "wys my hoe jy lyk"
  /// - "create an image of a lion"
  ///
  /// Correctly rejects non-imperative/past/conversational queries:
  /// - "I saw a picture of Eve yesterday"
  /// - "What does an image mean?"
  /// - "Can you tell me about drawing?"
  /// - "I want to make an image someday"
  static ImageIntentResult? detectImageIntent(String input) {
    var trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // 0. Sanitize input: strip leading/trailing quotes (ASCII and Unicode: ", ', “, ”, ‘, ’, «, », etc.)
    trimmed = trimmed.replaceAll(
      RegExp(r'^[\s\x22\x27\x60\u201C\u201D\u2018\u2019\u00AB\u00BB\u201E\(\)\[\]\?\.\!]+|[\s\x22\x27\x60\u201C\u201D\u2018\u2019\u00AB\u00BB\u201E\(\)\[\]\?\.\!]+$'),
      '',
    ).trim();
    if (trimmed.isEmpty) return null;

    // Clean trailing punctuation
    var cleaned = trimmed.replaceAll(RegExp(r'[\?\.!\s]+$'), '').trim();
    final lower = cleaned.toLowerCase();

    // 1. Negative guards against explicit web searches (Rule 7: e.g. "Search for images of Table Mountain")
    if (lower.startsWith('search for ') ||
        lower.startsWith('search the web for ') ||
        lower.startsWith('search online for ') ||
        lower.startsWith('google ') ||
        lower.startsWith('find photos of ') ||
        lower.startsWith('find pictures of ') ||
        lower.startsWith('soek vir ') ||
        lower.startsWith('soek op die web ') ||
        lower.startsWith('soek op die internet ') ||
        lower.startsWith('soek aanlyn vir ')) {
      return null;
    }

    // 1b. Negative guards against song / music creation
    if (lower.contains('song') ||
        lower.contains('sing a ') ||
        lower.contains("sing 'n ") ||
        lower.contains('sing me ') ||
        lower.contains('liedjie') ||
        lower.contains('musiek')) {
      return null;
    }

    // 1c. Negative guards to prevent false positives on casual/past conversation
    if (lower.startsWith('why ') ||
        lower.startsWith('hoekom ') ||
        lower.startsWith('how does ') ||
        lower.startsWith('hoe werk ') ||
        lower.startsWith('tell me about ') ||
        lower.startsWith('vertel my van ') ||
        lower.startsWith('talk to me about ') ||
        lower.contains(' saw a ') ||
        lower.contains(' gesien ') ||
        lower.contains(' took a ') ||
        lower.contains(' bought a ') ||
        lower.contains(' someday') ||
        lower.contains(' some day') ||
        lower.contains(' in the future') ||
        lower.contains(' eendag') ||
        lower.contains(' mean?') ||
        lower.contains(' meaning of') ||
        lower.contains(' betekenis van')) {
      // Check if it's the specific "what do you look like" exception
      final isLookLikeQuery = lower == 'what do you look like' ||
          lower == 'what do you look like?' ||
          lower == 'what do u look like' ||
          lower == 'hoe lyk jy' ||
          lower == 'hoe lyk jy?';
      if (!isLookLikeQuery) {
        return null;
      }
    }

    // Strip character address prefix if present: "Eve,", "Ara:", "Leo, please", "Rex ", "Sal, "
    // Normalize a leading conversational greeting before direct-character matching.
    final greetingOnlyPrefix = RegExp(
      r'^(?:hello|hi|hey|hiya|good\s+morning|good\s+afternoon|good\s+evening|hallo|haai)\s+'
      r'(eve|ara|leo|rex|sal)[\,\:\s]+\s*',
      caseSensitive: false,
    );
    final greetingOnlyMatch = greetingOnlyPrefix.firstMatch(cleaned);
    if (greetingOnlyMatch != null) {
      cleaned = '${greetingOnlyMatch.group(1)} ${cleaned.substring(greetingOnlyMatch.end).trim()}';
    }

    String queryWithoutCharPrefix = cleaned;
    String? explicitCharacterFromPrefix;
    final charPrefixPattern = RegExp(
      r'^(?:eve|ara|leo|rex|sal|adam|nova|luna|orion|companion|bot|ai)[\,\:\s]+\s*',
      caseSensitive: false,
    );
    final matchChar = charPrefixPattern.firstMatch(cleaned);
    if (matchChar != null) {
      final rawName = matchChar.group(0)!.replaceAll(RegExp(r'[\,\:\s]+'), '').toLowerCase();
      if (const ['eve', 'ara', 'leo', 'rex', 'sal'].contains(rawName)) {
        explicitCharacterFromPrefix = rawName;
      }
      queryWithoutCharPrefix = cleaned.substring(matchChar.end).trim();
    }

    // 2. Direct self-look / portrait / selfie requests
    final selfLookPatterns = [
      RegExp(r'^(?:can you\s+|could you\s+|please\s+)?(?:show me|send me|take|wys my|stuur vir my|gee my)\s+(?:what you look like|your face|how you look|a photo of you|a photo of yourself|a picture of yourself|a selfie|a selfie of yourself|\x27n foto van jou|\x27n foto van jouself|\x27n prent van jouself|hoe jy lyk|jou gesig|\x27n selfie)$', caseSensitive: false),
      RegExp(r'^(?:what do you look like|what do u look like|hoe lyk jy)$', caseSensitive: false),
    ];

    for (final pattern in selfLookPatterns) {
      if (pattern.hasMatch(cleaned) || pattern.hasMatch(queryWithoutCharPrefix)) {
        return ImageIntentResult(
          isIntent: true,
          rawPrompt: 'photo of yourself',
          isSelfReference: true,
          explicitCharacterId: explicitCharacterFromPrefix,
          isPhotoOrSelfie: true,
          isFullBody: false,
          isArtistic: false,
          specificScene: null,
        );
      }
    }

    // 3. Structured pattern matching for creation requests
    final patterns = [
      // Pattern A: "create/generate/make/draw/paint/show me/give me/send me [me] an image/picture/photo/view/scene of <PROMPT>"
      RegExp(
        r"^(?:can you|could you|would you|will you|please|i want you to|i would like you to|i'd like you to|i need you to|kan jy|asseblief|ek wil he jy moet)?\s*(?:please|asseblief)?\s*(?:create|generate|make|draw|paint|render|produce|design|show|show me|give me|send me|display|skep|maak|genereer|teken|verf|wys|wys my|gee my|stuur vir my)\s+(?:me\s+|vir my\s+)?(?:an?\s+|the\s+|\x27n\s+)?(?:.*?\s+)?(?:image|picture|photo|photograph|selfie|painting|artwork|illustration|drawing|portrait|prent|prentjie|foto|kiekie|skildery|skets|view|scene|landscape|panorama|wallpaper|render|rendering|visual|shot|uitsig|toneel|landskap)\s+(?:of|showing|depicting|with|about|van|met|oor)\s+(.+)$",
        caseSensitive: false,
      ),
      // Pattern B: "create/generate/make/draw/paint [me] an image/picture/photo/view: <PROMPT>"
      RegExp(
        r"^(?:can you|could you|would you|will you|please|i want you to|i would like you to|i'd like you to|i need you to|kan jy|asseblief)?\s*(?:please|asseblief)?\s*(?:create|generate|make|draw|paint|render|produce|show me|wys my|skep|maak|genereer|teken|verf)\s+(?:me\s+|vir my\s+)?(?:an?\s+|the\s+|\x27n\s+)?(?:.*?\s+)?(?:image|picture|photo|selfie|painting|artwork|prent|prentjie|foto|kiekie|skildery|view|scene|landscape|panorama|uitsig|toneel|landskap)\s*[:,\-]\s*(.+)$",
        caseSensitive: false,
      ),
      // Pattern C: "can you [please] draw/paint/sketch [me] [a/an] <PROMPT>"
      RegExp(
        r"^(?:can you|could you|would you|will you|please|i want you to|i would like you to|i'd like you to|kan jy|asseblief)?\s*(?:please|asseblief)?\s*(?:draw|paint|sketch|teken|verf|skets)\s+(?:me\s+|vir my\s+)?(?:an?\s+|\x27n\s+)?(.+)$",
        caseSensitive: false,
      ),
      // Pattern D: "Show me [SCENE] at/in/over [LOCATION]" (e.g. "Show me Table Mountain at sunset", "Wys my Tafelberg teen sonsondergang")
      RegExp(
        r"^(?:can you\s+|could you\s+|please\s+)?(?:show me|wys my)\s+([a-zA-Z0-9\s\x27\-]+(?:\s+(?:at|in|on|over|during|teen|in die|op die|by)\s+[a-zA-Z0-9\s\x27\-]+)+)$",
        caseSensitive: false,
      ),
      // Pattern E: "create/generate [me] a photorealistic/realistic <PROMPT>"
      RegExp(
        r"^(?:can you|could you|would you|will you|please|i want you to|i would like you to|i'd like you to|kan jy|asseblief)?\s*(?:please|asseblief)?\s*(?:create|generate|make|draw|paint|render|produce|design|skep|maak|genereer|teken|verf)\s+(?:me\s+|vir my\s+)?(?:an?\s+|the\s+|\x27n\s+)?(?:photorealistic|photo-realistic|hyperrealistic|realistic|realistiese)\s+(.+)$",
        caseSensitive: false,
      ),
      // Pattern F: Direct generic creation: "generate/create a futuristic spaceship", "skep 'n ruimteskip"
      RegExp(
        r"^(?:can you|could you|would you|will you|please|i want you to|i would like you to|i'd like you to|kan jy|asseblief)?\s*(?:please|asseblief)?\s*(?:create|generate|skep|genereer)\s+(?:me\s+|vir my\s+)?((?:an?\s+|\x27n\s+).+)$",
        caseSensitive: false,
      ),
    ];

    for (final queryToTest in [queryWithoutCharPrefix, cleaned]) {
      for (final pattern in patterns) {
        final match = pattern.firstMatch(queryToTest);
        if (match != null && match.groupCount >= 1) {
          var rawExtracted = match.group(match.groupCount)?.trim() ?? '';
          rawExtracted = rawExtracted.replaceAll(RegExp(r'^[\,\:\-\s]+'), '').trim();
          if (rawExtracted.isNotEmpty && rawExtracted.length > 1) {
            return _parseImageSubject(
              fullQuery: cleaned,
              extractedSubject: rawExtracted,
              explicitCharacterFromPrefix: explicitCharacterFromPrefix,
            );
          }
        }
      }
    }

    // 4. General natural-language image-generation fallback.
    //
    // Keep this after the structured patterns so the established self-reference,
    // character targeting, Afrikaans handling, scene extraction, and negative
    // guards continue to take precedence.
    //
    // Family 1/2: image-generation action + image noun + optional connector + subject.
    final naturalImageAction = RegExp(
      r'^(?:can you|could you|would you|will you|please|i want you to|i would like you to|i\x27d like you to|i need you to|'
      r'kan jy|asseblief|ek wil he jy moet)?\s*'
      r'(?:please|asseblief)?\s*'
      r'(?:create|generate|make|draw|paint|render|produce|design|craft|formulate|compose|build|develop|illustrate|'
      r'depict|do|skep|maak|genereer|teken|verf|ontwerp)\s+'
      r'(?:me\s+|for me\s+|vir my\s+)?'
      r'(?:an?\s+|n\s+|\x27n\s+|the\s+|die\s+)?'
      r'(image|picture|photo|photograph|selfie|painting|artwork|illustration|drawing|portrait|poster|scene|'
      r'landscape|panorama|wallpaper|visual|depiction|composition|prent|prentjie|foto|skildery|skets|portret|'
      r'illustrasie|tekening|uitsig|toneel|landskap)'
      r'(?:\s+(?:of|showing|depicting|with|about|from|of|van|met|oor))?\s+'
      r'(.+)$',
      caseSensitive: false,
    );

    for (final queryToTest in [queryWithoutCharPrefix, cleaned]) {
      final match = naturalImageAction.firstMatch(queryToTest);
      if (match != null) {
        final subject = match.group(2)?.trim() ?? '';
        if (subject.length > 1) {
          return _parseImageSubject(
            fullQuery: cleaned,
            extractedSubject: subject,
            explicitCharacterFromPrefix: explicitCharacterFromPrefix,
          );
        }
      }
    }

    // Family 3: strongly visual verbs can naturally take a subject without an
    // explicit image noun, e.g. "visualize Cape Town harbour at night".
    final naturalVisualVerb = RegExp(
      r'^(?:can you|could you|would you|will you|please|i want you to|i would like you to|i\x27d like you to|i need you to|'
      r'kan jy|asseblief|ek wil he jy moet)?\s*'
      r'(?:please|asseblief)?\s*'
      r'(?:visualize|portray|depict|illustrate|render|visualiseer|beeld uit|verbeeld|'
      r'uitbeeld|illustreer)\s+'
      r'(.+)$',
      caseSensitive: false,
    );

    for (final queryToTest in [queryWithoutCharPrefix, cleaned]) {
      final match = naturalVisualVerb.firstMatch(queryToTest);
      if (match != null) {
        final subject = match.group(1)?.trim() ?? '';
        if (subject.length > 1) {
          return _parseImageSubject(
            fullQuery: cleaned,
            extractedSubject: subject,
            explicitCharacterFromPrefix: explicitCharacterFromPrefix,
          );
        }
      }
    }

    return null;
  }

  static ImageIntentResult _parseImageSubject({
    required String fullQuery,
    required String extractedSubject,
    String? explicitCharacterFromPrefix,
  }) {
    final queryLower = fullQuery.toLowerCase();
    final subjectLower = extractedSubject.toLowerCase();

    // Clean extractedSubject to remove residual conversational prefixes, leading articles, and punctuation
    var cleanPrompt = extractedSubject.trim();
    cleanPrompt = cleanPrompt.replaceAll(RegExp(r'^[\,\:\-\s]+'), '').trim();
    cleanPrompt = cleanPrompt.replaceAll(
      RegExp(
        r'^(?:(?:an?|\x27n|the|die)\s+)?(?:image|picture|photo|photograph|painting|illustration|drawing|prent|prentjie|foto|skildery)\s+(?:of|showing|with|about|van|oor|met)\s+',
        caseSensitive: false,
      ),
      '',
    ).trim();
    // Preserve leading articles such as "a", "an", "the", "'n" and "die".
    // They are part of the user's requested image subject.
    cleanPrompt = cleanPrompt.replaceAll(RegExp(r'[\?\.!\s]+$'), '').trim();
    if (cleanPrompt.isEmpty) {
      cleanPrompt = extractedSubject.trim();
    }

    // Style flags
    final isArtistic = queryLower.contains('draw') ||
        queryLower.contains('sketch') ||
        queryLower.contains('paint') ||
        queryLower.contains('teken') ||
        queryLower.contains('verf') ||
        queryLower.contains('skets') ||
        queryLower.contains('illustration') ||
        queryLower.contains('drawing') ||
        queryLower.contains('painting') ||
        queryLower.contains('skildery');

    final isFullBody = queryLower.contains('full body') ||
        queryLower.contains('full-body') ||
        queryLower.contains('head to toe') ||
        queryLower.contains('full length') ||
        queryLower.contains('volle lyf') ||
        queryLower.contains('kop tot tone');

    final isPhotoOrSelfie = !isArtistic ||
        queryLower.contains('photo') ||
        queryLower.contains('selfie') ||
        queryLower.contains('photograph') ||
        queryLower.contains('foto') ||
        queryLower.contains('kiekie') ||
        queryLower.contains('realistic');

    // Check for explicit character reference
    String? explicitCharId = explicitCharacterFromPrefix;
    if (explicitCharId == null) {
      if (subjectLower.startsWith('eve ') || subjectLower == 'eve') {
        explicitCharId = 'eve';
      } else if (subjectLower.startsWith('ara ') || subjectLower == 'ara') {
        explicitCharId = 'ara';
      } else if (subjectLower.startsWith('leo ') || subjectLower == 'leo') {
        explicitCharId = 'leo';
      } else if (subjectLower.startsWith('rex ') || subjectLower == 'rex') {
        explicitCharId = 'rex';
      } else if (subjectLower.startsWith('sal ') || subjectLower == 'sal') {
        explicitCharId = 'sal';
      }
    }

    // Check if subject is self-referential
    final isSelfReference = explicitCharId != null ||
        subjectLower.startsWith('yourself') ||
        subjectLower == 'yourself' ||
        subjectLower.startsWith('you ') ||
        subjectLower == 'you' ||
        subjectLower.startsWith('jouself') ||
        subjectLower == 'jouself' ||
        subjectLower.startsWith('jou ') ||
        subjectLower == 'jou' ||
        subjectLower.contains('what you look like') ||
        subjectLower.contains('hoe jy lyk') ||
        subjectLower.contains('your face') ||
        subjectLower.contains('jou gesig') ||
        subjectLower.startsWith('a selfie') ||
        subjectLower.startsWith("'n selfie");

    String? specificScene;
    if (isSelfReference) {
      var cleanedScene = extractedSubject;
      // Strip leading reference words to isolate scene
      final stripPrefixes = [
        'yourself ',
        'yourself',
        'jouself ',
        'jouself',
        'you ',
        'you',
        'eve ',
        'eve',
        'ara ',
        'ara',
        'leo ',
        'leo',
        'rex ',
        'rex',
        'sal ',
        'sal',
        'what you look like',
        'hoe jy lyk',
        'your face',
        'jou gesig',
        'a selfie of yourself',
        'a selfie of you',
        'a selfie',
        "'n selfie",
      ];

      for (final prefix in stripPrefixes) {
        if (cleanedScene.toLowerCase().startsWith(prefix)) {
          cleanedScene = cleanedScene.substring(prefix.length).trim();
          break;
        }
      }

      // If what's left starts with prepositions, preserve them nicely
      if (cleanedScene.isNotEmpty && cleanedScene.length > 2) {
        // Afrikaans scene requests commonly use "op" as a preposition,
        // while the image prompt/test contract expects the scene itself
        // without the leading preposition (e.g. "op 'n strand" -> "'n strand").
        if (RegExp(r'^op\s+', caseSensitive: false).hasMatch(cleanedScene)) {
          cleanedScene = cleanedScene
              .replaceFirst(
                RegExp(r'^op\s+', caseSensitive: false),
                '',
              )
              .trim();
        }

        specificScene = cleanedScene;
      }
    }

    return ImageIntentResult(
      isIntent: true,
      rawPrompt: cleanPrompt,
      isSelfReference: isSelfReference,
      explicitCharacterId: explicitCharId,
      isPhotoOrSelfie: isPhotoOrSelfie,
      isFullBody: isFullBody,
      isArtistic: isArtistic,
      specificScene: specificScene,
    );
  }
}

/// Result of image intent detection with character and scene metadata.
class ImageIntentResult {
  final bool isIntent;
  final String rawPrompt;
  final bool isSelfReference;
  final String? explicitCharacterId;
  final bool isPhotoOrSelfie;
  final bool isFullBody;
  final bool isArtistic;
  final String? specificScene;

  const ImageIntentResult({
    required this.isIntent,
    required this.rawPrompt,
    this.isSelfReference = false,
    this.explicitCharacterId,
    this.isPhotoOrSelfie = true,
    this.isFullBody = false,
    this.isArtistic = false,
    this.specificScene,
  });
}
