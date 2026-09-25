import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/evidence_item.dart';
import '../models/tool_execution_record.dart';
import '../models/tool_result.dart';
import 'action_ledger.dart';
import 'ai_tool.dart';

/// Orchestrates provider-independent tool evaluation and execution for Listen to Eve.
///
/// Positioned between [ChatProvider] and [AiService] to ensure:
/// 1. Provider Independence: Tool decisions and executions do not depend on Gemini or xAI
/// 2. Memory Isolation: External tool findings never enter long-term user memory
/// 3. Conversational Safety: Bounded timeouts, snippet limits, and graceful error fallbacks
/// 4. Action Continuity: Automatically logs tool execution records into [ActionLedger]
class IntelligenceOrchestrator {
  final List<AiTool> _tools;
  ActionLedger? _actionLedger;

  /// Maximum allowed characters for a single tool snippet to prevent context bloating.
  static const int maxSnippetLength = 1200;

  /// Default execution timeout for external tools.
  static const Duration defaultToolTimeout = Duration(seconds: 10);

  IntelligenceOrchestrator({
    List<AiTool>? tools,
    ActionLedger? actionLedger,
  })  : _tools = tools ?? [],
        _actionLedger = actionLedger;

  /// List of currently registered tools.
  List<AiTool> get tools => List.unmodifiable(_tools);

  /// Active action ledger for recording conversational actions.
  ActionLedger? get actionLedger => _actionLedger;

  /// Attaches or updates the action ledger.
  set actionLedger(ActionLedger? ledger) {
    _actionLedger = ledger;
  }

  /// Registers an additional tool into the orchestrator.
  void registerTool(AiTool tool) {
    _tools.removeWhere((t) => t.id == tool.id);
    _tools.add(tool);
  }

  /// Returns a registered tool of type [T], if present.
  T? getTool<T extends AiTool>() {
    for (final tool in _tools) {
      if (tool is T) return tool;
    }
    return null;
  }

  /// Evaluates whether any registered tool is needed for the given user message
  /// and executes the first matching tool within safety boundaries.
  ///
  /// If a triggered tool fails or returns no data, subsequent matching tools
  /// (e.g. WebSearch fallback) are evaluated in sequence.
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

        if (result == null ||
            result.snippet.trim().isEmpty ||
            (result.confidence != null && result.confidence! <= 0.0) ||
            result.metadata['status'] == 'unavailable') {
          debugPrint('[Orchestrator] Tool ${tool.name} yielded no valid metrics; checking next candidate tool.');
          _actionLedger?.recordAction(ToolExecutionRecord(
            toolName: tool.id,
            purpose: tool.name,
            query: trimmed,
            timestamp: DateTime.now(),
            success: false,
            resultCount: 0,
            error: 'No valid data returned',
          ));
          continue;
        }

        // Enforce prompt context boundaries: truncate oversized snippets
        ToolResult finalResult = result;
        if (result.snippet.length > maxSnippetLength) {
          final boundedSnippet =
              '${result.snippet.substring(0, maxSnippetLength).trim()}... [truncated for brevity]';
          finalResult = ToolResult(
            toolId: result.toolId,
            title: result.title,
            snippet: boundedSnippet,
            url: result.url,
            retrievedAt: result.retrievedAt,
            confidence: result.confidence,
            metadata: result.metadata,
          );
        }

        // Record successful tool execution in action ledger
        final sourcesList = <String>[];
        if (finalResult.metadata['sources'] is List) {
          sourcesList.addAll(
            (finalResult.metadata['sources'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty),
          );
        }
        if (sourcesList.isEmpty && finalResult.url != null && finalResult.url!.isNotEmpty) {
          sourcesList.add(finalResult.url!);
        }

        final evidenceList = <EvidenceItem>[];
        if (finalResult.metadata['evidence'] is List) {
          for (final item in (finalResult.metadata['evidence'] as List)) {
            if (item is Map) {
              try {
                evidenceList.add(EvidenceItem.fromJson(Map<String, dynamic>.from(item)));
              } catch (_) {}
            }
          }
        }

        final resultCount = finalResult.metadata['resultCount'] is int
            ? finalResult.metadata['resultCount'] as int
            : (sourcesList.isNotEmpty ? sourcesList.length : 1);

        _actionLedger?.recordAction(ToolExecutionRecord(
          toolName: finalResult.toolId,
          purpose: tool.name,
          query: trimmed,
          timestamp: finalResult.retrievedAt,
          success: true,
          resultCount: resultCount,
          sources: sourcesList,
          evidence: evidenceList,
          summary: finalResult.snippet.length > 500
              ? '${finalResult.snippet.substring(0, 497)}...'
              : finalResult.snippet,
        ));

        return finalResult;
      } catch (e, stack) {
        debugPrint('[Orchestrator] Tool execution error for ${tool.name}: $e');
        debugPrint(stack.toString());
        _actionLedger?.recordAction(ToolExecutionRecord(
          toolName: tool.id,
          purpose: tool.name,
          query: trimmed,
          timestamp: DateTime.now(),
          success: false,
          resultCount: 0,
          error: e.toString(),
        ));
        // Check next candidate tool if this one encounters an unhandled exception
        continue;
      }
    }

    return null;
  }
}
