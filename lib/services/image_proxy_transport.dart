import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/image_reference.dart';
import 'ai_service.dart';

/// Metadata regarding proxy URI resolution for diagnostics and verification.
class ProxyResolutionInfo {
  final Uri? uri;
  final String source;
  final bool isExplicit;
  final bool isSearchFallback;

  const ProxyResolutionInfo({
    required this.uri,
    required this.source,
    required this.isExplicit,
    required this.isSearchFallback,
  });
}

/// Production-grade HTTP transport for communicating with the server-side
/// image generation proxy endpoint (`/api/generate-image`).
///
/// Features:
/// - Environment-aware URI resolution (Web, Android Emulator, and Physical devices)
/// - Multi-modal reference image encoding for character portraits
/// - Safe diagnostic logging (never logs credentials, tokens, or raw image payloads)
/// - Structured exception handling with distinct status codes and failure categories
class BackendProxyImageTransport {
  String? _configuredEndpoint;
  String? _serverBaseUrl;
  String? _fallbackServerUrl;
  final Duration timeout;
  final Duration connectionTimeout;
  final http.Client _client;
  final String? authToken;

  BackendProxyImageTransport({
    String? proxyEndpoint,
    String? serverBaseUrl,
    String? fallbackServerUrl,
    this.timeout = const Duration(seconds: 120),
    this.connectionTimeout = const Duration(seconds: 20),
    http.Client? client,
    this.authToken,
  })  : _configuredEndpoint = proxyEndpoint?.trim(),
        _serverBaseUrl = serverBaseUrl?.trim(),
        _fallbackServerUrl = fallbackServerUrl?.trim(),
        _client = client ?? http.Client();

  /// Updates the proxy endpoint at runtime.
  void setProxyEndpoint(String? endpoint) {
    _configuredEndpoint = endpoint?.trim().isEmpty ?? true ? null : endpoint?.trim();
  }

  /// Updates the server base URL at runtime.
  void setServerBaseUrl(String? serverUrl) {
    _serverBaseUrl = serverUrl?.trim().isEmpty ?? true ? null : serverUrl?.trim();
  }

  /// Updates the fallback server URL at runtime.
  void setFallbackServerUrl(String? serverUrl) {
    _fallbackServerUrl = serverUrl?.trim().isEmpty ?? true ? null : serverUrl?.trim();
  }

  String? get configuredEndpoint => _configuredEndpoint;
  String? get serverBaseUrl => _serverBaseUrl;
  String? get fallbackServerUrl => _fallbackServerUrl;

  Uri? get proxyUri => resolveTargetUri();

  /// Resolves the effective target URI based on runtime environment.
  Uri? resolveTargetUri() => resolveTargetUriInfo().uri;

