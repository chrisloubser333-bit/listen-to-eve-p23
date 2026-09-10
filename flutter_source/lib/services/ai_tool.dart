import '../models/tool_result.dart';

/// Abstract contract for pluggable tools and knowledge providers in Listen to Eve.
///
/// Designed to maintain complete provider independence:
/// - Tools can be invoked regardless of whether Gemini, xAI, or another provider is active
/// - Decisions to use tools are based on conversational intent and knowledge requirements
/// - Outputs conform strictly to [ToolResult] so chat history and memory remain unpolluted
abstract class AiTool {
  /// Unique machine identifier for this tool (e.g. 'web_search', 'weather_lookup').
  String get id;

  /// Human-readable name for logging and diagnostics.
  String get name;

  /// Short description of what this tool provides and when it should be used.
  String get description;

  /// Determines whether this tool should execute based on the user's message
  /// and recent conversation history.
  ///
  /// Distinguishes between:
  /// - Known conversational context or personal memory (return false)
  /// - Current, external, or factual queries requiring fresh lookup (return true)
  bool shouldTrigger(
    String userMessage, {
    List<Map<String, String>>? conversationHistory,
  });

  /// Executes the tool and returns a structured, bounded [ToolResult].
  ///
  /// Must handle timeouts, network failures, and empty results gracefully
  /// without throwing unhandled exceptions to the conversation caller.
  Future<ToolResult?> execute(
    String userMessage, {
    Map<String, dynamic>? parameters,
  });
}
