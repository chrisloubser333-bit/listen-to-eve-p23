import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/evidence_item.dart';
import '../models/tool_result.dart';
import 'ai_tool.dart';

/// Status of the search transport attempt for diagnostics and error handling.
enum SearchTransportStatus {
  success,
  noResults,
  unconfigured,
  endpointUnavailable,
  invalidConfig,
  networkFailure,
  serverError,
}

/// Rich response wrapper for search operations.
class SearchResponse {
  final List<SearchResultItem> results;
  final SearchTransportStatus status;
  final String? errorMessage;
  final int? statusCode;

  const SearchResponse({
    required this.results,
    required this.status,
    this.errorMessage,
    this.statusCode,
  });

  bool get isSuccess => status == SearchTransportStatus.success && results.isNotEmpty;
}

/// A structured item returned by the web search engine.
class SearchResultItem {
  final String title;
  final String snippet;
  final String url;
  final String? source;
  final String? publishedDate;

  const SearchResultItem({
    required this.title,
    required this.snippet,
    required this.url,
    this.source,
    this.publishedDate,
  });

  factory SearchResultItem.fromJson(Map<String, dynamic> json) {
    return SearchResultItem(
      title: json['title'] as String? ?? '',
      snippet: json['snippet'] as String? ?? json['description'] as String? ?? '',
      url: json['url'] as String? ?? json['link'] as String? ?? '',
      source: json['source'] as String? ?? json['domain'] as String?,
      publishedDate: json['publishedDate'] as String? ?? json['date'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'snippet': snippet,
        'url': url,
        if (source != null) 'source': source,
        if (publishedDate != null) 'publishedDate': publishedDate,
      };
}

/// Transport interface for executing search requests across network boundaries.
abstract class SearchTransport {
  Future<List<SearchResultItem>> search(
    String query, {
    int maxResults = 4,
    String? language,
    String? region,
  });

  Future<SearchResponse> searchDetailed(
    String query, {
    int maxResults = 4,
    String? language,
    String? region,
  });
}

/// Production-grade HTTP transport that communicates with a secure search proxy backend.
///
/// Features:
/// - Distinguishes between Web, Android Emulator, and Physical Android APK
/// - Never silently attempts 10.0.2.2 in production / release builds on physical devices
/// - Supports runtime updates of the proxy endpoint
/// - Distinguishes network timeouts, unreachable servers, zero results, and server errors
class BackendProxySearchTransport implements SearchTransport {
  String? _configuredEndpoint;
  final Duration timeout;
  final http.Client _client;
  final String? authToken;

  BackendProxySearchTransport({
    String? proxyEndpoint,
    this.timeout = const Duration(seconds: 5),
    http.Client? client,
    this.authToken,
  })  : _configuredEndpoint = proxyEndpoint?.trim(),
        _client = client ?? http.Client();

  /// Updates the proxy endpoint at runtime (e.g. from Settings).
  void setProxyEndpoint(String? endpoint) {
    _configuredEndpoint = endpoint?.trim();
  }

  String? get configuredEndpoint => _configuredEndpoint;

  /// Effective proxy URI (compatibility getter for tests and diagnostic checks)
  Uri? get proxyUri => resolveTargetUri();

  /// Resolves the effective target URI based on runtime environment.
  Uri? resolveTargetUri() {
    final endpoint = _configuredEndpoint;
    
    // 1. Explicit Absolute URI provided (http:// or https://)
    if (endpoint != null && endpoint.isNotEmpty) {
      final parsed = _normalizeProxyUri(endpoint.trim());
      if (parsed != null) {
        return parsed;
      }
    }

    // 2. Check compile-time environment variable
    const envProxy = String.fromEnvironment('SEARCH_PROXY_ENDPOINT', defaultValue: '');
    if (envProxy.isNotEmpty) {
      final parsedEnv = _normalizeProxyUri(envProxy.trim());
      if (parsedEnv != null) {
        return parsedEnv;
      }
    }

    // 3. Web Platform: Relative /api/search resolves to current window origin
    if (kIsWeb) {
      return Uri.base.resolve('/api/search');
    }

    // 4. Android Emulator / Debug mode local fallback
    if (kDebugMode) {
      return Uri.parse('http://10.0.2.2:3000/api/search');
    }

    // 5. Physical Android Device in Release: No valid proxy configured
    return null;
  }

  /// Normalizes server endpoints to ensure `/api/search` is cleanly mounted.
  /// Handles:
  /// - `https://example.com` -> `https://example.com/api/search`
  /// - `https://example.com/` -> `https://example.com/api/search`
  /// - `https://example.com/api/search` -> `https://example.com/api/search`
  /// - `https://example.com/api/search/` -> `https://example.com/api/search`
  Uri? _normalizeProxyUri(String rawUrl) {
    var uri = Uri.tryParse(rawUrl);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return null;
    }

    if (uri.path.isEmpty || uri.path == '/') {
      uri = uri.replace(path: '/api/search');
    } else if (uri.path.endsWith('/')) {
      uri = uri.replace(path: uri.path.substring(0, uri.path.length - 1));
    }

    return uri;
  }

  @override
  Future<List<SearchResultItem>> search(
    String query, {
    int maxResults = 4,
    String? language,
    String? region,
  }) async {
    final response = await searchDetailed(
      query,
      maxResults: maxResults,
      language: language,
      region: region,
    );
    return response.results;
  }

  @override
  Future<SearchResponse> searchDetailed(
    String query, {
    int maxResults = 4,
    String? language,
    String? region,
  }) async {
    final targetUri = resolveTargetUri();
    
    if (targetUri == null) {
      debugPrint('[BackendProxySearchTransport] Search proxy is unconfigured on physical device. Falling back to open factual lookup.');
      return _tryOpenFallbackSearch(query, maxResults: maxResults);
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

      if (response.statusCode == 200) {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final rawResults =
              decoded['results'] ?? decoded['items'] ?? decoded['data'];
          if (rawResults is List) {
            final items = rawResults
                .whereType<Map<String, dynamic>>()
                .map((item) => SearchResultItem.fromJson(item))
                .where((item) => item.snippet.isNotEmpty)
                .take(maxResults)
                .toList();

            if (items.isEmpty) {
              return const SearchResponse(
                results: [],
                status: SearchTransportStatus.noResults,
              );
            }

            return SearchResponse(
              results: items,
              status: SearchTransportStatus.success,
              statusCode: 200,
            );
          }
        }
        return const SearchResponse(
          results: [],
          status: SearchTransportStatus.noResults,
          statusCode: 200,
        );
      } else if (response.statusCode >= 500) {
        debugPrint('[WebSearch] Server error ${response.statusCode} from $targetUri');
        return SearchResponse(
          results: [],
          status: SearchTransportStatus.serverError,
          statusCode: response.statusCode,
          errorMessage: 'Search server encountered an internal error (${response.statusCode})',
        );
      } else {
        debugPrint('[WebSearch] Proxy returned status ${response.statusCode}');
        return SearchResponse(
          results: [],
          status: SearchTransportStatus.endpointUnavailable,
          statusCode: response.statusCode,
          errorMessage: 'Proxy returned HTTP ${response.statusCode}',
        );
      }
    } on SocketException catch (se) {
      debugPrint('[WebSearch] SocketException connecting to $targetUri: $se');
      // If emulator proxy failed on physical device, attempt open fallback
      return _tryOpenFallbackSearch(query, maxResults: maxResults);
    } on TimeoutException {
      debugPrint('[WebSearch] Request to $targetUri timed out after ${timeout.inSeconds}s');
      return const SearchResponse(
        results: [],
        status: SearchTransportStatus.networkFailure,
        errorMessage: 'Search request timed out',
      );
    } catch (e) {
      debugPrint('[WebSearch] Transport error: $e');
      return _tryOpenFallbackSearch(query, maxResults: maxResults);
    }
  }

