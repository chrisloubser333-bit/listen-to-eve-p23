/// Represents a single piece of conversational or tool-derived evidence.
///
/// Designed for evidence-aware response grounding (Companion Core V1 Phase 3):
/// - Captures factual claims, source domains, URLs, and snippets from tools or user statements
/// - Strictly runtime/conversational (NOT persistent Hive memory)
/// - Never contains API keys, auth headers, or raw heavy HTML/web payloads
class EvidenceItem {
  /// Name or ID of the tool or input origin (e.g. 'web_search', 'weather_lookup', 'conversation_user').
  final String sourceTool;

  /// Optional headline, page title, or record title.
  final String? title;

  /// Concise factual statement or snippet supporting the evidence (max ~300 chars).
  final String snippet;

  /// Sanitized source domain or provider name (e.g. 'wikipedia.org', 'github.com', 'open-meteo.com').
  final String? domain;

  /// Cleaned public URL if available (query parameters with tokens/keys stripped).
  final String? url;

  /// Associated search query or parameter.
  final String? query;

  /// Timestamp when this evidence was captured.
  final DateTime timestamp;

  /// Confidence score between 0.0 and 1.0.
  final double confidence;

  /// Whether this evidence was directly returned by a verified tool execution.
  final bool isVerifiedToolOutput;

  const EvidenceItem({
    required this.sourceTool,
    this.title,
    required this.snippet,
    this.domain,
    this.url,
    this.query,
    required this.timestamp,
    this.confidence = 1.0,
    this.isVerifiedToolOutput = true,
  });

  Map<String, dynamic> toJson() => {
        'sourceTool': sourceTool,
        'title': title,
        'snippet': snippet,
        'domain': domain,
        'url': url,
        'query': query,
        'timestamp': timestamp.toIso8601String(),
        'confidence': confidence,
        'isVerifiedToolOutput': isVerifiedToolOutput,
      };

  factory EvidenceItem.fromJson(Map<String, dynamic> json) => EvidenceItem(
        sourceTool: json['sourceTool'] as String? ?? 'unknown',
        title: json['title'] as String?,
        snippet: json['snippet'] as String? ?? '',
        domain: json['domain'] as String?,
        url: json['url'] as String?,
        query: json['query'] as String?,
        timestamp: json['timestamp'] != null
            ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
            : DateTime.now(),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
        isVerifiedToolOutput: json['isVerifiedToolOutput'] as bool? ?? true,
      );

  @override
  String toString() =>
      'EvidenceItem(tool: $sourceTool, domain: $domain, title: "$title", confidence: $confidence)';
}