  /// Resolves target URI and attributes the source for diagnostic tracking.
  ProxyResolutionInfo resolveTargetUriInfo() {
    final endpoint = _configuredEndpoint;

    // 1. Explicit Absolute URI provided for image proxy (http:// or https://)
    if (endpoint != null && endpoint.isNotEmpty) {
      final parsed = _normalizeProxyUri(endpoint.trim());
      if (parsed != null) {
        return ProxyResolutionInfo(
          uri: parsed,
          source: 'explicit_image_setting',
          isExplicit: true,
          isSearchFallback: false,
        );
      }
    }

    // 2. Server Base URL setting (e.g. https://your-server.run.app or http://192.168.1.50:3000)
    if (_serverBaseUrl != null && _serverBaseUrl!.isNotEmpty) {
      final parsedBase = _normalizeProxyUri(_serverBaseUrl!.trim());
      if (parsedBase != null) {
        return ProxyResolutionInfo(
          uri: parsedBase,
          source: 'server_base_url_setting',
          isExplicit: true,
          isSearchFallback: false,
        );
      }
    }

    // 3. Check compile-time environment variables
    const envProxy = String.fromEnvironment('IMAGE_PROXY_ENDPOINT', defaultValue: '');
    if (envProxy.isNotEmpty) {
      final parsedEnv = _normalizeProxyUri(envProxy.trim());
      if (parsedEnv != null) {
        return ProxyResolutionInfo(
          uri: parsedEnv,
          source: 'env_image_proxy',
          isExplicit: false,
          isSearchFallback: false,
        );
      }
    }

    const envServerBase = String.fromEnvironment('SERVER_BASE_URL', defaultValue: '');
    if (envServerBase.isNotEmpty) {
      final parsedServerEnv = _normalizeProxyUri(envServerBase.trim());
      if (parsedServerEnv != null) {
        return ProxyResolutionInfo(
          uri: parsedServerEnv,
          source: 'env_server_base_url',
          isExplicit: false,
          isSearchFallback: false,
        );
      }
    }

    // 4. Fallback to base host from search proxy or general server URL if available
    if (_fallbackServerUrl != null && _fallbackServerUrl!.isNotEmpty) {
      final parsedFallback = _normalizeProxyUri(_fallbackServerUrl!.trim());
      if (parsedFallback != null) {
        return ProxyResolutionInfo(
          uri: parsedFallback,
          source: 'search_fallback',
          isExplicit: false,
          isSearchFallback: true,
        );
      }
    }

    const envSearchProxy = String.fromEnvironment('SEARCH_PROXY_ENDPOINT', defaultValue: '');
    if (envSearchProxy.isNotEmpty) {
      final parsedSearchEnv = _normalizeProxyUri(envSearchProxy.trim());
      if (parsedSearchEnv != null) {
        return ProxyResolutionInfo(
          uri: parsedSearchEnv,
          source: 'env_search_fallback',
          isExplicit: false,
          isSearchFallback: true,
        );
      }
    }

    // 5. Web Platform: Relative /api/generate-image resolves to current origin
    if (kIsWeb) {
      return ProxyResolutionInfo(
        uri: Uri.base.resolve('/api/generate-image'),
        source: 'web_origin',
        isExplicit: false,
        isSearchFallback: false,
      );
    }

    // 6. Android Emulator in Debug mode fallback
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && kDebugMode) {
      if (endpoint != null && endpoint.startsWith('/') && !endpoint.startsWith('//')) {
        return ProxyResolutionInfo(
          uri: Uri.parse('http://10.0.2.2:3000$endpoint'),
          source: 'android_emulator_debug',
          isExplicit: false,
          isSearchFallback: false,
        );
      }
      return const ProxyResolutionInfo(
        uri: null,
        source: 'unconfigured_physical_device',
        isExplicit: false,
        isSearchFallback: false,
      );
    }

