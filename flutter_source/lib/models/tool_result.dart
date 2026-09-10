/// Structured representation of external knowledge or tool execution results.
///
/// Designed to provide a provider-independent context boundary for Listen to Eve:
/// - Separates temporary external knowledge from persistent user memory
/// - Never pollutes the visible user chat history
/// - Formats results naturally for character personas without exposing internal tool mechanics
class ToolResult {
  /// Unique identifier of the tool (e.g. 'web_search', 'knowledge_lookup').
  final String toolId;

  /// Brief human-readable title or query description.
  final String title;

  /// Bounded text snippet containing the verified facts or retrieved content.
  final String snippet;

  /// Optional source URL or reference link.
  final String? url;

  /// Timestamp when this knowledge was retrieved.
  final DateTime retrievedAt;

  /// Optional confidence score between 0.0 and 1.0.
  final double? confidence;

  /// Optional tool-specific metadata (e.g. source domain, query time).
  final Map<String, dynamic> metadata;

  const ToolResult({
    required this.toolId,
    required this.title,
    required this.snippet,
    this.url,
    required this.retrievedAt,
    this.confidence,
    this.metadata = const {},
  });

  /// Formats this tool result into a natural, character-friendly context block.
  ///
  /// Guarantees:
  /// 1. Clearly distinguished as external verified information
  /// 2. Instructs the character to synthesize naturally without robotic tool jargon
  /// 3. Instructs the character not to recite raw URLs unless explicitly asked
  String formatForPrompt({String language = 'en'}) {
    final isAf = language == 'af';
    final cleanSnippet = snippet.trim();
    final sourceRef = (url != null && url!.isNotEmpty) ? ' ($url)' : '';

    if (isAf) {
      return '''
[GELYSVERIFIEERDE EKSTERNE KENNIS EN INLIGTING]
Bron/Onderwerp: $title$sourceRef
Tydstip: ${retrievedAt.toIso8601String()}
Inligting:
$cleanSnippet

Riglyn vir gespreksgenoot:
- Hierdie is vars, geverifieerde eksterne feite om jou te help om die gebruiker se vraag akkuraat te beantwoord.
- Verweef hierdie inligting natuurlik en menslik in jou antwoord soos jy dit self weet.
- Moenie interne tegniese gereedskap, soekmeganismes of URL's noem nie, tensy die gebruiker uitdruklik vir 'n skakel of bron vra.
''';
    } else {
      return '''
[VERIFIED EXTERNAL KNOWLEDGE]
Source/Subject: $title$sourceRef
Timestamp: ${retrievedAt.toIso8601String()}
Information:
$cleanSnippet

Guideline for companion:
- This is verified external information to help you answer the user's inquiry accurately.
- Incorporate these facts naturally and conversationally into your response.
- Do not expose internal tool mechanics, search APIs, or raw URLs unless the user explicitly requests a link or citation.
''';
    }
  }

  Map<String, dynamic> toJson() => {
        'toolId': toolId,
        'title': title,
        'snippet': snippet,
        'url': url,
        'retrievedAt': retrievedAt.toIso8601String(),
        'confidence': confidence,
        'metadata': metadata,
      };

  factory ToolResult.fromJson(Map<String, dynamic> json) => ToolResult(
        toolId: json['toolId'] as String? ?? 'unknown_tool',
        title: json['title'] as String? ?? '',
        snippet: json['snippet'] as String? ?? '',
        url: json['url'] as String?,
        retrievedAt: json['retrievedAt'] != null
            ? DateTime.tryParse(json['retrievedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        confidence: (json['confidence'] as num?)?.toDouble(),
        metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
      );
}
