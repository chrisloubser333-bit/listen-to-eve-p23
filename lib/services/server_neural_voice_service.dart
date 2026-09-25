import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'voice_generation_service.dart';

/// Cloud Run Server-Side Neural Voice Synthesis Provider.
///
/// Dispatches speech synthesis requests to the secure backend proxy endpoint
/// `<server_base_url>/api/voice/synthesize`, which authenticates to Google Cloud
/// Text-to-Speech using server-side Application Default Credentials or API keys.
///
/// Zero cloud credentials, service accounts, or API keys are stored in the client.
class ServerNeuralVoiceGenerationService implements VoiceGenerationService {
  String? _serverBaseUrl;
  http.Client? _activeHttpClient;
  int _activeRequestId = 0;

  ServerNeuralVoiceGenerationService({String? serverBaseUrl})
      : _serverBaseUrl = _normalizeBaseUrl(serverBaseUrl);

  /// Updates the server base URL when changed in settings.
  void setServerBaseUrl(String? url) {
    _serverBaseUrl = _normalizeBaseUrl(url);
  }

  static String? _normalizeBaseUrl(String? rawUrl) {
    if (rawUrl == null) return null;
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  /// Resolves the absolute or relative URI for the voice synthesis route.
  Uri? resolveEndpointUri() {
    if (_serverBaseUrl != null && _serverBaseUrl!.isNotEmpty) {
      final base = _serverBaseUrl!;
      if (base.endsWith('/api/voice/synthesize')) {
        return Uri.tryParse(base);
      }
      return Uri.tryParse('$base/api/voice/synthesize');
    }

    if (kIsWeb) {
      // In browser preview, relative resolution against window origin is safe
      return Uri.base.resolve('/api/voice/synthesize');
    }

    // On physical Android without server_base_url configured, return null to trigger graceful fallback
    return null;
  }

  @override
  Future<GeneratedAudio?> synthesize(
    String text, {
    required CharacterVoiceProfile profile,
    VoiceSettings settings = const VoiceSettings(),
    String? cancellationToken,
  }) async {
    final targetUri = resolveEndpointUri();
    if (targetUri == null) {
      debugPrint(
        '[ServerNeuralVoice] Server base URL unconfigured on native device. Falling back to device TTS.',
      );
      return null;
    }

    final requestId = ++_activeRequestId;
    final client = http.Client();
    _activeHttpClient = client;

    final lang = settings.languageCode.startsWith('af') ? 'af' : 'en';
    final payload = jsonEncode({
      'text': text,
      'characterId': profile.characterId,
      'language': lang,
      'voiceId': profile.neuralVoiceId,
      'speed': settings.speedMultiplier,
      'pitch': 0.0,
    });

    debugPrint(
      '[NEURAL_VOICE_REQUEST] Target: $targetUri | Char: ${profile.characterId} | Voice: ${profile.neuralVoiceId} | Lang: $lang | Len: ${text.length}',
    );

    try {
      final response = await client
          .post(
            targetUri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'audio/mpeg, application/json',
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 12));

      // Guard against stale requests that completed after an interruption
      if (requestId != _activeRequestId) {
        debugPrint('[ServerNeuralVoice] Discarding response for canceled requestId: $requestId');
        return null;
      }

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        if (bytes.isNotEmpty) {
          final returnedVoice = response.headers['x-voice-id'] ?? profile.neuralVoiceId;
          debugPrint(
            '[NEURAL_VOICE_RESPONSE] Received ${bytes.lengthInBytes} audio bytes | Voice: $returnedVoice',
          );

          return GeneratedAudio(
            bytes: bytes,
            mimeType: 'audio/mpeg',
            provider: 'google_cloud_tts_gateway',
            voiceId: returnedVoice,
          );
        } else {
          debugPrint('[ServerNeuralVoice] Synthesis returned empty byte buffer.');
          return null;
        }
      } else {
        debugPrint(
          '[ServerNeuralVoice] Backend returned HTTP ${response.statusCode}: ${response.body}',
        );
        return null;
      }
    } catch (e) {
      if (requestId == _activeRequestId) {
        debugPrint('[ServerNeuralVoice] Network or dispatch error: $e');
      }
      return null;
    } finally {
      if (_activeHttpClient == client) {
        _activeHttpClient = null;
      }
      client.close();
    }
  }

  @override
  Future<void> stop() async {
    _activeRequestId++;
    try {
      _activeHttpClient?.close();
      _activeHttpClient = null;
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
