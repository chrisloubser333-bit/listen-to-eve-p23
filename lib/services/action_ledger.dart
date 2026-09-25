import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/conversation_state.dart';
import '../models/evidence_item.dart';
import '../models/tool_execution_record.dart';

/// Lightweight in-memory service for managing conversation state and action history.
///
/// Principles:
/// - Provider-independent: works identically with Gemini, OpenAI, xAI, or offline
/// - Memory-isolated: NEVER writes to Hive or permanent personal memory
/// - Security-hardened: prevents API keys, headers, or secrets from entering state
/// - Real-time: records tool successes and failures immediately when known
class ActionLedger extends ChangeNotifier {
  /// Maximum number of recent tool executions kept in working memory.
  static const int maxRecentActions = 10;

  final List<ToolExecutionRecord> _recentActions = [];
  ConversationState _state = ConversationState.initial();

  /// Current conversational state.
  ConversationState get state => _state;

  /// The most recent tool or action execution, if any.
  ToolExecutionRecord? get lastToolExecution => _state.lastToolExecution;

  /// Alias for [lastToolExecution] to support action-oriented inquiries.
  ToolExecutionRecord? get lastAction => _state.lastToolExecution;

  /// Most recent successful tool execution in bounded history, if any.
  ToolExecutionRecord? get lastSuccessfulAction {
    for (final action in _recentActions) {
      if (action.success) return action;
    }
    return null;
  }

  /// Most recent failed tool execution in bounded history, if any.
  ToolExecutionRecord? get lastFailedAction {
    for (final action in _recentActions) {
      if (!action.success) return action;
    }
    return null;
  }

  /// Finds all recent executions for a specific tool name (e.g. 'image_generation', 'web_search').
  List<ToolExecutionRecord> findRecentExecutions(String toolName) {
    return _recentActions
        .where((a) => a.toolName.toLowerCase() == toolName.toLowerCase())
        .toList();
  }

  /// Returns all runtime evidence items gathered across recent tool executions.
  List<EvidenceItem> get recentEvidence {
    final allEvidence = <EvidenceItem>[];
    for (final action in _recentActions) {
      allEvidence.addAll(action.evidence);
    }
    return List.unmodifiable(allEvidence);
  }

  /// Finds evidence items relevant to a particular query substring or entity name.
  List<EvidenceItem> findEvidenceForQuery(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return const [];
    return recentEvidence.where((item) {
      final inSnippet = item.snippet.toLowerCase().contains(clean);
      final inTitle = item.title?.toLowerCase().contains(clean) ?? false;
      final inQuery = item.query?.toLowerCase().contains(clean) ?? false;
      return inSnippet || inTitle || inQuery;
    }).toList();
  }

  /// Unmodifiable list of recent tool execution records (most recent first).
  List<ToolExecutionRecord> get recentActions =>
      UnmodifiableListView(_recentActions);

  /// Records a completed tool or action execution.
  ///
  /// Automatically filters out any accidental keys or credentials and bounds summary lengths.
  void recordAction(ToolExecutionRecord record) {
    final sanitizedRecord = _sanitizeRecord(record);

    _recentActions.insert(0, sanitizedRecord);
    if (_recentActions.length > maxRecentActions) {
      _recentActions.removeRange(maxRecentActions, _recentActions.length);
    }

    _state = _state.copyWith(
      lastToolExecution: sanitizedRecord,
    );

    debugPrint(
      '[ActionLedger] Recorded action: ${sanitizedRecord.toolName} (success: ${sanitizedRecord.success}, query: "${sanitizedRecord.query}")',
    );

    notifyListeners();
  }

  /// Compatibility alias for [recordAction] ensuring unified ledger recording.
  void recordExecution({
    required String toolName,
    String? purpose,
    required String inputSummary,
    String? resultSummary,
    bool success = true,
    dynamic status,
    int? resultCount,
    List<String> sources = const [],
    String? error,
    Map<String, dynamic>? metadata,
  }) {
    final isSuccess = status != null
        ? (status.toString().contains('success') || status == true)
        : success;

    recordAction(
      ToolExecutionRecord(
        toolName: toolName,
        purpose: purpose,
        query: inputSummary,
        timestamp: DateTime.now(),
        success: isSuccess,
        resultCount: resultCount,
        sources: sources,
        summary: resultSummary,
        error: error,
        metadata: metadata,
      ),
    );
  }

  /// Updates conversational state attributes (e.g. topic, intent, entities, character, turnCount).
  void updateState({
    String? activeTopic,
    String? activeTask,
    String? lastUserIntent,
    String? lastAssistantClaim,
    Map<String, String>? activeEntities,
    bool? isFollowUp,
    int? turnCount,
    String? activeCharacterId,
  }) {
    _state = _state.copyWith(
      activeTopic: activeTopic,
      activeTask: activeTask,
      lastUserIntent: lastUserIntent,
      lastAssistantClaim: lastAssistantClaim,
      activeEntities: activeEntities != null
          ? Map.unmodifiable({..._state.activeEntities, ...activeEntities})
          : null,
      isFollowUp: isFollowUp,
      turnCount: turnCount,
      activeCharacterId: activeCharacterId,
    );
    notifyListeners();
  }

  /// Increments the active turn counter by 1.
  void incrementTurn({String? activeCharacterId}) {
    _state = _state.copyWith(
      turnCount: _state.turnCount + 1,
      activeCharacterId: activeCharacterId ?? _state.activeCharacterId,
    );
    notifyListeners();
  }

