import 'tool_execution_record.dart';

/// Lightweight in-memory representation of ongoing conversational state.
///
/// Tracks the immediate conversational context across turns:
/// - Active topic being discussed
/// - Ongoing task or user goal
/// - Last recognized user intent
/// - Last substantive claim made by the assistant
/// - Most recent tool execution record
/// - Tracked active entities (e.g. named persons, locations, objects)
/// - Whether the current turn is recognized as a follow-up
///
/// Designed to be provider-independent, lightweight, and strictly segregated
/// from permanent long-term memory (Hive).
class ConversationState {
  /// The active subject or topic currently under discussion (e.g. 'user_identity', 'weather', 'vacation').
  final String? activeTopic;

  /// The active task or goal being pursued (e.g. 'research_user', 'plan_itinerary').
  final String? activeTask;

  /// The intent detected on the most recent user turn (e.g. 'ask_facts', 'follow_up', 'greeting').
  final String? lastUserIntent;

  /// The last substantive assertion or claim made by the assistant (e.g. 'I searched publicly online').
  final String? lastAssistantClaim;

  /// The most recent tool execution record, if any tool was executed in this conversation.
  final ToolExecutionRecord? lastToolExecution;

  /// Active entities identified in recent turns (e.g. {'user_name': 'Chris Loubser', 'city': 'Cape Town'}).
  final Map<String, String> activeEntities;

  /// Whether the active turn was evaluated as a follow-up to prior conversational context.
  final bool isFollowUp;

  /// Sequential user-assistant turn count within the active conversational session.
  final int turnCount;

  /// ID of the currently active companion persona/character (e.g. 'eve', 'ara', 'leo').
  final String? activeCharacterId;

  /// The subject of the current request (e.g. 'user', 'Chris Loubser', 'weather', or topic entity).
  final String? currentSubject;

  /// Previous user message or question.
  final String? previousUserQuestion;

  /// Previous assistant response text.
  final String? previousAssistantResponse;

  /// Search query executed during the most recent research action, if any.
  final String? searchQuery;

  /// Search scope (e.g. 'public_web', 'local_memory').
  final String? searchScope;

  /// Status of the most recent tool operation (e.g. 'success', 'failure', 'unavailable', 'not_requested').
  final String? toolStatus;

  /// Whether the last attempted action succeeded.
  final bool? lastActionSucceeded;

  /// Outstanding unanswered user request if interrupted or pending clarification.
  final String? relevantUnansweredRequest;

  const ConversationState({
    this.activeTopic,
    this.activeTask,
    this.lastUserIntent,
    this.lastAssistantClaim,
    this.lastToolExecution,
    this.activeEntities = const {},
    this.isFollowUp = false,
    this.turnCount = 0,
    this.activeCharacterId,
    this.currentSubject,
    this.previousUserQuestion,
    this.previousAssistantResponse,
    this.searchQuery,
    this.searchScope,
    this.toolStatus,
    this.lastActionSucceeded,
    this.relevantUnansweredRequest,
  });

  /// Creates an empty initial conversation state.
  factory ConversationState.initial({String? activeCharacterId}) =>
      ConversationState(activeCharacterId: activeCharacterId);

  /// Returns a copy of this state with updated fields.
  ConversationState copyWith({
    String? activeTopic,
    String? activeTask,
    String? lastUserIntent,
    String? lastAssistantClaim,
    ToolExecutionRecord? lastToolExecution,
    Map<String, String>? activeEntities,
    bool? isFollowUp,
    int? turnCount,
    String? activeCharacterId,
    String? currentSubject,
    String? previousUserQuestion,
    String? previousAssistantResponse,
    String? searchQuery,
    String? searchScope,
    String? toolStatus,
    bool? lastActionSucceeded,
    String? relevantUnansweredRequest,
    bool clearToolExecution = false,
  }) {
    return ConversationState(
      activeTopic: activeTopic ?? this.activeTopic,
      activeTask: activeTask ?? this.activeTask,
      lastUserIntent: lastUserIntent ?? this.lastUserIntent,
      lastAssistantClaim: lastAssistantClaim ?? this.lastAssistantClaim,
      lastToolExecution: clearToolExecution
          ? null
          : (lastToolExecution ?? this.lastToolExecution),
      activeEntities: activeEntities ?? Map.unmodifiable(this.activeEntities),
      isFollowUp: isFollowUp ?? this.isFollowUp,
      turnCount: turnCount ?? this.turnCount,
      activeCharacterId: activeCharacterId ?? this.activeCharacterId,
      currentSubject: currentSubject ?? this.currentSubject,
      previousUserQuestion: previousUserQuestion ?? this.previousUserQuestion,
      previousAssistantResponse:
          previousAssistantResponse ?? this.previousAssistantResponse,
      searchQuery: searchQuery ?? this.searchQuery,
      searchScope: searchScope ?? this.searchScope,
      toolStatus: toolStatus ?? this.toolStatus,
      lastActionSucceeded: lastActionSucceeded ?? this.lastActionSucceeded,
      relevantUnansweredRequest:
          relevantUnansweredRequest ?? this.relevantUnansweredRequest,
    );
  }

  Map<String, dynamic> toJson() => {
        'activeTopic': activeTopic,
        'activeTask': activeTask,
        'lastUserIntent': lastUserIntent,
        'lastAssistantClaim': lastAssistantClaim,
        'lastToolExecution': lastToolExecution?.toJson(),
        'activeEntities': activeEntities,
        'isFollowUp': isFollowUp,
        'turnCount': turnCount,
        'activeCharacterId': activeCharacterId,
        'currentSubject': currentSubject,
        'previousUserQuestion': previousUserQuestion,
        'previousAssistantResponse': previousAssistantResponse,
        'searchQuery': searchQuery,
        'searchScope': searchScope,
        'toolStatus': toolStatus,
        'lastActionSucceeded': lastActionSucceeded,
        'relevantUnansweredRequest': relevantUnansweredRequest,
      };

  @override
  String toString() =>
      'ConversationState(character: $activeCharacterId, turns: $turnCount, topic: $activeTopic, task: $activeTask, lastTool: ${lastToolExecution?.toolName}, isFollowUp: $isFollowUp)';
}