  /// Open HTTPS knowledge fallback (DuckDuckGo / Wikipedia summary) when custom proxy is unconfigured.
  Future<SearchResponse> _tryOpenFallbackSearch(String query, {int maxResults = 4}) async {
    try {
      final wikiUri = Uri.parse(
        'https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeComponent(query)}&utf8=&format=json&srlimit=$maxResults',
      );
      final wikiRes = await _client.get(wikiUri).timeout(const Duration(seconds: 4));
      if (wikiRes.statusCode == 200) {
        final data = jsonDecode(wikiRes.body) as Map<String, dynamic>;
        final queryObj = data['query'] as Map<String, dynamic>?;
        final searchItems = queryObj?['search'] as List?;
        if (searchItems != null && searchItems.isNotEmpty) {
          final results = <SearchResultItem>[];
          for (final item in searchItems) {
            if (item is Map<String, dynamic>) {
              final title = item['title'] as String? ?? '';
              final rawSnippet = item['snippet'] as String? ?? '';
              final cleanSnippet = rawSnippet
                  .replaceAll(RegExp(r'<[^>]*>'), '')
                  .replaceAll('&quot;', '"')
                  .replaceAll('&amp;', '&');
              if (cleanSnippet.isNotEmpty) {
                results.add(SearchResultItem(
                  title: title,
                  snippet: cleanSnippet,
                  url: 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}',
                  source: 'wikipedia.org',
                ));
              }
            }
          }
          if (results.isNotEmpty) {
            return SearchResponse(
              results: results,
              status: SearchTransportStatus.success,
              statusCode: 200,
            );
          }
        }
      }
    } catch (err) {
      debugPrint('[WebSearch] Open fallback lookup error: $err');
    }

