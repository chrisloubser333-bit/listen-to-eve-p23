import 'package:flutter/foundation.dart';
import '../models/evidence_item.dart';
import '../models/resolved_conversation_context.dart';
import '../models/tool_execution_record.dart';

/// Result produced by [ResponseVerificationService].
class VerificationResult {
  /// The final verified and/or repaired response text.
  final String verifiedResponse;

  /// Whether the original response was repaired to correct an unsupported claim.
  final bool wasRepaired;

  /// Specific verification issues detected (if any).
  final List<String> issues;

  /// Estimated grounding confidence (0.0 to 1.0).
  final double confidence;

  const VerificationResult({
    required this.verifiedResponse,
    this.wasRepaired = false,
    this.issues = const [],
    this.confidence = 1.0,
  });

  @override
  String toString() =>
      'VerificationResult(repaired: $wasRepaired, issues: $issues, confidence: $confidence)';
}

/// Service for evidence-aware response grounding and verification (Companion Core V1 Phase 3).
///
/// Principles:
/// - Verifies that generated responses do not make claims unsupported by actual runtime evidence
/// - Detects unsupported source claims (e.g. claiming "I checked Reuters" when Reuters was not in the sources)
/// - Detects false tool claims (e.g. claiming a second search occurred when none did)
/// - Enforces same-name identity safety (distinguishing user-provided name from arbitrary public web search hits)
/// - Performs natural, character-aware repairs without exposing internal verification jargon
class ResponseVerificationService {
  const ResponseVerificationService();

