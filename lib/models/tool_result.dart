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

  /// Convenience getters for execution and summary checks.
  bool get wasExecuted => snippet.trim().isNotEmpty;
  String get resultSummary => snippet.trim();

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
- Hierdie is vars, geverifieerde eksterne inligting om jou te help om die gebruiker se vraag akkuraat te beantwoord.
- Verweef hierdie feite natuurlik, warm en bondig (2 tot 5 sinne) in jou antwoord sonder om roboties te klink.
- Moenie interne gereedskap, soekmeganismes of URL's noem nie, tensy uitdruklik gevra.
- KRITIESE RIGLYN VIR PERSOONLIKE ONDERSOEK:
  1) Onderskei duidelik tussen:
     (a) Wat die gebruiker self vir jou in die gesprek of geheue gesê het.
     (b) Openbare webinligting wat oor die naam gevind is.
     (c) Moenie aanneem dat openbare webgegewens oor 'n naam outomaties aan die gebruiker behoort sonder hul bevestiging nie.
  2) Moet nooit ongeverifieerde persoonlike feite versin nie.
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
- Incorporate these facts naturally, warmly, and concisely (typically 2 to 5 sentences) into your response.
- Do not expose internal tool mechanics, search APIs, or raw URLs unless the user explicitly requests a citation.
- CRITICAL GUIDELINE FOR PERSON / IDENTITY RESEARCH:
  1) Clearly distinguish between:
     (a) What the user personally told you in conversation / memory.
     (b) Publicly available web information found online for that name.
     (c) Explicitly state that public web records for a name cannot be automatically assumed to belong to the user without verification.
  2) Never invent, assume, or hallucinate unverified personal facts.
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