    return const SearchResponse(
      results: [],
      status: SearchTransportStatus.unconfigured,
      errorMessage: 'Search proxy unconfigured and open fallback returned no matches.',
    );
  }
}

/// A provider-independent web search tool for Listen to Eve.
///
/// Implements [AiTool] to supply fresh real-world knowledge to whatever
/// [AiService] provider is currently active (Gemini, xAI, etc.).
class WebSearchTool implements AiTool {
  final BackendProxySearchTransport _transport;
  final int defaultMaxResults;

  WebSearchTool({
    BackendProxySearchTransport? transport,
    this.defaultMaxResults = 4,
  }) : _transport = transport ?? BackendProxySearchTransport();

  BackendProxySearchTransport get transport => _transport;

  void updateProxyEndpoint(String? endpoint) {
    _transport.setProxyEndpoint(endpoint);
  }

  @override
  String get id => 'web_search';

  @override
  String get name => 'Web Search';

  @override
  String get description =>
      'Retrieves current real-world facts, news, live prices, sports, and external knowledge.';

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
      'what interesting facts can you find',
      'what facts can you find',
      'what can you find about',
      'can you find about',
      'can you find out about',
      'find about',
      'facts can you find',
      'what can you find',
      'interesting facts about',
      'facts about',
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
      'wat kan jy vind oor',
      'wat kan jy oor',
      'watse feite kan jy vind',
      'kan jy iets vind oor',
      'kan jy iets kry oor',
      'wat kan jy vind',
      'feite oor',
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
    // If the query explicitly asks to find / search for facts or information,
    // it should not be blocked from web search as a purely internal memory query.
    final isFindingOrSearching = lower.contains('find') ||
        lower.contains('search') ||
        lower.contains('look up') ||
        lower.contains('check online') ||
        lower.contains('online') ||
        lower.contains('aanlyn') ||
        lower.contains('vind') ||
        lower.contains('soek') ||
        lower.contains('feite') ||
        lower.contains('facts');

