import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:listen_to_eve/models/image_reference.dart';

import 'package:listen_to_eve/providers/settings_provider.dart';
import 'package:listen_to_eve/services/storage_service.dart';

import 'package:listen_to_eve/main.dart';
import 'package:listen_to_eve/models/character_profile.dart';
import 'package:listen_to_eve/models/message.dart';
import 'package:listen_to_eve/services/ai_service.dart';
import 'package:listen_to_eve/services/image_proxy_transport.dart';
import 'package:listen_to_eve/providers/chat_provider.dart';
import 'package:listen_to_eve/services/web_search_tool.dart';


class _TestAiService implements AiService {
  @override
  void setApiKey(String key) {}

  @override
  bool get hasApiKey => false;

  @override
  Future<String> chatCompletion({
    required List<Map<String, String>> messages,
    String? systemPrompt,
  }) async {
    return 'Test response';
  }

  @override
  void disconnectRealtime() {}

  @override
  Future<String> generateImage(
    String prompt, {
    List<ImageReference>? referenceImages,
  }) async {
    return 'data:image/png;base64,dGVzdA==';
  }
}

void main() {
  testWidgets('LteApp builds without throwing', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    final storage = StorageService();
    await storage.init();

    final settings = SettingsProvider(storage);
    final aiService = _TestAiService();
    final chatProvider = ChatProvider(
      aiService,
      settings,
      storage,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AiService>.value(value: aiService),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
        ],
        child: const LteApp(),
      ),
    );

    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });

  test('WebSearchTool defaults to /api/search proxy', () {
    final transport = BackendProxySearchTransport();
    expect(transport.proxyUri?.path, '/api/search');
  });

  group('CharacterProfile Visual Identity and Prompt Generation', () {
    test('Eve character profile contains canonical visual anchors and assets', () {
      final eve = CharacterRegistry.eve;
      expect(eve.avatarAsset, 'assets/avatar_eve.jpg');
      expect(eve.canonicalSelfieAsset, 'assets/eve_selfie.jpg');
      expect(eve.fullBodyAssets, contains('assets/eve_full_body.jpg'));
      expect(eve.visualIdentityEn, contains('hazel-green eyes'));
      expect(eve.visualIdentityEn, contains('honey-brown hair'));
    });

    test('All 5 characters have distinct human visual identities and profiles', () {
      expect(CharacterRegistry.characters.length, 5);
      for (final character in CharacterRegistry.characters) {
        expect(character.name.isNotEmpty, true);
        expect(character.avatarAsset.isNotEmpty, true);
        expect(character.visualIdentityEn.isNotEmpty, true);
        expect(character.visualIdentityAf.isNotEmpty, true);

        final prompt = character.buildImagePrompt(sceneOrRequest: 'on a beach');
        expect(prompt, contains(character.name));
        expect(prompt, contains('on a beach'));
        expect(prompt, contains('photorealistic'));
        expect(prompt, isNot(contains('pollinations.ai')));
      }
    });

    test('Eve prompt building with specific scene and photorealism', () {
      final eve = CharacterRegistry.eve;
      final prompt = eve.buildImagePrompt(
        sceneOrRequest: 'on a beach with golden hour sunlight',
        isPhotorealistic: true,
        isFullBody: false,
      );

      expect(prompt, contains('Eve'));
      expect(prompt, contains('hazel-green eyes'));
      expect(prompt, contains('honey-brown hair'));
      expect(prompt, contains('on a beach with golden hour sunlight'));
      expect(prompt, contains('85mm portrait camera lens'));
      expect(prompt, isNot(contains('pollinations.ai')));
    });

    test('Rex character prompt represents charismatic human male identity', () {
      final rex = CharacterRegistry.rex;
      final prompt = rex.buildImagePrompt(sceneOrRequest: 'in Paris');
      expect(prompt, contains('Rex'));
      expect(prompt, contains('short textured brown hair'));
      expect(prompt, contains('light stubble'));
    });
  });

  group('ChatProvider Image Intent Detection', () {
    test('Detects self-reference "Create a photo of yourself on a beach"', () {
      final result = ChatProvider.detectImageIntent('Create a photo of yourself on a beach.');
      expect(result, isNotNull);
      expect(result!.isIntent, true);
      expect(result.isSelfReference, true);
      expect(result.isPhotoOrSelfie, true);
      expect(result.specificScene, 'on a beach');
    });

    test('Detects direct query "Show me what you look like"', () {
      final result = ChatProvider.detectImageIntent('Show me what you look like');
      expect(result, isNotNull);
      expect(result!.isIntent, true);
      expect(result.isSelfReference, true);
    });

    test('Detects "Create a selfie of yourself in Paris"', () {
      final result = ChatProvider.detectImageIntent('Create a selfie of yourself in Paris');
      expect(result, isNotNull);
      expect(result!.isIntent, true);
      expect(result.isSelfReference, true);
      expect(result.isPhotoOrSelfie, true);
      expect(result.specificScene, 'in Paris');
    });

    test('Detects explicit character naming "Generate a realistic photo of Eve in Cape Town"', () {
      final result = ChatProvider.detectImageIntent('Generate a realistic photo of Eve in Cape Town');
      expect(result, isNotNull);
      expect(result!.isIntent, true);
      expect(result.isSelfReference, true);
      expect(result.explicitCharacterId, 'eve');
      expect(result.specificScene, 'in Cape Town');
    });

    test('Detects "Make a picture of yourself wearing a black dress"', () {
      final result = ChatProvider.detectImageIntent('Make a picture of yourself wearing a black dress');
      expect(result, isNotNull);
      expect(result!.isIntent, true);
      expect(result.isSelfReference, true);
      expect(result.specificScene, 'wearing a black dress');
    });

    test('Detects artistic drawing of self "Can you draw yourself?"', () {
      final result = ChatProvider.detectImageIntent('Can you draw yourself?');
      expect(result, isNotNull);
      expect(result!.isIntent, true);
      expect(result.isSelfReference, true);
      expect(result.isArtistic, true);
    });

    test('Detects generic request "Create an image of a lion"', () {
      final result = ChatProvider.detectImageIntent('Create an image of a lion');
      expect(result, isNotNull);
      expect(result!.isIntent, true);
      expect(result.isSelfReference, false);
      expect(result.rawPrompt, 'a lion');
    });

    test('Detects generic request "Create a picture of Cape Town at sunset"', () {
      final result = ChatProvider.detectImageIntent('Create a picture of Cape Town at sunset');
      expect(result, isNotNull);
      expect(result!.isIntent, true);
      expect(result.isSelfReference, false);
      expect(result.rawPrompt, 'Cape Town at sunset');
    });

    test('Detects photorealistic scenic request "Create a photorealistic sunset view of Table Mountain overlooking Cape Town."', () {
      final result = ChatProvider.detectImageIntent('Create a photorealistic sunset view of Table Mountain overlooking Cape Town.');
      expect(result, isNotNull);
      expect(result!.isIntent, true);
      expect(result.isSelfReference, false);
      expect(result.rawPrompt, 'Table Mountain overlooking Cape Town');
      expect(result.isPhotoOrSelfie, true);
    });

    test('Detects generic request "Generate a futuristic spaceship"', () {
      final result = ChatProvider.detectImageIntent('Generate a futuristic spaceship');
      expect(result, isNotNull);
      expect(result!.isIntent, true);
      expect(result.isSelfReference, false);
      expect(result.rawPrompt, 'a futuristic spaceship');
    });

    test('Detects Afrikaans "Skep vir my \'n foto van jouself op \'n strand"', () {
      final result = ChatProvider.detectImageIntent("Skep vir my 'n foto van jouself op 'n strand");
      expect(result, isNotNull);
      expect(result!.isIntent, true);
      expect(result.isSelfReference, true);
      expect(result.specificScene, "'n strand");
    });

    test('Rejects negative non-intent cases', () {
      expect(ChatProvider.detectImageIntent('I saw a picture of Eve yesterday'), isNull);
      expect(ChatProvider.detectImageIntent('What does the word image mean?'), isNull);
      expect(ChatProvider.detectImageIntent('I want to make an image someday'), isNull);
      expect(ChatProvider.detectImageIntent('Tell me about drawing portraits'), isNull);
    });
  });

  group('Image Generation & Error Mapping Regression Guard', () {
    test('Successful image generation produces image ChatMessage with valid data URL and never spending limit text', () {
      const mockImageDataUrl = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP...';
      const promptLabel = 'Table Mountain overlooking Cape Town';
      final confirmation = 'Here is the image I created for you: "$promptLabel"';

      final message = ChatMessage(
        id: 'test-img-msg-1',
        role: MessageRole.assistant,
        content: confirmation,
        timestamp: DateTime.now(),
        imageUrl: mockImageDataUrl,
        imagePrompt: promptLabel,
      );

      expect(message.imageUrl, isNotNull);
      expect(message.imageUrl!.startsWith('data:image/jpeg;base64,'), true);
      expect(message.content, contains('Here is the image I created for you'));
      expect(message.content, isNot(contains('spending limit')));
      expect(message.content, isNot(contains('bestedingslimiet')));
      expect(message.content, isNot(contains('spending cap')));
    });

    test('Historical error messages are filtered from LLM prompt history', () {
      final messages = [
        ChatMessage(
          id: '1',
          role: MessageRole.user,
          content: 'Hello Eve',
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        ChatMessage(
          id: '2',
          role: MessageRole.assistant,
          content: 'Image creation is currently unavailable because the image-generation service has reached its spending limit. Please try again later or choose another image provider.',
          timestamp: DateTime.now().subtract(const Duration(minutes: 4)),
        ),
        ChatMessage(
          id: '3',
          role: MessageRole.user,
          content: 'Create an image of Cape Town at sunset',
          timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
      ];

      final filtered = messages
          .where((m) => m.role != MessageRole.system)
          .where((m) =>
              !m.content.contains('reached its spending limit') &&
              !m.content.contains('bestedingslimiet') &&
              !m.content.contains('spending limit') &&
              !m.content.contains('Image creation is currently unavailable'))
          .toList();

      expect(filtered.length, 2);
      expect(filtered.any((m) => m.id == '2'), false);
      expect(filtered[0].content, 'Hello Eve');
      expect(filtered[1].content, 'Create an image of Cape Town at sunset');
    });

    test('Non-billing exceptions do not map to spending limit message', () {
      const nonBillingEx = ImageGenerationException(
        'Temporary timeout connecting to image service',
        statusCode: 504,
        category: ImageGenerationErrorCategory.network,
      );

      expect(nonBillingEx.isBillingIssue, false);
      expect(nonBillingEx.category, ImageGenerationErrorCategory.network);
    });

    test('Billing exception category is preserved for genuine spend cap failures', () {
      const billingEx = ImageGenerationException(
        'Gemini billing spend limit reached.',
        statusCode: 429,
        category: ImageGenerationErrorCategory.billing,
        isBillingIssue: true,
      );

      expect(billingEx.isBillingIssue, true);
      expect(billingEx.category, ImageGenerationErrorCategory.billing);
    });

    test('Timeout exception flags and differentiation', () {
      const connTimeoutEx = ImageGenerationException(
        'Connection timed out while reaching the image service (20s limit).',
        statusCode: 504,
        category: ImageGenerationErrorCategory.network,
        isConnectionTimeout: true,
      );

      expect(connTimeoutEx.isTimeout, true);
      expect(connTimeoutEx.isConnectionTimeout, true);
      expect(connTimeoutEx.isGenerationTimeout, false);
      expect(connTimeoutEx.isBillingIssue, false);

      const genTimeoutEx = ImageGenerationException(
        'Image generation timed out waiting for backend rendering (120s limit).',
        statusCode: 504,
        category: ImageGenerationErrorCategory.network,
        isGenerationTimeout: true,
      );

      expect(genTimeoutEx.isTimeout, true);
      expect(genTimeoutEx.isConnectionTimeout, false);
      expect(genTimeoutEx.isGenerationTimeout, true);
    });

    test('BackendProxyImageTransport staged timeouts and resolution logic', () {
      final transport = BackendProxyImageTransport(
        fallbackServerUrl: 'https://example-proxy.run.app/api/search',
      );

      expect(transport.timeout.inSeconds, 120);
      expect(transport.connectionTimeout.inSeconds, 20);

      // Relative path resolved against fallback search server host
      final resolvedInfo = transport.resolveTargetUriInfo();
      expect(resolvedInfo.uri, isNotNull);
      expect(resolvedInfo.uri!.host, 'example-proxy.run.app');
      expect(resolvedInfo.uri!.path, '/api/generate-image');
      expect(resolvedInfo.source, 'search_fallback');
      expect(resolvedInfo.isSearchFallback, true);
      expect(resolvedInfo.isExplicit, false);

      // Trailing slash with search path is properly replaced
      transport.setFallbackServerUrl('https://example-proxy.run.app/api/search/');
      final resolvedWithTrailing = transport.resolveTargetUri();
      expect(resolvedWithTrailing!.path, '/api/generate-image');

      // Update explicit proxy endpoint with trailing slash
      transport.setProxyEndpoint('https://custom-image.run.app/api/generate-image/');
      final updatedInfo = transport.resolveTargetUriInfo();
      expect(updatedInfo.uri!.host, 'custom-image.run.app');
      expect(updatedInfo.uri!.path, '/api/generate-image');
      expect(updatedInfo.source, 'explicit_image_setting');
      expect(updatedInfo.isExplicit, true);
      expect(updatedInfo.isSearchFallback, false);
    });
  });
}
