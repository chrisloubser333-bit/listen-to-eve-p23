import 'package:flutter/foundation.dart';
import '../models/conversation_state.dart';
import '../models/resolved_conversation_context.dart';
import '../models/tool_execution_record.dart';
import 'action_ledger.dart';

/// Resolves user message intent and conversational follow-ups in Listen to Eve.
///
/// Principles (Companion Core V1 Phase 2):
/// 1. Zero-dependency, provider-independent resolution logic
/// 2. Leverages runtime [ActionLedger] and [ConversationState] to resolve context
/// 3. Detects anaphoric and implicit follow-ups (e.g. "Where did you look?", "What did you find?")
/// 4. Preserves genuine evidence/sources from [ActionLedger] without fabricating sources
/// 5. Ensures topic shifts properly break follow-up chains without ghost context
class ConversationContextResolver {
  const ConversationContextResolver();

  /// Resolves the conversational context for an incoming [userMessage].
  ResolvedConversationContext resolve(
    String userMessage, {
    ConversationState? state,
    ActionLedger? ledger,
    List<Map<String, String>>? conversationHistory,
  }) {
    final clean = userMessage.trim();
    final lower = clean.toLowerCase();

    if (clean.isEmpty) {
      return const ResolvedConversationContext(
        isFollowUp: false,
        resolvedIntent: 'empty',
      );
    }

    final currentState = state ?? ledger?.state ?? ConversationState.initial();
    final recentActions = ledger?.recentActions ?? [];
    final lastAction = ledger?.lastAction ?? currentState.lastToolExecution;

    // -------------------------------------------------------------------------
    // 1. Explicit Search Again Commands
    // -------------------------------------------------------------------------
    if (_isSearchAgain(lower)) {
      final searchAction = _findSearchAction(recentActions, lastAction);
      final topic = searchAction?.query ?? currentState.activeTopic;
      return ResolvedConversationContext(
        isFollowUp: false,
        resolvedIntent: 'search_again',
        activeTopic: topic,
        activeTask: 'web_search',
        activeEntities: currentState.activeEntities,
        originalMessage: clean,
      );
    }

    // -------------------------------------------------------------------------
    // 1b. Topic Shift Detection (Explicit New Commands / Independent Topics)
    // -------------------------------------------------------------------------
    if (_isExplicitTopicShift(lower)) {
      final entities = _extractEntities(clean);
      final topic = _extractTopic(clean, lower) ?? (entities.isNotEmpty ? entities.values.first : null);

      return ResolvedConversationContext(
        isFollowUp: false,
        resolvedIntent: _classifyNewIntent(lower),
        activeTopic: topic,
        activeTask: _classifyTask(lower),
        activeEntities: entities,
        originalMessage: clean,
      );
    }

    // -------------------------------------------------------------------------
    // 2. Verification Status & Grounding Inquiries ("Which parts are verified?", "Are you sure?")
    // -------------------------------------------------------------------------
    if (_isVerificationInquiry(lower)) {
      final searchAction = _findSearchAction(recentActions, lastAction);
      return ResolvedConversationContext(
        isFollowUp: true,
        resolvedIntent: 'ask_verification_status',
        activeTopic: searchAction?.query ?? currentState.activeTopic,
        activeTask: searchAction?.toolName,
        activeEntities: currentState.activeEntities,
        referencedToolExecution: searchAction,
        originalMessage: clean,
      );
    }

    // -------------------------------------------------------------------------
    // 3. Source & Lookup Inquiries ("Where did you look?", "What sources?", etc.)
    // -------------------------------------------------------------------------
    if (_isSourceInquiry(lower)) {
      // Find the most recent search or lookup action
      final searchAction = _findSearchAction(recentActions, lastAction);

      if (searchAction != null) {
        debugPrint(
          '[ContextResolver] Resolved source inquiry follow-up to prior action: ${searchAction.toolName} (query: "${searchAction.query}", sources: ${searchAction.sources})',
        );
        return ResolvedConversationContext(
          isFollowUp: true,
          resolvedIntent: 'show_search_sources',
          activeTopic: searchAction.query,
          activeTask: searchAction.toolName,
          activeEntities: currentState.activeEntities,
          referencedToolExecution: searchAction,
          originalMessage: clean,
        );
      } else {
        // No search was executed in the conversation
        return ResolvedConversationContext(
          isFollowUp: true,
          resolvedIntent: 'show_search_sources_empty',
          activeTopic: currentState.activeTopic,
          activeTask: null,
          activeEntities: currentState.activeEntities,
          referencedToolExecution: null,
          originalMessage: clean,
        );
      }
    }

    // -------------------------------------------------------------------------
    // 3. Search Result Inquiries ("What did you find?", "What else?", etc.)
    // -------------------------------------------------------------------------
    if (_isResultInquiry(lower)) {
      final searchAction = _findSearchAction(recentActions, lastAction);

      if (searchAction != null) {
        return ResolvedConversationContext(
          isFollowUp: true,
          resolvedIntent: 'query_search_results',
          activeTopic: searchAction.query,
          activeTask: searchAction.toolName,
          activeEntities: currentState.activeEntities,
          referencedToolExecution: searchAction,
          originalMessage: clean,
        );
      }
    }

    // -------------------------------------------------------------------------
    // 4. Weather Follow-Up Inquiries ("Will it rain?", "What about tomorrow?", etc.)
    // -------------------------------------------------------------------------
    if (_isWeatherFollowUp(lower, currentState, lastAction)) {
      final weatherAction = _findActionByTool(recentActions, ['weather_lookup', 'weather']) ?? lastAction;
      return ResolvedConversationContext(
        isFollowUp: true,
        resolvedIntent: 'clarify_weather',
        activeTopic: 'weather',
        activeTask: 'weather_lookup',
        activeEntities: currentState.activeEntities,
        referencedToolExecution: weatherAction,
        originalMessage: clean,
      );
    }

    // -------------------------------------------------------------------------
    // 5. Image Modification Follow-Up ("Make it brighter", "Draw it again", etc.)
    // -------------------------------------------------------------------------
    if (_isImageFollowUp(lower, currentState, lastAction)) {
      final imageAction = _findActionByTool(recentActions, ['image_generation', 'generate_image']) ?? lastAction;
      return ResolvedConversationContext(
        isFollowUp: true,
        resolvedIntent: 'modify_image',
        activeTopic: imageAction?.query ?? 'image_generation',
        activeTask: 'image_generation',
        activeEntities: currentState.activeEntities,
        referencedToolExecution: imageAction,
        originalMessage: clean,
      );
    }

    // -------------------------------------------------------------------------
    // 6. Generic Anaphora / Topic Continuation ("Tell me more about that", "Is it true?")
    // -------------------------------------------------------------------------
    if (_isAnaphoricContinuation(lower) && currentState.activeTopic != null) {
      return ResolvedConversationContext(
        isFollowUp: true,
        resolvedIntent: 'topic_continuation',
        activeTopic: currentState.activeTopic,
        activeTask: currentState.activeTask,
        activeEntities: currentState.activeEntities,
        referencedToolExecution: lastAction,
        originalMessage: clean,
      );
    }

    // -------------------------------------------------------------------------
    // 7. Standard New Query / Introduction
    // -------------------------------------------------------------------------
    final extractedEntities = _extractEntities(clean);
    final combinedEntities = {...currentState.activeEntities, ...extractedEntities};
    final detectedTopic = _extractTopic(clean, lower) ??
        (extractedEntities.containsKey('user_name') ? extractedEntities['user_name'] : currentState.activeTopic);

    return ResolvedConversationContext(
      isFollowUp: false,
      resolvedIntent: _classifyNewIntent(lower),
      activeTopic: detectedTopic,
      activeTask: _classifyTask(lower),
      activeEntities: combinedEntities,
      originalMessage: clean,
    );
  }