    if (isFindingOrSearching) {
      const pureMemoryPhrases = [
        'do you remember',
        'what do you remember',
        'what did i tell you',
        'what did i say',
        'onthou jy',
        'wat onthou jy',
        'wat het ek gesê',
      ];
      for (final pmp in pureMemoryPhrases) {
        if (lower.contains(pmp)) return true;
      }
      return false;
    }

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

    if (lower.startsWith('how are you') ||
        lower.startsWith('hoe gaan dit') ||
        lower.startsWith('i feel ') ||
        lower.startsWith('ek voel ') ||
        (lower.startsWith('i am ') && lower.length < 30 && !lower.contains('find') && !lower.contains('search')) ||
        (lower.startsWith('ek is ') && lower.length < 30 && !lower.contains('vind') && !lower.contains('soek'))) {
      return true;
    }

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
      final regex = RegExp('\\b${RegExp.escape(tw)}\\b');
      if (regex.hasMatch(lower)) return true;
    }

    return false;
  }

  bool _isInherentlyCurrentTopic(String lower) {
    const volatileKeywords = [
      'weather',
      'forecast',
      'temperature',
      'how is the weather',
      'stock price',
      'crypto price',
      'bitcoin price',
      'exchange rate',
      'who won the game',
      'match score',
      'sports standings',
      'traffic conditions',
      'current president',
      'current prime minister',
      // Afrikaans
      'weer',
      'weervoorspelling',
      'temperatuur',
      'huidige prys',
      'wisselkoers',
      'aandeleprys',
      'wie het gewen',
      'huidige president',
      'huidige premier',
    ];

    for (final vk in volatileKeywords) {
      if (lower.contains(vk)) return true;
    }

    return false;
  }

  String cleanQuery(String rawMessage, {String? fallbackTarget}) {
    var query = rawMessage.trim();

    // 1. If searching for facts about the user ("about me", "oor my", "about myself"),
    // extract user name from this message or use fallbackTarget (e.g. from memory)
    final lower = query.toLowerCase();
    if (lower.contains('about me') ||
        lower.contains('oor my') ||
        lower.contains('about myself') ||
        lower.contains('oor myself')) {
      final introMatch = RegExp(
        r"\b(?:i\s+am|i'm|my\s+name\s+is|my\s+naam\s+is|ek\s+is)\s+([A-Za-z]+(?:\s+[A-Za-z]+)*)",
        caseSensitive: false,
      ).firstMatch(query);

      if (introMatch != null) {
        final rawName = introMatch.group(1)!.trim().replaceAll(RegExp(r'[^\w\s]'), '');
        final parts = rawName.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        const stopWords = {
          'and', 'but', 'what', 'who', 'how', 'why', 'can', 'could', 'en', 'maar', 'wat', 'kan'
        };
        final nameParts = <String>[];
        for (final p in parts) {
          if (stopWords.contains(p.toLowerCase())) break;
          nameParts.add(p);
        }
        if (nameParts.isNotEmpty) {
          return nameParts.join(' ');
        }
      }

      if (fallbackTarget != null && fallbackTarget.trim().isNotEmpty) {
        return fallbackTarget.trim();
      }
    }

    final stripPatterns = [
      RegExp(r'^(?:what\s+)?(?:interesting\s+)?facts\s+can\s+you\s+find\s+(?:about|on)?\s*',
          caseSensitive: false),
      RegExp(r'^(?:can\s+you\s+)?(?:please\s+)?find\s+(?:me\s+)?(?:the\s+latest\s+)?(?:interesting\s+)?(?:facts\s+about|information\s+about|about)?\s*',
          caseSensitive: false),
      RegExp(r'^(?:can\s+you\s+)?(?:please\s+)?search\s+(?:the\s+web\s+for|online\s+for|for)?\s*',
          caseSensitive: false),
      RegExp(r'^(?:can\s+you\s+)?(?:please\s+)?look\s+up\s*', caseSensitive: false),
      RegExp(r'^(?:can\s+you\s+)?check\s+online\s+(?:for\s+)?', caseSensitive: false),
      RegExp(r'^(?:wat\s+(?:se\s+)?(?:interessante\s+)?feite\s+kan\s+jy\s+vind\s+(?:oor)?\s*)',
          caseSensitive: false),
      RegExp(r'^(?:kan\s+jy\s+)?(?:asseblief\s+)?vind\s+(?:vir\s+my\s+)?(?:die\s+nuutste\s+)?(?:feite\s+oor|inligting\s+oor|oor)?\s*',
          caseSensitive: false),
      RegExp(r'^(?:kan\s+jy\s+)?(?:asseblief\s+)?soek\s+(?:op\s+die\s+(?:web|internet)\s+vir|aanlyn\s+vir|vir)?\s*',
          caseSensitive: false),
      RegExp(r'^(?:kan\s+jy\s+)?(?:asseblief\s+)?kyk\s+op\s+(?:vir\s+)?',
          caseSensitive: false),
      RegExp(r'^(?:wat\s+kan\s+jy\s+(?:oor\s+my\s+)?vind\s*(?:oor)?\s*)',
          caseSensitive: false),
    ];

    for (final pattern in stripPatterns) {
      if (pattern.hasMatch(query)) {
        query = query.replaceFirst(pattern, '').trim();
        break;
      }
    }

    query = query.replaceAll(RegExp(r'[\?\.!]+$'), '').trim();

    return query.isNotEmpty ? query : rawMessage.trim();
  }

  @override
  Future<ToolResult?> execute(
    String userMessage, {
    Map<String, dynamic>? parameters,
  }) async {
    final userName = parameters?['userName'] as String?;
    final query = cleanQuery(userMessage, fallbackTarget: userName);
    if (query.isEmpty) return null;

    final maxResults = (parameters?['maxResults'] as int?) ?? defaultMaxResults;
    final language = parameters?['language'] as String?;
    final region = parameters?['region'] as String?;

    try {
      debugPrint('[WebSearchTool] Executing search for cleaned query: "$query"');

      final response = await _transport.searchDetailed(
        query,
        maxResults: maxResults,
        language: language,
        region: region,
      );

      if (!response.isSuccess || response.results.isEmpty) {
        debugPrint('[WebSearchTool] Search completed with status ${response.status}: ${response.errorMessage ?? "No results"}');
        return null;
      }

      final results = response.results;
      final buffer = StringBuffer();
      final sources = <String>[];
      final evidenceItems = <EvidenceItem>[];
      for (var i = 0; i < results.length; i++) {
        final item = results[i];
        final domain = item.source ??
            (Uri.tryParse(item.url)?.host.replaceFirst(RegExp(r'^www\.'), '') ??
                '');
        final domainTag = domain.isNotEmpty ? ' ($domain)' : '';
        if (domain.isNotEmpty && !sources.contains(domain)) {
          sources.add(domain);
        } else if (item.url.isNotEmpty && !sources.contains(item.url)) {
          sources.add(item.url);
        }

        final cleanSnippet = item.snippet.trim();
        evidenceItems.add(EvidenceItem(
          sourceTool: id,
          title: item.title.isNotEmpty ? item.title.trim() : null,
          snippet: cleanSnippet.length > 300
              ? '${cleanSnippet.substring(0, 297)}...'
              : cleanSnippet,
          domain: domain.isNotEmpty ? domain : null,
          url: item.url.isNotEmpty ? item.url : null,
          query: query,
          timestamp: DateTime.now(),
          confidence: 0.9,
          isVerifiedToolOutput: true,
        ));

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
          'transportStatus': response.status.name,
          'sources': sources,
          'evidence': evidenceItems.map((e) => e.toJson()).toList(),
        },
      );
    } catch (e, stack) {
      debugPrint('[WebSearchTool] Execution failed: $e');
      debugPrint(stack.toString());
      return null;
    }
  }
}
