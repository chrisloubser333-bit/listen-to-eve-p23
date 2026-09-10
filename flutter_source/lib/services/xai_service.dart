import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'ai_service.dart';

/// Handles communication with xAI Grok APIs (Chat + Voice).
///
/// For production you should NEVER hard-code the API key in the mobile app.
/// Use ephemeral tokens issued by a small backend instead.
class XaiService implements AiService {
  static const String _baseUrl = 'https://api.x.ai/v1';
  static const String _realtimeUrl = 'wss://api.x.ai/v1/realtime';

  String? _apiKey;
  WebSocketChannel? _ws;
  StreamController<Map<String, dynamic>>? _eventController;

  @override
  void setApiKey(String key) {
    _apiKey = key.trim();
  }

  @override
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  // ---------------------------------------------------------------
  // Text Chat (fallback / hybrid mode)
  // ---------------------------------------------------------------
  @override
  Future<String> chatCompletion({
    required List<Map<String, String>> messages,
    String model = 'grok-4.6',
    String? systemPrompt,
  }) async {
    if (!hasApiKey) throw Exception('API key not set');

    final body = {
      'model': model,
      'messages': [
        if (systemPrompt != null)
          {'role': 'system', 'content': systemPrompt},
        ...messages,
      ],
      'stream': false,
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode(body),
    );

    print('STATUS CODE: ${response.statusCode}');
    print('RESPONSE BODY: ${response.body}');
    
    if (response.statusCode != 200) {
      throw Exception('xAI error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['choices'][0]['message']['content'] as String;
  }

  // ---------------------------------------------------------------
  // Text-to-Speech (standalone)
  // ---------------------------------------------------------------
  Future<List<int>> textToSpeech({
    required String text,
    required String voiceId,
    String language = 'en',
  }) async {
    if (!hasApiKey) throw Exception('API key not set');

    final response = await http.post(
      Uri.parse('$_baseUrl/tts'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'text': text,
        'voice_id': voiceId,
        'language': language,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('TTS error ${response.statusCode}: ${response.body}');
    }

    return response.bodyBytes;
  }

  // ---------------------------------------------------------------
  // Realtime Voice WebSocket (core of the voice experience)
  // ---------------------------------------------------------------
  Stream<Map<String, dynamic>> connectRealtime({
    required String voiceId,
    required String instructions,
    String model = 'grok-voice-latest',
  }) {
    if (!hasApiKey) throw Exception('API key not set');

    _eventController?.close();
    _eventController = StreamController<Map<String, dynamic>>.broadcast();

    final uri = Uri.parse('$_realtimeUrl?model=$model');
    _ws = WebSocketChannel.connect(
      uri,
      protocols: null, // headers via additionalHeaders not directly supported in all packages
    );

    // Note: web_socket_channel does not easily support custom headers on all platforms.
    // For production use a package that supports headers or route through a backend
    // that issues ephemeral tokens and connects on behalf of the client.
    //
    // Temporary approach for development: many developers use a thin proxy.

    _ws!.stream.listen(
      (data) {
        try {
          final event = jsonDecode(data as String) as Map<String, dynamic>;
          _eventController?.add(event);
        } catch (e) {
          _eventController?.addError(e);
        }
      },
      onError: (e) => _eventController?.addError(e),
      onDone: () => _eventController?.close(),
    );

    // Configure session after connection
    Future.delayed(const Duration(milliseconds: 300), () {
      sendEvent({
        'type': 'session.update',
        'session': {
          'voice': voiceId,
          'instructions': instructions,
          'turn_detection': {'type': 'server_vad'},
          'audio': {
            'input': {
              'format': {'type': 'audio/pcm', 'rate': 24000}
            },
            'output': {
              'format': {'type': 'audio/pcm', 'rate': 24000}
            },
          },
        },
      });
    });

    return _eventController!.stream;
  }

  void sendEvent(Map<String, dynamic> event) {
    _ws?.sink.add(jsonEncode(event));
  }

  void sendAudioChunk(List<int> pcmBytes) {
    // In real implementation encode to base64 and send as
    // {'type': 'input_audio_buffer.append', 'audio': base64}
    // or use binary transport if configured.
  }

  void commitAudio() {
    sendEvent({'type': 'input_audio_buffer.commit'});
  }

  void createResponse() {
    sendEvent({'type': 'response.create'});
  }

  @override
  void disconnectRealtime() {
    _ws?.sink.close();
    _ws = null;
    _eventController?.close();
    _eventController = null;
  }

  // ---------------------------------------------------------------
  // Custom Voice helpers
  // ---------------------------------------------------------------
  Future<Map<String, dynamic>> createCustomVoice({
    required List<int> audioBytes,
    required String name,
    String language = 'en',
    String gender = 'neutral',
    String tone = 'friendly',
  }) async {
    if (!hasApiKey) throw Exception('API key not set');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/custom-voices'),
    );
    request.headers['Authorization'] = 'Bearer $_apiKey';
    request.fields['name'] = name;
    request.fields['language'] = language;
    request.fields['gender'] = gender;
    request.fields['tone'] = tone;
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      audioBytes,
      filename: 'reference.wav',
    ));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(
          'Custom voice error ${response.statusCode}: ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listCustomVoices() async {
    if (!hasApiKey) throw Exception('API key not set');

    final response = await http.get(
      Uri.parse('$_baseUrl/custom-voices'),
      headers: {'Authorization': 'Bearer $_apiKey'},
    );

    if (response.statusCode != 200) {
      throw Exception('List voices error: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return List<Map<String, dynamic>>.from(data['voices'] ?? []);
  }
}