  // ---------------------------------------------------------------------------
  // Detection Helpers (Bilingual EN / AF)
  // ---------------------------------------------------------------------------

  bool _isSearchAgain(String lower) {
    const searchAgainPatterns = [
      'search again',
      'search online again',
      'try searching again',
      'do another search',
      'run another search',
      'look up again',
      'check online again',
      // Afrikaans
      'soek weer',
      'probeer weer soek',
      'doen weer \'n soektog',
      'soek weer aanlyn',
      'kyk weer aanlyn',
    ];
    for (final pattern in searchAgainPatterns) {
      if (lower == pattern || lower.contains(pattern)) return true;
    }
    return false;
  }

  bool _isVerificationInquiry(String lower) {
    const verificationPatterns = [
      'which parts are verified',
      'what parts are verified',
      'what is verified',
      'is that verified',
      'is this verified',
      'how do you know',
      'are you sure',
      'are you certain',
      'is that true',
      'can you prove it',
      'what is confirmed',
      // Afrikaans
      'watter dele is geverifieer',
      'wat is geverifieer',
      'is dit geverifieer',
      'hoe weet jy',
      'is jy seker',
      'is jy seker daarvan',
      'is dit waar',
      'wat is bevestig',
    ];
    for (final pattern in verificationPatterns) {
      if (lower == pattern || lower.contains(pattern)) return true;
    }
    return false;
  }

