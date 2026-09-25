import 'package:flutter/foundation.dart';
import 'ai_service.dart';
import 'image_proxy_transport.dart';
import '../models/ai_provider_type.dart';
import '../models/image_reference.dart';

/// An [AiService] implementation that routes conversational requests to
/// whichever provider is currently selected by the user (e.g. xAI or Gemini).
///
/// Supports optional [BackendProxyImageTransport] for secure, unauthenticated
/// client-side image generation when vendor API keys are not supplied.
///
/// Keeps [ChatProvider] completely decoupled from individual vendor SDKs and APIs.
class SwitchableAiService implements AiService {
  final Map<AiProviderType, AiService> _providers;
  AiProviderType _activeType;
  BackendProxyImageTransport? _imageProxyTransport;

  SwitchableAiService({
    required Map<AiProviderType, AiService> providers,
    AiProviderType initialType = AiProviderType.gemini,
    BackendProxyImageTransport? imageProxyTransport,
  })  : _providers = providers,
        _activeType = initialType,
        _imageProxyTransport = imageProxyTransport;

  AiProviderType get activeType => _activeType;

  AiService get activeService =>
      _providers[_activeType] ?? _providers.values.first;

  BackendProxyImageTransport? get imageProxyTransport => _imageProxyTransport;

  void setImageProxyTransport(BackendProxyImageTransport? transport) {
    _imageProxyTransport = transport;
  }

  void setActiveProvider(AiProviderType type) {
    if (_providers.containsKey(type)) {
      _activeType = type;
    }
  }

  AiService? getProvider(AiProviderType type) => _providers[type];

  @override
  void setApiKey(String key) {
    activeService.setApiKey(key);
  }

  void setApiKeyForProvider(AiProviderType type, String key) {
    _providers[type]?.setApiKey(key);
  }

  @override
  bool get hasApiKey => activeService.hasApiKey;

  bool hasApiKeyForProvider(AiProviderType type) =>
      _providers[type]?.hasApiKey ?? false;

  @override
  Future<String> chatCompletion({
    required List<Map<String, String>> messages,
    String? systemPrompt,
  }) {
    return activeService.chatCompletion(
      messages: messages,
      systemPrompt: systemPrompt,
    );
  }

  @override
  void disconnectRealtime() {
    activeService.disconnectRealtime();
  }

  @override
  Future<String> generateImage(
    String prompt, {
    List<ImageReference>? referenceImages,
  }) async {
    debugPrint(
      '[IMAGE_GENERATION_REQUEST] SwitchableAiService routing image request for "$prompt" (activeType: $_activeType, hasDirectKey: ${activeService.hasApiKey}, hasProxy: ${_imageProxyTransport != null})',
    );

    final directKeyAvailable = activeService.hasApiKey;
    debugPrint(
      '[IMAGE_DIAGNOSTIC] Direct provider attempted: $directKeyAvailable (Provider: ${_activeType.id})',
    );

    // 1. If active vendor has an API key configured, attempt direct provider generation
    if (directKeyAvailable) {
      try {
        final result = await activeService.generateImage(
          prompt,
          referenceImages: referenceImages,
        );
        debugPrint(
          '[IMAGE_GENERATION_SUCCESS] Active provider ($_activeType) direct image generation succeeded (URL length: ${result.length})',
        );
        return result;
      } catch (err) {
        debugPrint(
          '[IMAGE_DIAGNOSTIC] Direct provider ($_activeType) failed: ${err is ImageGenerationException ? err.category.name : err.runtimeType}. Checking proxy fallback...',
        );

        // If backend proxy transport is available, always attempt proxy fallback before failing
        if (_imageProxyTransport != null) {
          try {
            debugPrint(
              '[IMAGE_GENERATION_REQUEST] Attempting backend proxy fallback for ${_activeType.id}...',
            );
            final proxyResult = await _imageProxyTransport!.generateImage(
              prompt,
              referenceImages: referenceImages,
              provider: _activeType.id,
            );
            debugPrint(
              '[IMAGE_GENERATION_SUCCESS] Backend proxy fallback succeeded for ${_activeType.id} (URL length: ${proxyResult.length})',
            );
            return proxyResult;
          } catch (proxyErr) {
            debugPrint(
              '[IMAGE_GENERATION_FAILURE] Backend proxy fallback also failed: $proxyErr',
            );
            if (proxyErr is ImageGenerationException) {
              rethrow;
            }
            if (err is ImageGenerationException) {
              rethrow;
            }
          }
        }
        rethrow;
      }
    }

    // 2. No direct vendor API key configured: route through secure backend image proxy
    if (_imageProxyTransport != null) {
      debugPrint(
        '[IMAGE_GENERATION_REQUEST] Routing image generation through backend proxy (Provider: ${_activeType.id}).',
      );
      final proxyResult = await _imageProxyTransport!.generateImage(
        prompt,
        referenceImages: referenceImages,
        provider: _activeType.id,
      );
      debugPrint(
        '[IMAGE_GENERATION_SUCCESS] Backend image proxy succeeded for ${_activeType.id} (URL length: ${proxyResult.length})',
      );
      return proxyResult;
    }

    throw ImageGenerationException(
      'No API key configured for ${_activeType.displayName} and no backend image proxy available.',
      category: ImageGenerationErrorCategory.auth,
      statusCode: 401,
      isApiKeyIssue: true,
      provider: _activeType.id,
    );
  }
}
