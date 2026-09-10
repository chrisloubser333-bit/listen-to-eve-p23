import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/tool_result.dart';
import 'ai_tool.dart';

/// Normalized search result item returned by a [SearchTransport].
class SearchResultItem {
  final String title;
  final String snippet;
  final String url;
  final String? source;
  final DateTime? publishedDate;

  const SearchResultItem({
    required this.title,
    required this.snippet,
    required this.url,
    this.source,
    this.publishedDate,
  });

  factory SearchResultItem.fromJson(Map<String, dynamic> json) {
    return SearchResultItem(
      title: (json['title'] as String? ?? '').trim(),
      snippet: (json['snippet'] as String? ??
              json['description'] as String? ??
              json['content'] as String? ??
              '')
          .trim(),
      url: (json['url'] as String? ?? json['link'] as String? ?? '').trim(),
      source: (json['source'] as String? ?? json['domain'] as String?)?.trim(),
      publishedDate: json['publishedDate'] != null
          ? DateTime.tryParse(json['publishedDate'] as String)
          : null,
    );
  }
}

/// Abstract transport contract for executing web searches.
///
/// Ensures [WebSearchTool] is strictly decoupled from specific network
/// protocols, search APIs, or backend hosting choices.
///
/// In production, concrete implementations should delegate through a secure
/// proxy backend so private search engine API keys never reside on the mobile client.
abstract class SearchTransport {
  Future<List<SearchResultItem>> search(
    String query, {
    int maxResults = 4,
    String? language,
    String? region,
  });
}

/// Concrete HTTP transport that communicates with a secure search proxy backend.
///
/// Endpoint Contract:
/// - Method: POST (or GET with query parameter)
/// - Headers: Content-Type: application/json, (optional Authorization: Bearer <token>)
/// - Request Body (JSON):
///   ```json
///   {
///     "query": "latest SpaceX launch",
///     "maxResults": 4,
///     "language": "en",
///     "region": "us"
///   }
///   ```
/// - Expected Response Body (JSON):
///   ```json
///   {
///     "results": [
///       {
///         "title": "SpaceX Launches Starship Flight 6",
///         "snippet": "SpaceX successfully launched Starship from Starbase, Texas...",
///         "url": "https://example.com/spacex-flight-6",
///         "source": "example.com",
///         "publishedDate": "2026-09-08T18:00:00Z"
///       }
///     ]
///   }
///   ```
class BackendProxySearchTransport implements SearchTransport {
  final Uri? proxyUri;
  final Duration timeout;
  final http.Client _client;
  final String? authToken;

  BackendProxySearchTransport({
    String? proxyEndpoint,
    this.timeout = const Duration(seconds: 5),
    http.Client? client,
    this.authToken,
  })  : proxyUri = (proxyEndpoint != null && proxyEndpoint.trim().isNotEmpty)
            ? Uri.tryParse(proxyEndpoint.trim())
            : Uri.parse('/api/search'),
        _client = client ?? http.Client();