  bool _isSourceInquiry(String lower) {
    const sourcePatterns = [
      // English
      'where did you look',
      'where did you search',
      'what were your sources',
      'what were the sources',
      'what are the sources',
      'which sources',
      'what sources',
      'which websites',
      'what websites',
      'which sites',
      'what sites',
      'where did you find that',
      'where did that come from',
      'where did you get that',
      'where did you see that',
      'what links',
      'show me sources',
      'show sources',
      'sources please',
      'source please',
      'where online',
      'where did you find this',
      // Afrikaans
      'waar het jy gekyk',
      'waar het jy gesoek',
      'watter bronne',
      'watse bronne',
      'watter webtuistes',
      'watse webtuistes',
      'watter webwerwe',
      'watse webwerwe',
      'waar het jy dit gekry',
      'waar kom dit vandaan',
      'waar het jy dit gesien',
      'wys die bronne',
      'wys bronne',
      'bronne asseblief',
      'waar aanlyn',
    ];

    for (final pattern in sourcePatterns) {
      if (lower == pattern || lower.startsWith('$pattern ') || lower.endsWith(' $pattern') || lower.contains(' $pattern ') || lower.contains(pattern)) {
        return true;
      }
    }

    return false;
  }

  bool _isResultInquiry(String lower) {
    const resultPatterns = [
      // English
      'what did you find',
      'what else did you find',
      'did you find anything else',
      'did you find anything interesting',
      'what did the search say',
      'show me the results',
      'what were the results',
      'tell me more about what you found',
      // Afrikaans
      'wat het jy gevind',
      'wat het jy nog gevind',
      'het jy enigiets anders gevind',
      'het jy iets interessants gevind',
      'wat sê die soektog',
      'wys die resultate',
      'wat was die resultate',
      'vertel my meer van wat jy gevind het',
    ];

    for (final pattern in resultPatterns) {
      if (lower.contains(pattern)) return true;
    }

    return false;
  }

  bool _isWeatherFollowUp(String lower, ConversationState state, ToolExecutionRecord? lastAction) {
    final isWeatherContext = state.activeTopic == 'weather' ||
        state.activeTask == 'weather_lookup' ||
        (lastAction != null && lastAction.toolName.contains('weather'));

    if (!isWeatherContext) return false;

    const weatherFollowUps = [
      'will it rain',
      'is it going to rain',
      'what about tomorrow',
      'what about tonight',
      'what about this weekend',
      'how hot is it',
      'is it windy',
      'what is the temperature',
      // Afrikaans
      'gaan dit reën',
      'gaan dit reen',
      'wat van môre',
      'wat van more',
      'wat van vanaand',
      'hoe warm is dit',
      'waai die wind',
    ];

    for (final wf in weatherFollowUps) {
      if (lower.contains(wf)) return true;
    }

    return false;
  }

  bool _isImageFollowUp(String lower, ConversationState state, ToolExecutionRecord? lastAction) {
    final isImageContext = state.activeTask == 'image_generation' ||
        (lastAction != null && lastAction.toolName.contains('image'));

    if (!isImageContext) return false;

    const imageFollowUps = [
      'make it brighter',
      'change the background',
      'make it a photo',
      'draw it again',
      'can you add',
      'make it darker',
      // Afrikaans
      'maak dit helderder',
      'verander die agtergrond',
      'teken dit weer',
      'maak dit donkerder',
    ];

    for (final img in imageFollowUps) {
      if (lower.contains(img)) return true;
    }

    return false;
  }

  bool _isAnaphoricContinuation(String lower) {
    const anaphoricPhrases = [
      'tell me more',
      'can you elaborate',
      'explain that',
      'is that true',
      'why is that',
      'how come',
      'when did that happen',
      // Afrikaans
      'vertel my meer',
      'kan jy uitbrei',
      'verduidelik dit',
      'is dit waar',
      'hoekom is dit so',
      'wanneer het dit gebeur',
    ];

    for (final ap in anaphoricPhrases) {
      if (lower.contains(ap)) return true;
    }

    return false;
  }

