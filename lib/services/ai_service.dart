import '../models/image_reference.dart';

/// Abstract interface for AI providers in Listen to Eve.
///
/// Decouples conversation orchestration and memory from any single AI vendor
/// (e.g. xAI Grok, Gemini, OpenAI).
abstract class AiService {
  /// Sets or updates the active API key for this provider.
  void setApiKey(String key);

  /// Whether a valid API key is currently configured for this provider.
  bool get hasApiKey;

  /// Generates a conversational chat completion response.
  ///
  /// [messages] is the list of previous turns formatted as role-content maps.
  /// [systemPrompt] optionally specifies persona instructions or guidelines.
  Future<String> chatCompletion({
    required List<Map<String, String>> messages,
    String? systemPrompt,
  });

  /// Disconnects and cleans up any active realtime voice or streaming sessions.
  void disconnectRealtime();

  /// Generates an image using the active AI provider.
  ///
  /// Supports optional [referenceImages] for multimodal identity conditioning.
  /// Returns a displayable image URL or data URI.
  Future<String> generateImage(
    String prompt, {
    List<ImageReference>? referenceImages,
  });
}

/// Structured error categories for image generation failures across AI providers.
enum ImageGenerationErrorCategory {
  validation,
  auth,
  quota,
  billing,
  rateLimit,
  provider,
  network,
  unsupported,
  server,
  unknown;

  static ImageGenerationErrorCategory fromString(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'validation':
        return ImageGenerationErrorCategory.validation;
      case 'auth':
      case 'authentication':
        return ImageGenerationErrorCategory.auth;
      case 'quota':
        return ImageGenerationErrorCategory.quota;
      case 'billing':
      case 'spend_cap':
        return ImageGenerationErrorCategory.billing;
      case 'rate_limit':
      case 'ratelimit':
        return ImageGenerationErrorCategory.rateLimit;
      case 'provider':
      case 'provider_error':
        return ImageGenerationErrorCategory.provider;
      case 'network':
      case 'timeout':
        return ImageGenerationErrorCategory.network;
      case 'unsupported':
      case 'safety':
        return ImageGenerationErrorCategory.unsupported;
      case 'server':
        return ImageGenerationErrorCategory.server;
      default:
        return ImageGenerationErrorCategory.unknown;
    }
  }
}

/// Exception thrown when image generation fails across any AI provider.
class ImageGenerationException implements Exception {
  final String message;
  final int? statusCode;
  final String? provider;
  final ImageGenerationErrorCategory category;
  final String? sanitizedDetail;

  const ImageGenerationException(
    this.message, {
    this.statusCode,
    this.provider,
    this.category = ImageGenerationErrorCategory.unknown,
    bool isApiKeyIssue = false,
    bool isQuotaIssue = false,
    bool isBillingIssue = false,
    bool isRateLimitIssue = false,
    bool isTimeout = false,
    bool isConnectionTimeout = false,
    bool isGenerationTimeout = false,
    bool isNetworkIssue = false,
    bool isModelUnsupported = false,
    this.sanitizedDetail,
  }) : _explicitApiKey = isApiKeyIssue,
       _explicitQuota = isQuotaIssue,
       _explicitBilling = isBillingIssue,
       _explicitRateLimit = isRateLimitIssue,
       _explicitTimeout = isTimeout || isConnectionTimeout || isGenerationTimeout,
       _explicitConnectionTimeout = isConnectionTimeout,
       _explicitGenerationTimeout = isGenerationTimeout,
       _explicitNetwork = isNetworkIssue,
       _explicitUnsupported = isModelUnsupported;

  final bool _explicitApiKey;
  final bool _explicitQuota;
  final bool _explicitBilling;
  final bool _explicitRateLimit;
  final bool _explicitTimeout;
  final bool _explicitConnectionTimeout;
  final bool _explicitGenerationTimeout;
  final bool _explicitNetwork;
  final bool _explicitUnsupported;

  bool get isApiKeyIssue =>
      _explicitApiKey || category == ImageGenerationErrorCategory.auth;

  bool get isBillingIssue =>
      _explicitBilling || category == ImageGenerationErrorCategory.billing;

  bool get isQuotaIssue =>
      _explicitQuota || category == ImageGenerationErrorCategory.quota;

  bool get isRateLimitIssue =>
      _explicitRateLimit || category == ImageGenerationErrorCategory.rateLimit;

  bool get isTimeout =>
      _explicitTimeout || (category == ImageGenerationErrorCategory.network && statusCode == 504);

  bool get isConnectionTimeout =>
      _explicitConnectionTimeout ||
      (_explicitTimeout && statusCode == 504 && sanitizedDetail != null && sanitizedDetail!.contains('connection'));

  bool get isGenerationTimeout =>
      _explicitGenerationTimeout ||
      (isTimeout && !_explicitConnectionTimeout);

  bool get isNetworkIssue =>
      _explicitNetwork || _explicitTimeout || category == ImageGenerationErrorCategory.network;

  bool get isModelUnsupported =>
      _explicitUnsupported || category == ImageGenerationErrorCategory.unsupported;

  bool get isServerIssue =>
      category == ImageGenerationErrorCategory.server ||
      category == ImageGenerationErrorCategory.provider;

  @override
  String toString() =>
      'ImageGenerationException(category: ${category.name}, status: $statusCode, provider: $provider): $message';
}