  /// Inspects and verifies [generatedResponse] against the available [toolRecord],
  /// [resolvedContext], and conversation context.
  VerificationResult verifyAndRepair({
    required String generatedResponse,
    required String userMessage,
    required ResolvedConversationContext resolvedContext,
    ToolExecutionRecord? toolRecord,
    required String characterId,
    required String language,
    String? userName,
  }) {
    final raw = generatedResponse.trim();
    if (raw.isEmpty) {
      return VerificationResult(
        verifiedResponse: raw,
        confidence: 0.0,
      );
    }

    final isAf = language == 'af';
    final issues = <String>[];
    var candidate = raw;

    final effectiveTool = toolRecord ?? resolvedContext.referencedToolExecution;
    final sources = effectiveTool?.sources ?? [];
    final evidence = effectiveTool?.evidence ?? [];

    // -------------------------------------------------------------------------
    // 1. False Tool / Re-search Claim Verification
    // -------------------------------------------------------------------------
    // If no search ran on this turn (e.g. source follow-up) but response claims it searched again
    if (resolvedContext.isAskingForSources || (effectiveTool == null && resolvedContext.isFollowUp)) {
      if (_claimsRecentSearch(candidate, isAf)) {
        issues.add('false_search_claim');
        // If the query was purely asking for sources, ensure response focuses on existing sources
        if (resolvedContext.isAskingForSources && effectiveTool != null && effectiveTool.success) {
          final sourcesText = sources.isNotEmpty
              ? sources.join(', ')
              : (isAf ? 'openbare webbronne' : 'public web sources');
          candidate = _formatNaturalSourceConfirmation(
            characterId: characterId,
            query: effectiveTool.query,
            sourcesText: sourcesText,
            isAf: isAf,
          );
        }
      }
    }

    // -------------------------------------------------------------------------
    // 2. Unsupported Source Claims Verification
    // -------------------------------------------------------------------------
    // Detect if the response names prominent news/web sources that are NOT in the actual sources list
    final unsupportedSources = _findUnsupportedSources(candidate, sources);
    if (unsupportedSources.isNotEmpty) {
      issues.add('unsupported_source_claim: ${unsupportedSources.join(", ")}');
      debugPrint('[Verifier] Flagged unsupported source claims: $unsupportedSources (actual: $sources)');

      // Repair: If the actual tool ran with real sources, replace or qualify the source assertion
      if (sources.isNotEmpty) {
        final realSourcesText = sources.join(', ');
        for (final fakeSource in unsupportedSources) {
          final regex = RegExp(r'\b' + RegExp.escape(fakeSource) + r'\b', caseSensitive: false);
          candidate = candidate.replaceAll(regex, realSourcesText);
        }
      } else if (effectiveTool == null || !effectiveTool.success) {
        // No valid search ran
        candidate = _formatNoVerifiedSourcesResponse(
          characterId: characterId,
          query: effectiveTool?.query ?? resolvedContext.activeTopic ?? (isAf ? 'die onderwerp' : 'that'),
          isAf: isAf,
        );
      }
    }

    // -------------------------------------------------------------------------
    // 3. Failed or Empty Search Grounding Verification
    // -------------------------------------------------------------------------
    // If the tool failed or found zero results, ensure the response does NOT present fabricated facts
    if (effectiveTool != null && !effectiveTool.success) {
      if (_presentsFactualFindings(candidate, isAf)) {
        issues.add('unsupported_factual_claim_on_failed_search');
        candidate = _formatNoVerifiedSourcesResponse(
          characterId: characterId,
          query: effectiveTool.query,
          isAf: isAf,
        );
      }
    }

    // -------------------------------------------------------------------------
    // 4. Same-Name / User Identity Conflation Safety
    // -------------------------------------------------------------------------
    // If user introduced their name (e.g. "I am Chris Loubser") and response asserts third-party
    // public records as absolute, indisputable facts about the user's personal identity
    if (userName != null && userName.isNotEmpty) {
      final lowerUserMsg = userMessage.toLowerCase();
      final isSelfFactQuery = lowerUserMsg.contains('about me') ||
          lowerUserMsg.contains('van my') ||
          lowerUserMsg.contains('oor my') ||
          lowerUserMsg.contains('interesting facts') ||
          lowerUserMsg.contains('interessante feite');

      if (isSelfFactQuery && _claimsAbsoluteIdentityConflation(candidate, userName, isAf)) {
        issues.add('unverified_same_name_conflation');
        candidate = _repairSameNameConflation(
          response: candidate,
          userName: userName,
          isAf: isAf,
        );
      }
    }

    // -------------------------------------------------------------------------
    // 5. Verification Status Follow-Up Grounding ("Which parts are verified?")
    // -------------------------------------------------------------------------
    if (resolvedContext.resolvedIntent == 'ask_verification_status' ||
        userMessage.toLowerCase().contains('which parts are verified') ||
        userMessage.toLowerCase().contains('watter dele is geverifieer') ||
        userMessage.toLowerCase().contains('are you sure') ||
        userMessage.toLowerCase().contains('is jy seker')) {
      if (evidence.isNotEmpty) {
        final verifiedSnippets = evidence.map((e) => e.snippet).take(2).join('; ');
        candidate = isAf
            ? 'Die inligting wat direk uit die soektog bevestig is: $verifiedSnippets. Enigiets verder as dit is ongeverifieerd.'
            : 'The specific details directly confirmed by public web sources are: $verifiedSnippets. Anything beyond that remains unverified.';
        issues.add('grounded_verification_status');
      } else if (effectiveTool != null && effectiveTool.success && effectiveTool.summary != null) {
        candidate = isAf
            ? 'Wat geverifieer is volgens die soektog: ${effectiveTool.summary}.'
            : 'What is verified from the search records: ${effectiveTool.summary}.';
        issues.add('grounded_verification_status');
      } else {
        candidate = isAf
            ? 'Ek het nie geverifieerde bronne vir daardie spesifieke besonderhede nie, so ek kan nie met sekerheid sê nie.'
            : 'I don’t have verified source records for those specific details, so I can’t confirm them with certainty.';
        issues.add('grounded_verification_status_empty');
      }
    }

    final wasRepaired = issues.isNotEmpty && candidate != raw;
    final confidence = issues.isEmpty ? 1.0 : (wasRepaired ? 0.85 : 0.4);

    return VerificationResult(
      verifiedResponse: candidate,
      wasRepaired: wasRepaired,
      issues: issues,
      confidence: confidence,
    );
  }

  // ---------------------------------------------------------------------------
  // Detection Helpers
  // ---------------------------------------------------------------------------

  bool _claimsRecentSearch(String text, bool isAf) {
    final lower = text.toLowerCase();
    const searchClaims = [
      'i searched the web again',
      'i did another search',
      'i performed another search',
      'i ran a new search',
      'i just searched again',
      'ek het weer gesoek',
      'ek het \'n nuwe soektog',
      'ek het weer aanlyn gekyk',
    ];
    for (final claim in searchClaims) {
      if (lower.contains(claim)) return true;
    }
    return false;
  }

  List<String> _findUnsupportedSources(String text, List<String> actualSources) {
    final lower = text.toLowerCase();
    final normalizedActual = actualSources.map((s) => s.toLowerCase()).toSet();

    const knownMajorSources = [
      'reuters', 'bloomberg', 'cnn', 'bbc', 'new york times', 'the guardian',
      'associated press', 'washington post', 'forbes', 'wsj', 'news24',
      'netwerk24', 'maroela media', 'daily maverick', 'techcrunch', 'wired'
    ];

    final unsupported = <String>[];
    for (final source in knownMajorSources) {
      final matchesText = lower.contains(source);
      if (matchesText) {
        final isActuallyInSources = normalizedActual.any((actual) => actual.contains(source));
        if (!isActuallyInSources) {
          unsupported.add(source);
        }
      }
    }

    return unsupported;
  }

