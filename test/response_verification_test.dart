import 'package:flutter_test/flutter_test.dart';
import 'package:listen_to_eve/models/conversation_state.dart';
import 'package:listen_to_eve/models/evidence_item.dart';
import 'package:listen_to_eve/models/resolved_conversation_context.dart';
import 'package:listen_to_eve/models/tool_execution_record.dart';
import 'package:listen_to_eve/services/action_ledger.dart';
import 'package:listen_to_eve/services/conversation_context_resolver.dart';
import 'package:listen_to_eve/services/offline_conversational_fallback.dart';
import 'package:listen_to_eve/services/response_verification_service.dart';

void main() {
  group('Companion Core V1 Phase 3: Response Grounding & Verification Tests', () {
    late ResponseVerificationService verifier;
    late ConversationContextResolver resolver;
    late ActionLedger ledger;

    setUp(() {
      verifier = const ResponseVerificationService();
      resolver = const ConversationContextResolver();
      ledger = ActionLedger();
    });

    test('1. Supported claim with authentic sources is accepted without alteration', () {
      final record = ToolExecutionRecord(
        toolName: 'web_search',
        query: 'Table Mountain',
        timestamp: DateTime.now(),
        success: true,
        sources: ['capetown.travel', 'wikipedia.org'],
        evidence: [
          EvidenceItem(
            sourceTool: 'web_search',
            title: 'Table Mountain National Park',
            snippet: 'Table Mountain is a prominent landmark overlooking Cape Town.',
            domain: 'capetown.travel',
            timestamp: DateTime.now(),
          ),
        ],
      );

      final result = verifier.verifyAndRepair(
        generatedResponse: 'Table Mountain is a prominent landmark overlooking Cape Town.',
        userMessage: 'What is Table Mountain?',
        resolvedContext: const ResolvedConversationContext(
          isFollowUp: false,
          resolvedIntent: 'ask_facts',
        ),
        toolRecord: record,
        characterId: 'eve',
        language: 'en',
      );

      expect(result.wasRepaired, isFalse);
      expect(result.issues, isEmpty);
      expect(result.verifiedResponse, contains('Table Mountain'));
    });

    test('2. Unsupported source claim is flagged and repaired with actual sources', () {
      final record = ToolExecutionRecord(
        toolName: 'web_search',
        query: 'Chris Loubser',
        timestamp: DateTime.now(),
        success: true,
        sources: ['github.com', 'linkedin.com'],
      );

      final result = verifier.verifyAndRepair(
        generatedResponse: 'According to Reuters, Chris works on mobile development.',
        userMessage: 'Where did you look?',
        resolvedContext: const ResolvedConversationContext(
          isFollowUp: true,
          resolvedIntent: 'show_search_sources',
                ),
        toolRecord: record,
        characterId: 'eve',
        language: 'en',
      );

      expect(result.issues.any((i) => i.contains('unsupported_source_claim')), isTrue);
      expect(result.wasRepaired, isTrue);
      expect(result.verifiedResponse, isNot(contains('Reuters')));
      expect(result.verifiedResponse, contains('github.com, linkedin.com'));
    });

    test('3. False claim that another search occurred is flagged and repaired', () {
      final record = ToolExecutionRecord(
        toolName: 'web_search',
        query: 'Chris Loubser',
        timestamp: DateTime.now(),
        success: true,
        sources: ['github.com'],
      );

      final result = verifier.verifyAndRepair(
        generatedResponse: 'I searched the web again and looked across github.com.',
        userMessage: 'Where did you look?',
        resolvedContext: const ResolvedConversationContext(
          isFollowUp: true,
          resolvedIntent: 'show_search_sources',
                ),
        toolRecord: record,
        characterId: 'eve',
        language: 'en',
      );

      expect(result.issues, contains('false_search_claim'));
      expect(result.wasRepaired, isTrue);
      expect(result.verifiedResponse.toLowerCase(), isNot(contains('i searched the web again')));
    });

    test('4. Failed search produces no fabricated factual evidence', () {
      final record = ToolExecutionRecord(
        toolName: 'web_search',
        query: 'UnknownEntityXYZ',
        timestamp: DateTime.now(),
        success: false,
        sources: [],
      );

      final result = verifier.verifyAndRepair(
        generatedResponse: 'The search found that UnknownEntityXYZ was founded in 1990.',
        userMessage: 'What did you find?',
        resolvedContext: const ResolvedConversationContext(
          isFollowUp: true,
          resolvedIntent: 'query_search_results',
        ),
        toolRecord: record,
        characterId: 'eve',
        language: 'en',
      );

      expect(result.issues, contains('unsupported_factual_claim_on_failed_search'));
      expect(result.wasRepaired, isTrue);
      expect(result.verifiedResponse, contains('no verified sources or results were returned'));
    });

    test('5. No previous search produces no fabricated findings', () {
      final reply = OfflineConversationalFallback.generateReply(
        userMessage: 'What did you find?',
        characterId: 'eve',
        language: 'en',
        resolvedContext: const ResolvedConversationContext(
          isFollowUp: true,
          resolvedIntent: 'show_search_sources_empty',
                  referencedToolExecution: null,
        ),
      );

      expect(reply, contains('We haven’t looked anything up online yet'));
    });

    test('6. User-provided identity is distinguished from same-name web results', () {
      final record = ToolExecutionRecord(
        toolName: 'web_search',
        query: 'Chris Loubser',
        timestamp: DateTime.now(),
        success: true,
        sources: ['publicrecord.org'],
      );

      final result = verifier.verifyAndRepair(
        generatedResponse: 'You are a software engineer who founded tech companies.',
        userMessage: 'I am Chris Loubser. What interesting facts can you find about me?',
        resolvedContext: const ResolvedConversationContext(
          isFollowUp: false,
          resolvedIntent: 'ask_facts',
        ),
        toolRecord: record,
        characterId: 'eve',
        language: 'en',
        userName: 'Chris Loubser',
      );

      expect(result.issues, contains('unverified_same_name_conflation'));
      expect(result.wasRepaired, isTrue);
      expect(result.verifiedResponse, contains('cannot verify whether these public records refer directly to you'));
    });

    test('7. "Which parts are verified?" uses recorded evidence snippets', () {
      final record = ToolExecutionRecord(
        toolName: 'web_search',
        query: 'Chris Loubser',
        timestamp: DateTime.now(),
        success: true,
        sources: ['github.com'],
        evidence: [
          EvidenceItem(
            sourceTool: 'web_search',
            title: 'GitHub Profile',
            snippet: 'Active contributor to open-source Flutter repositories',
            domain: 'github.com',
            timestamp: DateTime.now(),
          ),
        ],
      );

      final result = verifier.verifyAndRepair(
        generatedResponse: 'Everything is true.',
        userMessage: 'Which parts are verified?',
        resolvedContext: ResolvedConversationContext(
          isFollowUp: true,
          resolvedIntent: 'ask_verification_status',
          referencedToolExecution: record,
        ),
        toolRecord: record,
        characterId: 'eve',
        language: 'en',
      );

      expect(result.issues, contains('grounded_verification_status'));
      expect(result.verifiedResponse, contains('Active contributor to open-source Flutter repositories'));
    });

    test('8. "Are you sure?" expresses grounded support without manufactured certainty', () {
      final record = ToolExecutionRecord(
        toolName: 'web_search',
        query: 'Chris Loubser',
        timestamp: DateTime.now(),
        success: true,
        sources: ['publicweb.com'],
        summary: 'Public mentions of a professional with this name',
      );

      final result = verifier.verifyAndRepair(
        generatedResponse: 'Yes, 100% certain without a doubt!',
        userMessage: 'Are you sure?',
        resolvedContext: ResolvedConversationContext(
          isFollowUp: true,
          resolvedIntent: 'ask_verification_status',
          referencedToolExecution: record,
        ),
        toolRecord: record,
        characterId: 'eve',
        language: 'en',
      );

      expect(result.issues, contains('grounded_verification_status'));
      expect(result.verifiedResponse, contains('What is verified from the search records'));
    });

    test('9. Explicit "search again" is allowed and classified as a new search task', () {
      ledger.recordAction(ToolExecutionRecord(
        toolName: 'web_search',
        query: 'Cape Town weather',
        timestamp: DateTime.now(),
        success: true,
      ));

      final context = resolver.resolve('Search again', ledger: ledger);

      expect(context.isFollowUp, isFalse);
      expect(context.resolvedIntent, equals('search_again'));
      expect(context.activeTask, equals('web_search'));
      expect(context.isAskingForSources, isFalse);
    });

    test('10. Weather and image evidence structures remain compatible', () {
      final weatherEvidence = EvidenceItem(
        sourceTool: 'weather_lookup',
        title: 'Open-Meteo Forecast',
        snippet: 'Cape Town: 22°C, Sunny, 15km/h wind',
        domain: 'open-meteo.com',
        timestamp: DateTime.now(),
      );

      final weatherRecord = ToolExecutionRecord(
        toolName: 'weather_lookup',
        query: 'Cape Town',
        timestamp: DateTime.now(),
        success: true,
        sources: ['open-meteo.com'],
        evidence: [weatherEvidence],
      );

      ledger.recordAction(weatherRecord);

      expect(ledger.recentEvidence.length, equals(1));
      expect(ledger.recentEvidence.first.sourceTool, equals('weather_lookup'));
      expect(ledger.recentEvidence.first.snippet, contains('22°C'));
    });

    test('11. Afrikaans verification status and source grounding works accurately', () {
      final record = ToolExecutionRecord(
        toolName: 'web_search',
        query: 'Kaapstad',
        timestamp: DateTime.now(),
        success: true,
        sources: ['netwerk24.com'],
        evidence: [
          EvidenceItem(
            sourceTool: 'web_search',
            snippet: 'Kaapstad ervaar sonnige weer en matige wind.',
            domain: 'netwerk24.com',
            timestamp: DateTime.now(),
          ),
        ],
      );

      final result = verifier.verifyAndRepair(
        generatedResponse: 'Ek is baie seker.',
        userMessage: 'Watter dele is geverifieer?',
        resolvedContext: ResolvedConversationContext(
          isFollowUp: true,
          resolvedIntent: 'ask_verification_status',
          referencedToolExecution: record,
        ),
        toolRecord: record,
        characterId: 'eve',
        language: 'af',
      );

      expect(result.issues, contains('grounded_verification_status'));
      expect(result.verifiedResponse, contains('Die inligting wat direk uit die soektog bevestig is: Kaapstad ervaar sonnige weer'));
    });
  });
}