  bool _isExplicitTopicShift(String lower) {
    // Explicit new tools or domains that completely reset conversational focus
    if (lower.startsWith('weather in ') ||
        lower.startsWith('weer in ') ||
        lower.startsWith('temperature in ') ||
        lower.startsWith('what is photosynthesis') ||
        lower.startsWith('wat is fotosintese') ||
        lower.startsWith('tell me a joke') ||
        lower.startsWith('vertel \'n grappie') ||
        lower.startsWith('write a poem') ||
        lower.startsWith('skryf \'n gedig')) {
      return true;
    }

    return false;
  }

  ToolExecutionRecord? _findSearchAction(
    List<ToolExecutionRecord> recentActions,
    ToolExecutionRecord? lastAction,
  ) {
    // 1. Check lastAction
    if (lastAction != null && (lastAction.toolName == 'web_search' || lastAction.toolName == 'search')) {
      return lastAction;
    }

    // 2. Check recent successful web searches
    for (final action in recentActions) {
      if (action.toolName == 'web_search' || action.toolName == 'search') {
        return action;
      }
    }

    return null;
  }

  ToolExecutionRecord? _findActionByTool(
    List<ToolExecutionRecord> recentActions,
    List<String> toolNames,
  ) {
    for (final action in recentActions) {
      if (toolNames.contains(action.toolName)) {
        return action;
      }
    }
    return null;
  }

  String _classifyNewIntent(String lower) {
    if (lower.contains('facts') || lower.contains('feite') || lower.contains('find') || lower.contains('soek')) {
      return 'ask_facts';
    }
    if (lower.contains('weather') || lower.contains('weer')) {
      return 'ask_weather';
    }
    if (lower.contains('hello') || lower.contains('hi') || lower.contains('hallo')) {
      return 'greeting';
    }
    return 'general_query';
  }

  String? _classifyTask(String lower) {
    if (lower.contains('facts') || lower.contains('feite') || lower.contains('find') || lower.contains('soek')) {
      return 'web_search';
    }
    if (lower.contains('weather') || lower.contains('weer')) {
      return 'weather_lookup';
    }
    return null;
  }

  Map<String, String> _extractEntities(String text) {
    final entities = <String, String>{};

    // Extract introduced name: "I am Chris Loubser", "My name is...", "Ek is..."
    final nameRegex = RegExp(
      r"\b(?:i\s+am|i'm|my\s+name\s+is|call\s+me|ek\s+is|my\s+naam\s+is|noem\s+my)\s+([A-Za-z]+(?:\s+[A-Za-z]+)*)",
      caseSensitive: false,
    );
    final match = nameRegex.firstMatch(text);
    if (match != null) {
      const statusWords = {
        'fine', 'good', 'okay', 'well', 'tired', 'exhausted', 'busy', 'ready', 'just', 'wondering',
        'asking', 'trying', 'thinking', 'moeg', 'besig', 'siek', 'hier', 'terug'
      };
      final rawName = match.group(1)!.trim().replaceAll(RegExp(r'[^\w\s]'), '');
      final words = rawName.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.isNotEmpty && !statusWords.contains(words.first.toLowerCase())) {
        const stopWords = {'and', 'but', 'what', 'who', 'how', 'why', 'can', 'en', 'maar', 'wat', 'kan'};
        final validParts = <String>[];
        for (final w in words) {
          if (stopWords.contains(w.toLowerCase())) break;
          validParts.add(w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''));
        }
        if (validParts.isNotEmpty) {
          entities['user_name'] = validParts.join(' ');
        }
      }
    }

    return Map.unmodifiable(entities);
  }

  String? _extractTopic(String rawText, String lower) {
    if (lower.contains('weather in ') || lower.contains('weer in ')) {
      final match = RegExp(r'(?:weather in|weer in)\s+([A-Za-z\s]+)', caseSensitive: false).firstMatch(rawText);
      if (match != null) return 'weather_${match.group(1)?.trim()}';
      return 'weather';
    }
    if (lower.contains('photosynthesis') || lower.contains('fotosintese')) {
      return 'photosynthesis';
    }
    return null;
  }
}
