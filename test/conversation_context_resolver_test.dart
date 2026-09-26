import 'package:flutter_test/flutter_test.dart';
import 'package:listen_to_eve/models/tool_execution_record.dart';
import 'package:listen_to_eve/services/action_ledger.dart';
import 'package:listen_to_eve/services/conversation_context_resolver.dart';
import 'package:listen_to_eve/services/offline_conversational_fallback.dart';

void main() {
  group('Companion Core V1 Phase 2: Conversational Follow-Up Resolution Tests', () {
    late ActionLedger ledger;
    late ConversationContextResolver resolver;

    setUp(() {
      ledger = ActionLedger();
      resolver = const ConversationContextResolver();
    });

    test('1. Resolves "Where did you look?" to previous web search in ActionLedger', () {
      // 1. Initial turn: User asks about Chris Loubser, tool executes and records in ledger
      ledger.recordAction(ToolExecutionRecord(
        toolName: 'web_search',
        purpose: 'Web Search',
        query: 'Chris Loubser',
        timestamp: DateTime.now(),
        success: true,
        resultCount: 2,
        sources: ['wikipedia.org', 'github.com'],
        summary: '1. Chris Loubser profile (wikipedia.org)\n2. Open source projects (github.com)',
      ));

      // 2. Follow-up turn: User asks "Where did you look?"
      final resolved = resolver.resolve(
        'Where did you look?',
        state: ledger.state,
        ledger: ledger,
      );

      expect(resolved.isFollowUp, isTrue);
      expect(resolved.resolvedIntent, equals('show_search_sources'));
      expect(resolved.isAskingForSources, isTrue);
      expect(resolved.activeTopic, equals('Chris Loubser'));
      expect(resolved.referencedToolExecution, isNotNull);
      expect(resolved.referencedToolExecution!.sources, containsAll(['wikipedia.org', 'github.com']));
      expect(resolved.referencedToolExecution!.query, equals('Chris Loubser'));

      // 3. Verify formatted prompt context
      final promptBlock = resolved.formatForPrompt(language: 'en');
      expect(promptBlock, isNotNull);
      expect(promptBlock, contains('Chris Loubser'));
      expect(promptBlock, contains('wikipedia.org, github.com'));

      // 4. Verify offline fallback generates natural answer with real sources
      final replyEn = OfflineConversationalFallback.generateReply(
        userMessage: 'Where did you look?',
        characterId: 'eve',
        language: 'en',
        resolvedContext: resolved,
      );

      expect(replyEn, contains('wikipedia.org, github.com'));
      expect(replyEn, contains('Chris Loubser'));
    });

    test('2. Afrikaans source inquiry: "Waar het jy gesoek?"', () {
      ledger.recordAction(ToolExecutionRecord(
        toolName: 'web_search',
        purpose: 'Web Search',
        query: 'Kaapstad Tafelberg',
        timestamp: DateTime.now(),
        success: true,
        resultCount: 1,
        sources: ['capetown.travel'],
        summary: 'Tafelberg Nasionale Park inligting.',
      ));

      final resolved = resolver.resolve(
        'Waar het jy gesoek?',
        state: ledger.state,
        ledger: ledger,
      );

      expect(resolved.isFollowUp, isTrue);
      expect(resolved.isAskingForSources, isTrue);
      expect(resolved.activeTopic, equals('Kaapstad Tafelberg'));

      final replyAf = OfflineConversationalFallback.generateReply(
        userMessage: 'Waar het jy gesoek?',
        characterId: 'eve',
        language: 'af',
        resolvedContext: resolved,
      );

      expect(replyAf, contains('capetown.travel'));
      expect(replyAf, contains('Kaapstad Tafelberg'));
    });

    test('3. Failed previous search returns honest message without hallucinating sources', () {
      ledger.recordAction(ToolExecutionRecord(
        toolName: 'web_search',
        purpose: 'Web Search',
        query: 'Obscure Unknown Person 12345',
        timestamp: DateTime.now(),
        success: false,
        resultCount: 0,
        sources: [],
        error: 'No results found',
      ));

      final resolved = resolver.resolve(
        'What were your sources?',
        state: ledger.state,
        ledger: ledger,
      );

      expect(resolved.isFollowUp, isTrue);
      expect(resolved.isAskingForSources, isTrue);
      expect(resolved.referencedToolExecution!.success, isFalse);

      final replyEn = OfflineConversationalFallback.generateReply(
        userMessage: 'What were your sources?',
        characterId: 'eve',
        language: 'en',
        resolvedContext: resolved,
      );

      expect(replyEn.toLowerCase(), contains('no verified sources'));
    });

    test('4. Source inquiry when no search has occurred yet in conversation', () {
      final resolved = resolver.resolve(
        'Where did you look?',
        state: ledger.state,
        ledger: ledger,
      );

      expect(resolved.isFollowUp, isTrue);
      expect(resolved.referencedToolExecution, isNull);

      final replyEn = OfflineConversationalFallback.generateReply(
        userMessage: 'Where did you look?',
        characterId: 'eve',
        language: 'en',
        resolvedContext: resolved,
      );

      expect(replyEn.toLowerCase(), contains("haven’t looked anything up"));
    });

    test('5. Result follow-up inquiry: "What did you find?"', () {
      ledger.recordAction(ToolExecutionRecord(
        toolName: 'web_search',
        purpose: 'Web Search',
        query: 'Quantum Computing',
        timestamp: DateTime.now(),
        success: true,
        resultCount: 1,
        sources: ['nature.com'],
        summary: 'Recent advancements in superconducting qubits.',
      ));

      final resolved = resolver.resolve(
        'What did you find?',
        state: ledger.state,
        ledger: ledger,
      );

      expect(resolved.isFollowUp, isTrue);
      expect(resolved.isAskingForDetails, isTrue);
      expect(resolved.activeTopic, equals('Quantum Computing'));

      final replyEn = OfflineConversationalFallback.generateReply(
        userMessage: 'What did you find?',
        characterId: 'eve',
        language: 'en',
        resolvedContext: resolved,
      );

      expect(replyEn, contains('Recent advancements in superconducting qubits.'));
    });

    test('6. Explicit topic shift breaks follow-up chain cleanly', () {
      // Prior web search
      ledger.recordAction(ToolExecutionRecord(
        toolName: 'web_search',
        purpose: 'Web Search',
        query: 'Chris Loubser',
        timestamp: DateTime.now(),
        success: true,
        sources: ['wikipedia.org'],
      ));

      // User asks completely new question
      final resolved = resolver.resolve(
        'Weather in Durban',
        state: ledger.state,
        ledger: ledger,
      );

      expect(resolved.isFollowUp, isFalse);
      expect(resolved.resolvedIntent, equals('ask_weather'));
      expect(resolved.activeTopic, equals('weather_Durban'));
      expect(resolved.referencedToolExecution, isNull);
    });

    test('7. Character voice distinctions for source follow-ups', () {
      ledger.recordAction(ToolExecutionRecord(
        toolName: 'web_search',
        purpose: 'Web Search',
        query: 'SpaceX Starship',
        timestamp: DateTime.now(),
        success: true,
        sources: ['spacex.com', 'nasa.gov'],
        summary: 'Flight 5 successful booster catch.',
      ));

      final resolved = resolver.resolve(
        'Where did you find that?',
        state: ledger.state,
        ledger: ledger,
      );

      final characters = ['eve', 'ara', 'leo', 'rex', 'sal'];
      final replies = <String, String>{};

      for (final c in characters) {
        final reply = OfflineConversationalFallback.generateReply(
          userMessage: 'Where did you find that?',
          characterId: c,
          language: 'en',
          resolvedContext: resolved,
        );
        expect(reply, contains('spacex.com, nasa.gov'));
        replies[c] = reply;
      }

      // Check distinct personality phrasing
      expect(replies['rex'], contains('!'));
      expect(replies['leo'], contains('checked public online records'));
      expect(replies['ara'], contains('consulted public online sources'));
      expect(replies['sal'], contains('mainly checking'));
      expect(replies['eve'], contains('When I searched online'));
    });
  });
}