  /// Clears the active action ledger and resets conversation state to initial.
  void clear({String? activeCharacterId}) {
    _recentActions.clear();
    _state = ConversationState.initial(activeCharacterId: activeCharacterId);
    debugPrint('[ActionLedger] Cleared all actions and reset conversation state');
    notifyListeners();
  }

  /// Alias for [clear] to support standard provider reset workflows.
  void reset({String? activeCharacterId}) => clear(activeCharacterId: activeCharacterId);

  /// Sanitization check: strips tokens resembling API keys, headers, or data-URI payloads.
  ToolExecutionRecord _sanitizeRecord(ToolExecutionRecord record) {
    final safeQuery = _stripSecrets(record.query);
    final safeSummary = record.summary != null
        ? _stripSecrets(record.summary!)
        : null;
    final safeError = record.error != null
        ? _stripSecrets(record.error!)
        : null;

    final safeSources = record.sources
        .map((s) => _stripSecrets(s))
        .where((s) => s.isNotEmpty)
        .toList();

    // Sanitize and bound evidence items (max 10 items, max 300 chars snippet)
    final safeEvidence = record.evidence.take(10).map((e) {
      final cleanSnippet = _stripSecrets(e.snippet);
      final boundedSnippet = cleanSnippet.length > 300
          ? '${cleanSnippet.substring(0, 297)}...'
          : cleanSnippet;
      return EvidenceItem(
        sourceTool: _stripSecrets(e.sourceTool),
        title: e.title != null ? _stripSecrets(e.title!) : null,
        snippet: boundedSnippet,
        domain: e.domain != null ? _stripSecrets(e.domain!) : null,
        url: e.url != null ? _stripSecrets(e.url!) : null,
        query: e.query != null ? _stripSecrets(e.query!) : null,
        timestamp: e.timestamp,
        confidence: e.confidence,
        isVerifiedToolOutput: e.isVerifiedToolOutput,
      );
    }).toList();

    // Bound summary length to 1000 chars to avoid memory leaks or context bloating
    final boundedSummary = safeSummary != null && safeSummary.length > 1000
        ? '${safeSummary.substring(0, 997)}...'
        : safeSummary;

    // Sanitize metadata map
    final safeMetadata = record.metadata != null
        ? _sanitizeMetadata(record.metadata!)
        : null;

    return ToolExecutionRecord(
      toolName: record.toolName,
      purpose: record.purpose,
      query: safeQuery,
      timestamp: record.timestamp,
      success: record.success,
      resultCount: record.resultCount,
      sources: safeSources,
      evidence: safeEvidence,
      summary: boundedSummary,
      error: safeError,
      metadata: safeMetadata,
    );
  }

  /// Sanitizes and bounds metadata entries to prevent secret or heavy payload leakage.
  Map<String, dynamic> _sanitizeMetadata(Map<String, dynamic> raw) {
    final sanitized = <String, dynamic>{};
    // Limit to 10 keys maximum
    final entries = raw.entries.take(10);

    for (final entry in entries) {
      final key = entry.key;
      final val = entry.value;

      // Reject keys that hint at credentials
      final lowerKey = key.toLowerCase();
      if (lowerKey.contains('key') ||
          lowerKey.contains('secret') ||
          lowerKey.contains('token') ||
          lowerKey.contains('auth') ||
          lowerKey.contains('password')) {
        continue;
      }

      if (val is String) {
        // Strip secrets, data-uris, and bound string size to 500 chars
        final cleaned = _stripSecrets(val);
        sanitized[key] = cleaned.length > 500 ? '${cleaned.substring(0, 497)}...' : cleaned;
      } else if (val is num || val is bool) {
        sanitized[key] = val;
      } else {
        // Safe string fallback for complex objects
        final str = _stripSecrets(val.toString());
        sanitized[key] = str.length > 200 ? '${str.substring(0, 197)}...' : str;
      }
    }

    return Map.unmodifiable(sanitized);
  }

  /// Removes common secret patterns and large base64/data-URI strings.
  String _stripSecrets(String input) {
    if (input.isEmpty) return input;
    var sanitized = input;

    // Redact base64 Data URIs (e.g. data:image/png;base64,... or data:audio/... or data:application/...)
    sanitized = sanitized.replaceAll(
      RegExp(r'data:(?:image|audio|video|application)/[a-zA-Z0-9\+\-\.]+;base64,[A-Za-z0-9+/=]+', caseSensitive: false),
      '[DATA_URI_REDACTED]',
    );

    // Redact stand-alone long base64 strings (>100 consecutive base64 characters)
    sanitized = sanitized.replaceAll(
      RegExp(r'[A-Za-z0-9+/]{100,}={0,2}'),
      '[BASE64_PAYLOAD_REDACTED]',
    );

    // Redact Bearer tokens
    sanitized = sanitized.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9_\-\.]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );

    // Redact standard API key patterns (e.g. AIza..., sk-..., gsk_...)
    sanitized = sanitized.replaceAll(
      RegExp(r'\b(?:AIza[0-9A-Za-z-_]{35}|sk-[a-zA-Z0-9]{20,}|xai-[a-zA-Z0-9]{20,})\b'),
      '[API_KEY_REDACTED]',
    );

    // Redact password or secret query parameters
    sanitized = sanitized.replaceAll(
      RegExp(r'(?:key|token|secret|password|api_key)=[^&\s]+', caseSensitive: false),
      'key=[REDACTED]',
    );

    return sanitized;
  }
}
