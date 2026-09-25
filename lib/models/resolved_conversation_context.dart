import 'tool_execution_record.dart';

/// Represents the resolved conversational context for an incoming user message.
///
/// Discovered by [ConversationContextResolver] by combining the current input
/// with runtime [ConversationState] and [ActionLedger] history.
class ResolvedConversationContext {
  /// Whether the current message is a conversational follow-up to previous turns/actions.
  final bool isFollowUp;

  /// The resolved intent of the user message (e.g., 'show_search_sources', 'query_search_results',
  /// 'clarify_weather', 'modify_image', 'topic_continuation', 'general_query', 'new_topic').
  final String resolvedIntent;

  /// The active topic being referenced (resolved from state or input).
  final String? activeTopic;

  /// The active task or tool context referenced (e.g., 'web_search', 'weather_lookup', 'image_generation').
  final String? activeTask;

  /// Key entities relevant to this turn (e.g. {'user_name': 'Chris Loubser'}).
  final Map<String, String> activeEntities;

  /// The specific [ToolExecutionRecord] from [ActionLedger] that this follow-up refers to, if any.
  final ToolExecutionRecord? referencedToolExecution;

  /// The original user message.
  final String originalMessage;

  const ResolvedConversationContext({
    required this.isFollowUp,
    required this.resolvedIntent,
    this.activeTopic,
    this.activeTask,
    this.activeEntities = const {},
    this.referencedToolExecution,
    this.originalMessage = '',
  });

  /// True if the user is asking about the sources, sites, or methodology of the previous search/action.
  bool get isAskingForSources =>
      resolvedIntent == 'show_search_sources' ||
      resolvedIntent == 'show_search_sources_empty';

  /// True if the user is asking for more details or elaboration from the previous search.
  bool get isAskingForDetails => resolvedIntent == 'query_search_results';

  /// Generates a provider-independent prompt block for LLM context injection.
  String? formatForPrompt({String language = 'en'}) {
    if (!isFollowUp) return null;

    final isAf = language == 'af';
    final rec = referencedToolExecution;

    if (isAskingForSources) {
      if (rec != null) {
        final sourcesStr = rec.sources.isNotEmpty
            ? rec.sources.join(', ')
            : (isAf ? 'geen direkte skakels' : 'no direct links');

        if (isAf) {
          return '''
[GESPREK OPVOLG-KONTEKS: BRONNE EN NASLAANINLIGTING]
Die gebruiker vra nou waar jy gesoek het of watter bronne jy gebruik het vir hul vorige navraag ("${rec.query}").
- Gereedskap/Aksie: ${rec.toolName}
- Resultaat-status: ${rec.success ? "Suksesvol uitgevoer" : "Misluk of geen resultate nie"}
- Werklike bronne geraadpleeg: $sourcesStr
- Opsomming van wat gevind is: ${rec.summary ?? "Geen opsomming"}

Riglyn vir gespreksgenoot:
- Beantwoord die gebruiker se vraag oor waar jy gesoek het natuurlik, warm en eerlik.
- Noem die werklike bronne wat geraadpleeg is ($sourcesStr) sonder om bronne te versin of stelsel-terme/jargon te gebruik.
- As die soektog nie suksesvol was nie of min resultate gehad het, wees eerlik sonder om verskonings te fabriseer.
''';
        } else {
          return '''
[CONVERSATION FOLLOW-UP CONTEXT: SOURCES & LOOKUP INFORMATION]
The user is following up to ask where you looked or what sources you checked for their prior query ("${rec.query}").
- Tool/Action: ${rec.toolName}
- Execution status: ${rec.success ? "Successfully executed" : "Failed or no results"}
- Actual sources consulted: $sourcesStr
- Summary of verified findings: ${rec.summary ?? "No summary"}

Guideline for companion:
- Answer the user's question about where you looked naturally, warmly, and honestly.
- Mention the real sources that were checked ($sourcesStr) without inventing fake sources or using robotic tool jargon.
- If the search did not succeed or had limited results, be transparent without fabricating details.
''';
        }
      } else {
        if (isAf) {
          return '''
[GESPREK OPVOLG-KONTEKS: GEEN VORIGE SOEKTOG]
Die gebruiker vra waar jy gesoek het, maar geen soektog is nog in hierdie gesprek uitgevoer nie.
Riglyn: Laat die gebruiker vriendelik en natuurlik weet dat julle nog niks aanlyn in hierdie gesprek nageslaan het nie.
''';
        } else {
          return '''
[CONVERSATION FOLLOW-UP CONTEXT: NO PRIOR SEARCH]
The user is asking where you looked, but no search has been executed yet in this conversation.
Guideline: Let the user know naturally and warmly that nothing has been looked up online yet in this conversation.
''';
        }
      }
    } else if (isAskingForDetails && rec != null) {
      final sourcesStr = rec.sources.isNotEmpty ? rec.sources.join(', ') : 'public web';
      if (isAf) {
        return '''
[GESPREK OPVOLG-KONTEKS: VERDERE BESONDERHEDE]
Die gebruiker vra verdere besonderhede oor die vorige navraag ("${rec.query}").
- Vorige bevindinge: ${rec.summary ?? ""}
- Bronne: $sourcesStr
''';
      } else {
        return '''
[CONVERSATION FOLLOW-UP CONTEXT: FURTHER DETAILS]
The user is asking for more details regarding the prior query ("${rec.query}").
- Prior findings: ${rec.summary ?? ""}
- Sources: $sourcesStr
''';
      }
    }

    return null;
  }
}