    // 7. Physical Android/iOS Device without configured server endpoint
    return const ProxyResolutionInfo(
      uri: null,
      source: 'unconfigured',
      isExplicit: false,
      isSearchFallback: false,
    );
  }

  /// Normalizes server endpoints to ensure `/api/generate-image` is cleanly mounted.
  Uri? _normalizeProxyUri(String rawUrl) {
    var trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    // Auto-prepend http:// or https:// if scheme was omitted by user
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      if (trimmed.startsWith('/')) {
        return null; // Leave relative paths for platform-specific resolution
      }
      // If it looks like a cloud domain (.run.app, .com, .org, .io), default to https
      final isCloudDomain = trimmed.contains('.run.app') ||
          trimmed.contains('.app') ||
          (trimmed.contains('.') && !trimmed.contains(':') && !RegExp(r'^\d+\.').hasMatch(trimmed));
      trimmed = isCloudDomain ? 'https://$trimmed' : 'http://$trimmed';
    }

    var uri = Uri.tryParse(trimmed);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return null;
    }

    var path = uri.path.trim();
    while (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }

    if (path.isEmpty || path == '/') {
      path = '/api/generate-image';
    } else if (path.endsWith('/api/search')) {
      path = '${path.substring(0, path.length - '/api/search'.length)}/api/generate-image';
    } else if (path.endsWith('/api/generate-image')) {
      // Already ends with /api/generate-image, retain without duplicating
      path = path;
    } else {
      path = '$path/api/generate-image';
    }

    // Remove any accidental duplicate slashes in path
    path = path.replaceAll(RegExp(r'/+'), '/');

    return uri.replace(path: path, query: null, fragment: null);
  }

  /// Executes an image generation request against the backend proxy.
  Future<String> generateImage(
    String prompt, {
    List<ImageReference>? referenceImages,
    String? characterId,
    String? aspectRatio = '1:1',
    String? provider,
  }) async {
    final resolution = resolveTargetUriInfo();
    final targetUri = resolution.uri;
    if (targetUri == null) {
      debugPrint('[IMAGE_DIAGNOSTIC] Proxy unconfigured for this environment (source: ${resolution.source}).');
      final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      final msg = isAndroid
          ? 'Backend image proxy endpoint is not configured for this Android device. Please configure your server URL (e.g. http://192.168.x.x:3000) in Settings.'
          : 'Backend image proxy endpoint is not configured for this device/environment. Please configure the server URL in Settings.';
      throw ImageGenerationException(
        msg,
        statusCode: 0,
        provider: 'backend_proxy',
        category: ImageGenerationErrorCategory.validation,
      );
    }

    final safeOrigin = '${targetUri.scheme}://${targetUri.host}:${targetUri.port}';
    final safeTargetUrl = targetUri.toString();
    final effectiveBase = _serverBaseUrl ?? _fallbackServerUrl ?? safeOrigin;
    debugPrint(
      '[IMAGE_PROXY_URL] base=$effectiveBase endpoint=$safeTargetUrl (source: ${resolution.source}, explicitSetting: ${resolution.isExplicit}, searchFallback: ${resolution.isSearchFallback})',
    );

    final refList = <Map<String, String>>[];
    if (referenceImages != null && referenceImages.isNotEmpty) {
      for (final ref in referenceImages) {
        refList.add({
          'mimeType': ref.mimeType,
          'data': base64Encode(ref.bytes),
        });
      }
    }

    final payload = {
      'prompt': prompt,
      'aspectRatio': aspectRatio ?? '1:1',
      if (refList.isNotEmpty) 'referenceImages': refList,
      if (characterId != null) 'characterId': characterId,
      if (provider != null) 'provider': provider,
    };

    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      if (authToken != null) 'Authorization': 'Bearer $authToken',
    };

    debugPrint(
      '[IMAGE_PROXY_REQUEST] POST $safeTargetUrl (Prompt length: ${prompt.length} chars, AspectRatio: ${aspectRatio ?? "1:1"}, RefImages: ${refList.length}, Character: ${characterId ?? "none"})',
    );

    final stopwatch = Stopwatch()..start();
    http.StreamedResponse streamedResponse;

    try {
      final request = http.Request('POST', targetUri);
      request.headers.addAll(headers);
      request.body = jsonEncode(payload);

      streamedResponse = await _client.send(request).timeout(connectionTimeout);
      debugPrint(
        '[IMAGE_PROXY_RESPONSE] Connection opened -> status: HTTP ${streamedResponse.statusCode}, connectionDuration: ${stopwatch.elapsedMilliseconds}ms',
      );
    } on TimeoutException {
      debugPrint(
        '[IMAGE_GENERATION_TIMEOUT] Connection timed out after ${connectionTimeout.inSeconds}s connecting to $safeOrigin',
      );
      throw ImageGenerationException(
        'Connection timed out while reaching the image service at ${targetUri.host}. Please check server connectivity.',
        statusCode: 504,
        category: ImageGenerationErrorCategory.network,
        isConnectionTimeout: true,
        provider: 'backend_proxy',
      );
    } catch (connErr) {
      debugPrint('[IMAGE_GENERATION_FAILURE] Network connection to $safeOrigin failed: $connErr');
      final isLocalhost = targetUri.host == 'localhost' || targetUri.host == '127.0.0.1';
      final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      String diagnosticMsg;
      if (isLocalhost && isAndroid) {
        diagnosticMsg = 'Cannot reach localhost on Android device. Please configure your computer\'s Wi-Fi IP (e.g. http://192.168.x.x:3000) in Settings, or run "adb reverse tcp:3000 tcp:3000".';
      } else {
        diagnosticMsg = 'Network error connecting to image service at $safeOrigin: $connErr';
      }
      throw ImageGenerationException(
        diagnosticMsg,
        statusCode: 503,
        category: ImageGenerationErrorCategory.network,
        isNetworkIssue: true,
        provider: 'backend_proxy',
      );
    }

    http.Response response;
    try {
      final remainingBudget = timeout - stopwatch.elapsed;
      final effectiveReadTimeout = remainingBudget > const Duration(seconds: 15)
          ? remainingBudget
          : const Duration(seconds: 90);

      response = await http.Response.fromStream(streamedResponse).timeout(effectiveReadTimeout);
      debugPrint(
        '[IMAGE_PROXY_RESPONSE] Body received -> status: HTTP ${response.statusCode}, duration: ${stopwatch.elapsedMilliseconds}ms, payloadBytes: ${response.bodyBytes.length}',
      );
    } on TimeoutException {
      debugPrint(
        '[IMAGE_GENERATION_TIMEOUT] Image generation timed out waiting for backend rendering after ${stopwatch.elapsed.inSeconds}s',
      );
      throw ImageGenerationException(
        'Image generation timed out waiting for backend rendering.',
        statusCode: 504,
        category: ImageGenerationErrorCategory.network,
        isGenerationTimeout: true,
        provider: 'backend_proxy',
      );
    } catch (readErr) {
      debugPrint('[IMAGE_GENERATION_FAILURE] Reading response stream failed: $readErr');
      throw ImageGenerationException(
        'Failed reading image response from server: $readErr',
        statusCode: 502,
        category: ImageGenerationErrorCategory.network,
        isNetworkIssue: true,
        provider: 'backend_proxy',
      );
    }

    try {
      Map<String, dynamic>? responseData;
      try {
        if (response.body.isNotEmpty) {
          responseData = jsonDecode(response.body) as Map<String, dynamic>?;
        }
      } catch (_) {
        // Non-JSON response body handled below
      }

      if (response.statusCode == 200) {
        final success = responseData?['success'] as bool? ?? false;
        final imageUrl = responseData?['imageUrl'] as String?;

        if (success && imageUrl != null && imageUrl.isNotEmpty) {
          // Verify it is not an SVG placeholder
          if (imageUrl.startsWith('data:image/svg') || imageUrl.contains('<svg')) {
            throw const ImageGenerationException(
              'Backend proxy returned vector SVG rather than supported raster image format.',
              statusCode: 502,
              provider: 'backend_proxy',
              category: ImageGenerationErrorCategory.provider,
            );
          }
          final mimePrefix = imageUrl.startsWith('data:') && imageUrl.contains(';')
              ? imageUrl.substring(5, imageUrl.indexOf(';'))
              : 'raster';
          debugPrint(
            '[IMAGE_GENERATION_SUCCESS] Image received successfully (Length: ${imageUrl.length} chars, MIME: $mimePrefix, Total duration: ${stopwatch.elapsedMilliseconds}ms)',
          );
          return imageUrl;
        }

        final errorMsg = responseData?['error'] as String? ?? 'Image generation returned empty image data.';
        throw ImageGenerationException(
          errorMsg,
          statusCode: 200,
          provider: responseData?['provider'] as String? ?? 'backend_proxy',
          category: ImageGenerationErrorCategory.provider,
          sanitizedDetail: responseData?['details'] as String?,
        );
      }

      // Parse structured failure response from proxy
      final errorMessage = responseData?['error'] as String? ?? 'Image proxy returned HTTP ${response.statusCode}';
      final categoryRaw = responseData?['category'] as String?;
      final providerName = responseData?['provider'] as String? ?? 'backend_proxy';
      final detail = responseData?['details'] as String?;

      var category = ImageGenerationErrorCategory.fromString(categoryRaw);
      if (category == ImageGenerationErrorCategory.unknown) {
        if (response.statusCode == 429) {
          category = ImageGenerationErrorCategory.quota;
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          category = ImageGenerationErrorCategory.auth;
        } else if (response.statusCode == 504) {
          category = ImageGenerationErrorCategory.network;
        } else if (response.statusCode >= 500) {
          category = ImageGenerationErrorCategory.provider;
        }
      }

      final isSpendCap = category == ImageGenerationErrorCategory.billing ||
          (detail != null && detail.toLowerCase().contains('spend cap'));

      throw ImageGenerationException(
        errorMessage,
        statusCode: response.statusCode,
        provider: providerName,
        category: category,
        isBillingIssue: isSpendCap,
        sanitizedDetail: detail,
      );
    } on ImageGenerationException {
      rethrow;
    } catch (e) {
      debugPrint('[IMAGE_GENERATION_FAILURE] Error parsing response: $e');
      throw ImageGenerationException(
        'Unexpected error processing image response: $e',
        statusCode: 500,
        category: ImageGenerationErrorCategory.provider,
        provider: 'backend_proxy',
      );
    }
  }
}
