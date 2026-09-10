import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/tool_result.dart';
import 'ai_tool.dart';

/// Orchestrates provider-independent tool evaluation and execution for Listen to Eve.
///
/// Positioned between [ChatProvider] and [AiService] to ensure:
/// 1. Provider Independence: Tool decisions and executions do not depend on Gemini or xAI
/// 2. Memory Isolation: External tool findings never enter long-term user memory
/// 3. Conversational Safety: Bounded timeouts, snippet limits, and graceful error fallbacks
class IntelligenceOrchestrator {
  final List<AiTool> _tools;

  /// Maximum allowed characters for a single tool snippet to prevent context bloating.
  static const int maxSnippetLength = 1200;

  /// Default execution timeout for external tools.
  static const Duration defaultToolTimeout = Duration(seconds: 6);

  IntelligenceOrchestrator({List<AiTool>? tools}) : _tools = tools ?? [];

  /// List of currently registered tools.
  List<AiTool> get tools => List.unmodifiable(_tools);

  /// Registers an additional tool into the orchestrator.
  void registerTool(AiTool tool) {
    _tools.removeWhere((t) => t.id == tool.id);
    _tools.add(tool);
  }

  /// Evaluates whether any registered tool is needed for the given user message
  /// and executes the first matching tool within safety boundaries.
  ///
  /// Returns a bounded [ToolResult] if a tool successfully produced facts,
  /// or `null` if no tool was required, if execution timed out, or if it failed.
  Future<ToolResult?> evaluateAndExecute(
    String userMessage, {
    List<Map<String, String>>? conversationHistory,
    Map<String, dynamic>? parameters,
  }) async {
    if (_tools.isEmpty) return null;

    final trimmed = userMessage.trim();
    if (trimmed.isEmpty) return null;

    for (final tool in _tools) {
      try {
        final shouldRun = tool.shouldTrigger(
          trimmed,
          conversationHistory: conversationHistory,
        );

        if (!shouldRun) continue;

        debugPrint('[Orchestrator] Invoking tool: ${tool.name} for query: "$trimmed"');

        final result = await tool
            .execute(trimmed, parameters: parameters)
            .timeout(defaultToolTimeout, onTimeout: () {
          debugPrint('[Orchestrator] Tool ${tool.name} timed out after ${defaultToolTimeout.inSeconds}s');
          return null;
        });

        if (result == null || result.snippet.trim().isEmpty) {
          continue;
        }

        // Enforce prompt context boundaries: truncate oversized snippets
        if (result.snippet.length > maxSnippetLength) {
          final boundedSnippet =
              '${result.snippet.substring(0, maxSnippetLength).trim()}... [truncated for brevity]';
          return ToolResult(
            toolId: result.toolId,
            title: result.title,
            snippet: boundedSnippet,
            url: result.url,
            retrievedAt: result.retrievedAt,
            confidence: result.confidence,
            metadata: result.metadata,
          );
        }

        return result;
      } catch (e, stack) {
        debugPrint('[Orchestrator] Tool execution error for ${tool.name}: $e');
        debugPrint(stack.toString());
        // Do not crash conversational flow on tool failure
        return null;
      }
    }

    return null;
  }
}