  @override
  Future<List<SearchResultItem>> search(
    String query, {
    int maxResults = 4,
    String? language,
    String? region,
  }) async {
    Uri? targetUri = proxyUri;
    if (targetUri == null) {
      // Safe fallback when no backend proxy endpoint is configured.
      return const [];
    }

    // If endpoint is relative (e.g. /api/search), resolve scheme & host safely
    if (!targetUri.hasScheme) {
      if (kIsWeb) {
        targetUri = Uri.base.resolveUri(targetUri);
      } else {
        targetUri = Uri.parse('http://10.0.2.2:3000').resolveUri(targetUri);
      }
    }

    try {
      final payload = <String, dynamic>{
        'query': query,
        'maxResults': maxResults,
        if (language != null && language.isNotEmpty) 'language': language,
        if (region != null && region.isNotEmpty) 'region': region,
      };

      final response = await _client
          .post(
            targetUri,
            headers: {
              'Content-Type': 'application/json',
              if (authToken != null && authToken!.isNotEmpty)
                'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode(payload),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        debugPrint('[WebSearch] Proxy returned status ${response.statusCode}');
        return const [];
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final rawResults =
            decoded['results'] ?? decoded['items'] ?? decoded['data'];
        if (rawResults is List) {
          return rawResults
              .whereType<Map<String, dynamic>>()
              .map((item) => SearchResultItem.fromJson(item))
              .where((item) => item.snippet.isNotEmpty)
              .take(maxResults)
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[WebSearch] Search transport error: $e');
    }

    return const [];
  }
}

/// A provider-independent web search tool for Listen to Eve.
///
/// Implements [AiTool] to supply fresh real-world knowledge to whatever
/// [AiService] provider is currently active (Gemini, xAI, etc.).
class WebSearchTool implements AiTool {
  final SearchTransport _transport;
  final int defaultMaxResults;

  WebSearchTool({
    SearchTransport? transport,
    this.defaultMaxResults = 4,
  }) : _transport = transport ?? BackendProxySearchTransport();

  @override
  String get id => 'web_search';

  @override
  String get name => 'Web Search';

  @override
  String get description =>
      'Retrieves current real-world facts, news, live prices, weather, and external knowledge.';

  // ---------------------------------------------------------------------------
  // Trigger Logic (Conservative, Intent-Driven, Bilingual EN/AF)
  // ---------------------------------------------------------------------------

  @override
  bool shouldTrigger(
    String userMessage, {
    List<Map<String, String>>? conversationHistory,
  }) {
    final lower = userMessage.trim().toLowerCase();
    if (lower.isEmpty) return false;

    // 1. Never search for explicit memory queries or personal background
    if (_isMemoryQuery(lower)) return false;

    // 2. High priority: Explicit search requests by the user
    if (_isExplicitSearch(lower)) return true;

    // 3. Never search for casual greetings, personal feelings, or creative requests
    if (_isCasualOrCreative(lower)) return false;

    // 4. Trigger for volatile, real-time factual domains combined with temporal markers
    if (_hasCurrentTemporalIndicator(lower)) return true;

    // 5. Trigger for topics that inherently require real-time lookup
    if (_isInherentlyCurrentTopic(lower)) return true;

    return false;
  }

  /// Detects explicit user instructions to search or lookup information online.
  bool _isExplicitSearch(String lower) {
    const explicitPrefixes = [
      'search for',
      'search the web for',
      'search online for',
      'look up',
      'look this up',
      'look that up',
      'find the latest',
      'find me the latest',
      'can you check online',
      'check online for',
      'google',
      'browse the web for',
      // Afrikaans
      'soek vir',
      'soek op die web',
      'soek op die internet',
      'soek aanlyn vir',
      'soek aanlyn',
      'kyk op',
      'vind die nuutste',
      'kan jy aanlyn naslaan',
      'kan jy dit aanlyn naslaan',
      'naslaan',
      'gaan kyk aanlyn vir',
      'gaan kyk aanlyn',
    ];

    for (final prefix in explicitPrefixes) {
      if (lower.startsWith(prefix) || lower.contains(' $prefix ')) {
        return true;
      }
    }

    return false;
  }

  /// Detects memory recall or user personal preference requests.
  bool _isMemoryQuery(String lower) {
    const memoryKeywords = [
      'do you remember',
      'what do you remember',
      'what did i tell you',
      'what did i say',
      'my favorite',
      'my preference',
      'remember that',
      'don\'t forget',
      'do not forget',
      'about me',
      'who am i',
      // Afrikaans
      'onthou jy',
      'wat onthou jy',
      'wat het ek gesê',
      'onthou dat',
      'moenie vergeet nie',
      'oor my',
      'wie is ek',
      'my gunsteling',
    ];

    for (final kw in memoryKeywords) {
      if (lower.contains(kw)) return true;
    }

    return false;
  }

  /// Detects conversational filler, greetings, emotional statements, or creative prompts.
  bool _isCasualOrCreative(String lower) {
    // Exact short greetings
    const greetings = [
      'hi',
      'hello',
      'hey',
      'hallo',
      'goeiemôre',
      'goeie môre',
      'goeienaand',
      'goeie naand',
      'good morning',
      'good afternoon',
      'good evening',
      'how are you',
      'hoe gaan dit',
      'what\'s up',
      'sup',
      'thanks',
      'thank you',
      'dankie',
      'cool',
      'great',
      'awesome',
      'lekker',
      'okay',
      'ok',
      'yes',
      'no',
      'ja',
      'nee',
    ];

    if (greetings.contains(lower)) return true;

    // Common conversational reactions
    if (lower.startsWith('how are you') ||
        lower.startsWith('hoe gaan dit') ||
        lower.startsWith('i feel ') ||
        lower.startsWith('ek voel ') ||
        lower.startsWith('i am ') ||
        lower.startsWith('ek is ') && lower.length < 30) {
      // Unless it explicitly contains a search command
      return true;
    }

    // Creative writing requests without current events
    const creativePrefixes = [
      'write a poem',
      'write me a poem',
      'tell me a joke',
      'tell a joke',
      'help me write',
      'brainstorm with me',
      'skryf \'n gedig',
      'skryf vir my \'n gedig',
      'vertel \'n grappie',
      'vertel my \'n grappie',
      'help my dink aan',
    ];

    for (final cp in creativePrefixes) {
      if (lower.startsWith(cp)) return true;
    }

    // Stable timeless factual/scientific definitions (no temporal indicator)
    const stableQuestionStarts = [
      'what is photosynthesis',
      'what is quantum computing',
      'explain photosynthesis',
      'explain quantum computing',
      'who wrote romeo and juliet',
      'what is the speed of light',
      'how does gravity work',
      'wat is fotosintese',
      'wie het romeo en juliet geskryf',
      'hoe werk swaartekrag',
    ];

    for (final sq in stableQuestionStarts) {
      if (lower.contains(sq)) return true;
    }

    return false;
  }

  /// Detects temporal indicators indicating a need for fresh or real-time information.
  bool _hasCurrentTemporalIndicator(String lower) {
    const temporalWords = [
      'today',
      'tonight',
      'currently',
      'current',
      'latest',
      'recent',
      'recently',
      'this week',
      'this month',
      'right now',
      'as of now',
      'newest',
      'updated',
      'breaking news',
      // Afrikaans
      'vandag',
      'vanaand',
      'tans',
      'huidige',
      'nuutste',
      'onlangs',
      'hierdie week',
      'hierdie maand',
      'nou',
      'opgedateer',
      'brekende nuus',
    ];

    for (final tw in temporalWords) {
      // Match word boundaries to prevent false positives inside other words
      final regex = RegExp('\\b${RegExp.escape(tw)}\\b');
      if (regex.hasMatch(lower)) return true;
    }

    return false;
  }

  /// Topics that inherently represent live, rapidly changing real-world data.
  bool _isInherentlyCurrentTopic(String lower) {
    const volatileKeywords = [
      'weather',
      'temperature',
      'forecast',
      'stock price',
      'crypto price',
      'bitcoin price',
      'exchange rate',
      'who won the game',
      'match score',
      'sports standings',
      'traffic conditions',
      'closing time',
      'opening hours',
      'current president',
      'current prime minister',
      // Afrikaans
      'weervoorspelling',
      'huidige prys',
      'wisselkoers',
      'aandeleprys',
      'wie het gewen',
      'openingstye',
      'sluitingstyd',
      'huidige president',
      'huidige premier',
    ];

    for (final vk in volatileKeywords) {
      if (lower.contains(vk)) return true;
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Query Sanitization & Execution
  // ---------------------------------------------------------------------------

  /// Extracts a clean search query from the conversational text.
  ///
  /// Strips conversational padding such as "Please search the web for..."
  /// to focus purely on the core subject matter for the external search engine.
  String cleanQuery(String rawMessage) {
    var query = rawMessage.trim();

    final stripPatterns = [
      RegExp(r'^(?:can\s+you\s+)?(?:please\s+)?search\s+(?:the\s+web\s+for|online\s+for|for)?\s*',
          caseSensitive: false),
      RegExp(r'^(?:can\s+you\s+)?(?:please\s+)?look\s+up\s*', caseSensitive: false),
      RegExp(r'^(?:can\s+you\s+)?(?:please\s+)?find\s+(?:me\s+)?(?:the\s+latest\s+)?',
          caseSensitive: false),
      RegExp(r'^(?:can\s+you\s+)?check\s+online\s+(?:for\s+)?', caseSensitive: false),
      // Afrikaans
      RegExp(r'^(?:kan\s+jy\s+)?(?:asseblief\s+)?soek\s+(?:op\s+die\s+(?:web|internet)\s+vir|aanlyn\s+vir|vir)?\s*',
          caseSensitive: false),
      RegExp(r'^(?:kan\s+jy\s+)?(?:asseblief\s+)?kyk\s+op\s+(?:vir\s+)?',
          caseSensitive: false),
      RegExp(r'^(?:kan\s+jy\s+)?vind\s+(?:vir\s+my\s+)?(?:die\s+nuutste\s+)?',
          caseSensitive: false),
    ];

    for (final pattern in stripPatterns) {
      if (pattern.hasMatch(query)) {
        query = query.replaceFirst(pattern, '').trim();
        break;
      }
    }

    // Remove trailing question marks or punctuation
    query = query.replaceAll(RegExp(r'[\?\.!]+$'), '').trim();

    return query.isNotEmpty ? query : rawMessage.trim();
  }

  @override
  Future<ToolResult?> execute(
    String userMessage, {
    Map<String, dynamic>? parameters,
  }) async {
    final query = cleanQuery(userMessage);
    if (query.isEmpty) return null;

    final maxResults = (parameters?['maxResults'] as int?) ?? defaultMaxResults;
    final language = parameters?['language'] as String?;
    final region = parameters?['region'] as String?;

    try {
      debugPrint('[WebSearchTool] Executing search for cleaned query: "$query"');

      final results = await _transport.search(
        query,
        maxResults: maxResults,
        language: language,
        region: region,
      );

      if (results.isEmpty) {
        debugPrint('[WebSearchTool] No results returned for query: "$query"');
        return null;
      }

      // Compact factual bundle formatting
      final buffer = StringBuffer();
      for (var i = 0; i < results.length; i++) {
        final item = results[i];
        final domain = item.source ??
            (Uri.tryParse(item.url)?.host.replaceFirst(RegExp(r'^www\.'), '') ??
                '');
        final domainTag = domain.isNotEmpty ? ' ($domain)' : '';

        buffer.writeln('${i + 1}. ${item.title}$domainTag');
        buffer.writeln('   ${item.snippet}');
        if (i < results.length - 1) {
          buffer.writeln();
        }
      }

      final primaryUrl =
          results.first.url.isNotEmpty ? results.first.url : null;

      return ToolResult(
        toolId: id,
        title: query,
        snippet: buffer.toString().trim(),
        url: primaryUrl,
        retrievedAt: DateTime.now(),
        confidence: 0.9,
        metadata: {
          'resultCount': results.length,
          'cleanedQuery': query,
        },
      );
    } catch (e, stack) {
      debugPrint('[WebSearchTool] Execution failed: $e');
      debugPrint(stack.toString());
      // Graceful error degradation: conversation proceeds without external snippet
      return null;
    }
  }
}
