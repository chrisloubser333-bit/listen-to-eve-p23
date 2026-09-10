import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ai_service.dart';

/// Exceptions raised during Gemini operations with user-safe descriptions.
class GeminiException implements Exception {
  final String message;
  final int? statusCode;

  const GeminiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class GeminiApiKeyMissingException extends GeminiException {
  const GeminiApiKeyMissingException()
      : super('Gemini API key is not set. Please configure your key in Settings.');
}

class GeminiAuthenticationException extends GeminiException {
  const GeminiAuthenticationException(super.message, {super.statusCode});
}

class GeminiRateLimitException extends GeminiException {
  const GeminiRateLimitException(super.message, {super.statusCode});
}

class GeminiServerException extends GeminiException {
  const GeminiServerException(super.message, {super.statusCode});
}

class GeminiNetworkException extends GeminiException {
  const GeminiNetworkException(super.message, {super.statusCode});
}

class GeminiApiException extends GeminiException {
  const GeminiApiException(super.message, {super.statusCode});
}

/// Handles communication with the Google Gemini Generative Language API.
///
/// Implements [AiService] so that Gemini can be swapped in seamlessly
/// without altering character personas, memory retrieval, or conversation history.
class GeminiService implements AiService {
  /// Default isolated model configuration.
  static const String defaultModel = 'gemini-3.6-flash';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  final String model;
  final http.Client _client;
  final Duration requestTimeout;

  String? _apiKey;

