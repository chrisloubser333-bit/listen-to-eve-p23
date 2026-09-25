import 'evidence_item.dart';

/// Status of a tool or action execution.
enum ToolExecutionStatus {
  success,
  failure,
}

/// Structured representation of a tool or action execution during active conversation.
///
/// Designed for conversational intelligence continuity:
/// - Records what tool was run, for what purpose, with what query, and whether it succeeded
/// - Captures source domains / URLs, structured evidence items, and result counts without storing heavy payloads
/// - NEVER stores API keys, authentication headers, or sensitive secrets
/// - Independent of Hive personal memory (lives only in active conversational state)
class ToolExecutionRecord {
  /// Name or ID of the tool executed (e.g. 'web_search', 'weather_lookup', 'image_generation').
  final String toolName;

  /// Conversational purpose or intent category (e.g. 'self_research', 'fact_lookup', 'weather_request').
  final String? purpose;

  /// The cleaned input query or target parameter sent to the tool (e.g. 'Chris Loubser', 'Cape Town').
  final String query;

  /// Exact timestamp when the action finished execution.
  final DateTime timestamp;

  /// Whether the tool action succeeded in producing valid, verified results.
  final bool success;

  /// Number of result items, records, or entities returned (if applicable).
  final int? resultCount;

  /// Sanitized list of source domains, titles, or URLs (no sensitive parameters).
  final List<String> sources;

  /// Structured runtime evidence items supporting the findings (Companion Core V1 Phase 3).
  final List<EvidenceItem> evidence;

  /// Bounded human-readable summary of what was found or produced (max ~500 chars).
  final String? summary;

  /// Sanitized error or failure message if the action failed (never contains secrets).
  final String? error;

  /// Sanitized, bounded metadata (e.g. prompt, targetCharacterId, status).
  final Map<String, dynamic>? metadata;

  const ToolExecutionRecord({
    required this.toolName,
    this.purpose,
    required this.query,
    required this.timestamp,
    required this.success,
    this.resultCount,
    this.sources = const [],
    this.evidence = const [],
    this.summary,
    this.error,
    this.metadata,
  });

  /// Sanitized JSON representation for diagnostic logging or state inspection.
  Map<String, dynamic> toJson() => {
        'toolName': toolName,
        'purpose': purpose,
        'query': query,
        'timestamp': timestamp.toIso8601String(),
        'success': success,
        'resultCount': resultCount,
        'sources': sources,
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'summary': summary,
        'error': error,
        if (metadata != null) 'metadata': metadata,
      };

  factory ToolExecutionRecord.fromJson(Map<String, dynamic> json) =>
      ToolExecutionRecord(
        toolName: json['toolName'] as String? ?? 'unknown_tool',
        purpose: json['purpose'] as String?,
        query: json['query'] as String? ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
            : DateTime.now(),
        success: json['success'] as bool? ?? false,
        resultCount: json['resultCount'] as int?,
        sources: (json['sources'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        evidence: (json['evidence'] as List<dynamic>?)
                ?.map((e) => EvidenceItem.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        summary: json['summary'] as String?,
        error: json['error'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
      );

  @override
  String toString() =>
      'ToolExecutionRecord(tool: $toolName, purpose: $purpose, query: "$query", success: $success, results: $resultCount, evidence: ${evidence.length})';
}