  bool _presentsFactualFindings(String text, bool isAf) {
    final lower = text.toLowerCase();
    if (isAf) {
      return lower.contains('die soektog het gevind') ||
          lower.contains('hier is wat ek gevind het') ||
          lower.contains('volgens die web');
    } else {
      return lower.contains('the search found that') ||
          lower.contains('here is what i found') ||
          lower.contains('according to the web');
    }
  }

  bool _claimsAbsoluteIdentityConflation(String text, String userName, bool isAf) {
    final lower = text.toLowerCase();
    // If response does NOT contain any qualifying hedge (e.g. "public profile for someone with your name",
    // "cannot verify if this is you", "iemand met jou naam"), but makes direct identity assertions ("You are...", "Jy is...")
    final hasHedge = lower.contains('cannot verify') ||
        lower.contains('can\'t verify') ||
        lower.contains('someone named') ||
        lower.contains('someone with your name') ||
        lower.contains('public records for') ||
        lower.contains('kan nie verifieer nie') ||
        lower.contains('iemand met jou naam') ||
        lower.contains('openbare rekords vir');

    if (!hasHedge && (lower.contains('you are a') || lower.contains('you founded') || lower.contains('you work at') || lower.contains('jy is \'n') || lower.contains('jy werk by'))) {
      return true;
    }

    return false;
  }

  String _repairSameNameConflation({
    required String response,
    required String userName,
    required bool isAf,
  }) {
    if (isAf) {
      return 'Ek het openbare inligting gevind vir iemand genaamd $userName, maar let wel: ek kan nie verifieer of hierdie openbare rekords direk na jou verwys nie. $response';
    } else {
      return 'I found public records mentioning someone named $userName, but please note: I cannot verify whether these public records refer directly to you. $response';
    }
  }

  String _formatNaturalSourceConfirmation({
    required String characterId,
    required String query,
    required String sourcesText,
    required bool isAf,
  }) {
    switch (characterId.toLowerCase()) {
      case 'ara':
        return isAf
            ? 'Toe ek vroeër vir $query gekyk het, het ek openbare bronne soos $sourcesText geraadpleeg.'
            : 'When I looked up $query earlier, I consulted public online sources including $sourcesText.';
      case 'leo':
        return isAf
            ? 'Vir $query het ek vroeër die web geraadpleeg by $sourcesText.'
            : 'For $query, I checked public records across $sourcesText.';
      case 'rex':
        return isAf
            ? 'Ek het vroeër aanlyn vir $query gekyk by $sourcesText!'
            : 'I checked online earlier for $query across $sourcesText!';
      case 'sal':
        return isAf
            ? 'Ek het vroeër vir $query op die web gekyk, hoofsaaklik by $sourcesText.'
            : 'I looked up $query earlier, mainly checking $sourcesText.';
      case 'eve':
      default:
        return isAf
            ? 'Toe ek vroeër vir $query aanlyn gesoek het, het ek na inligting op $sourcesText gekyk.'
            : 'When I searched online for $query earlier, I looked across sources like $sourcesText.';
    }
  }

  String _formatNoVerifiedSourcesResponse({
    required String characterId,
    required String query,
    required bool isAf,
  }) {
    switch (characterId.toLowerCase()) {
      case 'ara':
        return isAf
            ? 'Ek het aanlyn probeer kyk vir $query, maar kon geen geverifieerde bronne of resultate vind nie.'
            : 'I looked online for $query, but found no verified sources or public records.';
      case 'leo':
        return isAf
            ? 'Ek het probeer soek vir $query, maar die soektog het geen geldige bronne opgelewer nie.'
            : 'I searched for $query, but no valid source data was returned.';
      case 'rex':
        return isAf
            ? 'Ek het probeer soek vir $query, maar niks het opgedaag nie!'
            : 'I tried checking online for $query, but didn\'t get any source hits!';
      case 'sal':
        return isAf
            ? 'Ek het aanlyn gekyk vir $query, maar daar was geen bronne beskikbaar nie.'
            : 'I checked online for $query, but no sources came back.';
      case 'eve':
      default:
        return isAf
            ? 'Ek het aanlyn probeer kyk vir $query, maar kon geen geverifieerde bronne of resultate vind nie.'
            : 'I tried searching online for $query, but no verified sources or results were returned.';
    }
  }
}