  GeminiService({
    this.model = defaultModel,
    this.requestTimeout = const Duration(seconds: 45),
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  void setApiKey(String key) {
    _apiKey = key.trim();
  }

  @override
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  @override
  Future<String> chatCompletion({
    required List<Map<String, String>> messages,
    String? systemPrompt,
    String? modelOverride,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async {
    if (!hasApiKey) {
      throw const GeminiApiKeyMissingException();
    }

    if (messages.isEmpty) {
      throw const GeminiApiException(
          'Cannot generate completion with an empty messages list.');
    }

    final activeModel = modelOverride ?? model;
    final uri = Uri.parse('$_baseUrl/models/$activeModel:generateContent');

    // Prepare multiturn conversation contents conforming to Gemini API rules:
    // 1. Roles are 'user' and 'model'.
    // 2. Turns must alternate; consecutive turns with the same role are combined.
    // 3. Conversation must start with a 'user' turn and end with a 'user' turn.
    // 4. System messages are absorbed into system_instruction, never converted to user turns.
    String? effectiveSystemPrompt = systemPrompt;
    final List<Map<String, dynamic>> contents = [];

    for (final msg in messages) {
      final rawRole = msg['role']?.toLowerCase() ?? 'user';
      final text = msg['content']?.trim() ?? '';
      if (text.isEmpty) continue;

      if (rawRole == 'system') {
        if (effectiveSystemPrompt == null || effectiveSystemPrompt.isEmpty) {
          effectiveSystemPrompt = text;
        } else {
          effectiveSystemPrompt = '$effectiveSystemPrompt\n\n$text';
        }
        continue;
      }

      final mappedRole =
          (rawRole == 'assistant' || rawRole == 'model') ? 'model' : 'user';

      if (contents.isNotEmpty && contents.last['role'] == mappedRole) {
        final parts = contents.last['parts'] as List<Map<String, dynamic>>;
        parts.add({'text': text});
      } else {
        contents.add({
          'role': mappedRole,
          'parts': [
            {'text': text}
          ],
        });
      }
    }

    // Ensure the conversation starts with a 'user' turn for API compatibility
    if (contents.isNotEmpty && contents.first['role'] == 'model') {
      contents.insert(0, {
        'role': 'user',
        'parts': [
          {'text': 'Hello'}
        ],
      });
    }

    // Ensure the conversation ends with a 'user' turn for generateContent
    if (contents.isNotEmpty && contents.last['role'] == 'model') {
      contents.add({
        'role': 'user',
        'parts': [
          {'text': 'Please continue.'}
        ],
      });
    }

    if (contents.isEmpty) {
      throw const GeminiApiException('All provided messages were empty.');
    }

    final Map<String, dynamic> body = {
      'contents': contents,
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
      },
    };

    if (effectiveSystemPrompt != null &&
        effectiveSystemPrompt.trim().isNotEmpty) {
      body['system_instruction'] = {
        'parts': [
          {'text': effectiveSystemPrompt.trim()}
        ],
      };
    }

    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': _apiKey!,
    };

    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const GeminiNetworkException(
          'Connection to Gemini API timed out. Please check your connection.');
    } catch (e) {
      if (e is GeminiException) rethrow;
      throw GeminiNetworkException('Network error contacting Gemini: $e');
    }

    if (response.statusCode != 200) {
      String errorMessage = 'HTTP ${response.statusCode}';
      try {
        final errJson = jsonDecode(response.body);
        if (errJson is Map && errJson['error'] is Map) {
          final errorObj = errJson['error'] as Map;
          errorMessage = errorObj['message'] ?? errorMessage;
        }
      } catch (_) {
        if (response.body.isNotEmpty) {
          errorMessage = response.body;
        }
      }

      if (response.statusCode == 400 ||
          response.statusCode == 401 ||
          response.statusCode == 403) {
        final lowerMsg = errorMessage.toLowerCase();
        if (lowerMsg.contains('api key') ||
            lowerMsg.contains('credential') ||
            lowerMsg.contains('unauthorized') ||
            lowerMsg.contains('permission') ||
            lowerMsg.contains('forbidden') ||
            lowerMsg.contains('unregistered') ||
            lowerMsg.contains('unauthenticated')) {
          throw GeminiAuthenticationException(
            'Invalid or unauthorized Gemini API key. Please check your key in Settings.',
            statusCode: response.statusCode,
          );
        }
      } else if (response.statusCode == 429) {
        throw GeminiRateLimitException(
          'Gemini rate limit exceeded. Please wait a moment before trying again.',
          statusCode: 429,
        );
      } else if (response.statusCode >= 500) {
        throw GeminiServerException(
          'Gemini service temporarily unavailable (${response.statusCode}). Please try again later.',
          statusCode: response.statusCode,
        );
      }

      throw GeminiApiException(
        'Gemini API error ($errorMessage)',
        statusCode: response.statusCode,
      );
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;

      if (candidates == null || candidates.isEmpty) {
        final promptFeedback = data['promptFeedback'];
        if (promptFeedback is Map && promptFeedback['blockReason'] != null) {
          throw GeminiApiException(
            'Gemini blocked the response: ${promptFeedback['blockReason']}',
            statusCode: 200,
          );
        }
        throw const GeminiApiException('Gemini returned an empty response.');
      }

      final firstCandidate = candidates.first as Map<String, dynamic>;
      final content = firstCandidate['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;

      if (parts == null || parts.isEmpty) {
        final finishReason = firstCandidate['finishReason'] ?? 'UNKNOWN';
        throw GeminiApiException(
          'Gemini completed without text content (finish reason: $finishReason).',
          statusCode: 200,
        );
      }

      final buffer = StringBuffer();
      for (final part in parts) {
        if (part is Map<String, dynamic> && part['text'] != null) {
          buffer.write(part['text']);
        }
      }

      final resultText = buffer.toString().trim();
      if (resultText.isEmpty) {
        throw const GeminiApiException('Gemini returned empty text content.');
      }

      return resultText;
    } on GeminiException {
      rethrow;
    } catch (e) {
      throw GeminiApiException('Failed to parse Gemini response: $e');
    }
  }

  @override
  void disconnectRealtime() {
    // Realtime voice for Gemini will be integrated via Live API in future tasks.
    // Provider-safe no-op to fulfill the AiService contract without side effects.
  }
}
