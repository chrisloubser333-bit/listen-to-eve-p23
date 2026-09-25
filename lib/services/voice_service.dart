import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'local_voice_cache_manager.dart';
import 'voice_generation_service.dart';
import 'server_neural_voice_service.dart';

/// Manages Speech-To-Text (STT), Neural Audio Streaming (via JustAudio),
/// Disk-Backed Voice Caching (via LocalVoiceCacheManager), and Text-To-Speech (TTS) for Listen to Eve.
///
/// Implements:
/// - Disk-backed deterministic SHA-256 caching layer for zero-latency audio playback.
/// - Background isolate string sanitization and hash computation (`Isolate.run`).
/// - Server-Side Google Cloud Text-to-Speech synthesis gateway as PRIMARY voice path.
/// - JustAudio MP3 playback.
/// - Resilient fallback to DeviceTtsVoiceGenerationService (flutter_tts).
/// - Continuous listening with configurable silence pause duration (1.0s - 3.0s).
/// - Automatic dispatch after silence.
/// - Character-specific speech synthesis with distinct pitch, rate, and vocal cadence.
/// - Cancellation token / request ID tracking for instantaneous barge-in / interruption.
/// - Bilingual support (English and Afrikaans).
/// - Graceful fallback when platform audio hardware/services are restricted.
class VoiceService {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ServerNeuralVoiceGenerationService _serverNeuralVoiceService =
      ServerNeuralVoiceGenerationService();
  late final DeviceTtsVoiceGenerationService _deviceTtsVoiceService;

  bool _isSttInitialized = false;
  bool _isTtsInitialized = false;
  bool _isListening = false;
  bool _isSpeaking = false;

  Timer? _silenceTimer;
  String _currentWords = '';
  int _activeSpeechRequestId = 0;
  String? _serverStreamingGateway;

  // Callbacks
  Function(String words)? onPartialText;
  Function(String finalWords)? onSpeechCompleted;
  Function(bool isListening)? onListeningStateChanged;
  Function(bool isSpeaking)? onSpeakingStateChanged;

  VoiceService({String? serverStreamingGateway, String? serverBaseUrl}) {
    final effectiveUrl = serverBaseUrl ?? serverStreamingGateway;
    if (effectiveUrl != null && effectiveUrl.trim().isNotEmpty) {
      setServerBaseUrl(effectiveUrl);
    }
    _deviceTtsVoiceService = DeviceTtsVoiceGenerationService(
      speakFunction: ({
        required String text,
        required String characterId,
        required String language,
        double speedMultiplier = 0.85,
      }) async {
        final profile = CharacterVoiceProfile.forCharacter(characterId);
        await _speakViaTts(
          cleanText: text,
          characterId: characterId,
          language: language,
          speedMultiplier: speedMultiplier,
          currentRequestId: _activeSpeechRequestId,
          profile: profile,
        );
      },
      stopFunction: _stopActiveEngines,
    );
    _initTts();
    _initAudioPlayer();
  }

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  int get activeSpeechRequestId => _activeSpeechRequestId;

  void setServerBaseUrl(String? url) {
    _serverStreamingGateway = (url != null && url.trim().isNotEmpty) ? url.trim() : null;
    _serverNeuralVoiceService.setServerBaseUrl(url);
  }

  void setServerStreamingGateway(String? gateway) {
    setServerBaseUrl(gateway);
  }

  void _initAudioPlayer() {
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _isSpeaking = false;
        onSpeakingStateChanged?.call(false);
      }
    });
  }

  List<dynamic>? _availableVoices;

  Future<void> _initTts() async {
    try {
      await _flutterTts.awaitSpeakCompletion(true);
      _flutterTts.setStartHandler(() {
        _isSpeaking = true;
        onSpeakingStateChanged?.call(true);
      });
      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        onSpeakingStateChanged?.call(false);
      });
      _flutterTts.setCancelHandler(() {
        _isSpeaking = false;
        onSpeakingStateChanged?.call(false);
      });
      _flutterTts.setErrorHandler((msg) {
        _isSpeaking = false;
        onSpeakingStateChanged?.call(false);
      });
      try {
        _availableVoices = await _flutterTts.getVoices;
      } catch (_) {}
      _isTtsInitialized = true;
    } catch (e) {
      debugPrint('VoiceService TTS init error: $e');
    }
  }

  Future<bool> initSpeech() async {
    if (_isSttInitialized) return true;
    try {
      _isSttInitialized = await _speechToText.initialize(
        onError: (err) {
          debugPrint('STT Error: ${err.errorMsg}');
          stopListening();
        },
        onStatus: (status) {
          debugPrint('STT Status: $status');
          if (status == 'done' || status == 'notListening') {
            if (_isListening) {
              _checkFinalizeOnStop();
            }
          }
        },
      );
      return _isSttInitialized;
    } catch (e) {
      debugPrint('VoiceService Speech init exception: $e');
      _isSttInitialized = false;
      return false;
    }
  }

  /// Starts speech recognition.
  Future<bool> startListening({
    required String language,
    double pauseDurationSeconds = 1.8,
  }) async {
    if (_isSpeaking) {
      await stopSpeaking();
    }

    final initialized = await initSpeech();
    if (!initialized) return false;

    _currentWords = '';
    _silenceTimer?.cancel();
    _isListening = true;
    onListeningStateChanged?.call(true);

    final localeId = language == 'af' ? 'af_ZA' : 'en_US';

    try {
      await _speechToText.listen(
        onResult: (SpeechRecognitionResult result) {
          _onSpeechResult(result, pauseDurationSeconds);
        },
        localeId: localeId,
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
      );
      return true;
    } catch (e) {
      debugPrint('Error starting listening: $e');
      stopListening();
      return false;
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result, double pauseDurationSeconds) {
    _currentWords = result.recognizedWords;
    onPartialText?.call(_currentWords);

    _silenceTimer?.cancel();

    if (_currentWords.trim().isNotEmpty) {
      final durationMs = (pauseDurationSeconds * 1000).toInt();
      _silenceTimer = Timer(Duration(milliseconds: durationMs), () {
        _finalizeAndDispatch();
      });
    }
  }

  void _checkFinalizeOnStop() {
    _silenceTimer?.cancel();
    _isListening = false;
    onListeningStateChanged?.call(false);

    if (_currentWords.trim().isNotEmpty) {
      final sent = _currentWords;
      _currentWords = '';
      onSpeechCompleted?.call(sent);
    }
  }

  Future<void> _finalizeAndDispatch() async {
    _silenceTimer?.cancel();
    final words = _currentWords;
    _currentWords = '';
    await stopListening();

    if (words.trim().isNotEmpty) {
      onSpeechCompleted?.call(words.trim());
    }
  }

  Future<void> stopListening() async {
    _silenceTimer?.cancel();
    _isListening = false;
    onListeningStateChanged?.call(false);
    try {
      await _speechToText.stop();
    } catch (_) {}
  }

  /// Speaks text with multi-tier vocal execution:
  /// 1. Check local neural voice cache.
  /// 2. If cache hit -> play cached MP3 with JustAudio.
  /// 3. If cache miss and server URL is configured -> call ServerNeuralVoiceGenerationService.
  /// 4. Save successful MP3 into LocalVoiceCacheManager.
  /// 5. Play with JustAudio.
  /// 6. If the server is unavailable, synthesis fails, times out, or no server URL is configured ->
  ///    fall back to DeviceTtsVoiceGenerationService / flutter_tts.
  Future<void> speak({
    required String text,
    required String characterId,
    required String language,
    double speedMultiplier = 0.85,
  }) async {
    if (text.trim().isEmpty) return;

    final currentRequestId = ++_activeSpeechRequestId;

    // Interrupt/stop any currently active playback/synthesis
    await _stopActiveEngines();
    await _serverNeuralVoiceService.stop();

    if (_activeSpeechRequestId != currentRequestId) return;

    // Offload text sanitization and SHA-256 computation to background isolate
    final profile = CharacterVoiceProfile.forCharacter(characterId);
    final voiceEngineVersion = language.toLowerCase().startsWith('af')
        ? 'google-cloud-tts-af-wavenet-v1'
        : 'gemini-3.1-flash-tts-preview-v1';

    final sanitizeResult = await LocalVoiceCacheManager.instance.sanitizeAndComputeKey(
      text: text,
      characterId: characterId,
      language: language,
      speedMultiplier: speedMultiplier,
      pitch: profile.pitch,
      baseRate: profile.baseRate,
      neuralVoiceId: profile.neuralVoiceId,
      voiceEngineVersion: voiceEngineVersion,
    );

    final cleanText = sanitizeResult['cleanText'] ?? text.trim();
    final hashKey = sanitizeResult['hashKey'] ?? '';

    if (cleanText.isEmpty || _activeSpeechRequestId != currentRequestId) {
      return;
    }

    // Step 1: Check local neural voice cache
    if (!kIsWeb && hashKey.isNotEmpty) {
      final cachedFile = await LocalVoiceCacheManager.instance.getCachedAudioFile(hashKey);
      if (cachedFile != null && await cachedFile.exists()) {
        debugPrint('[VoiceService] Cache hit for key $hashKey (${cachedFile.path}). Playing from disk.');
        // Step 2: If cache hit -> play cached MP3 with JustAudio
        await _playCachedFile(cachedFile, currentRequestId);
        return;
      }
    }

    // Step 3: If cache miss and server URL is configured -> call ServerNeuralVoiceGenerationService
    GeneratedAudio? neuralAudio;
    try {
      neuralAudio = await _serverNeuralVoiceService.synthesize(
        cleanText,
        profile: profile,
        settings: VoiceSettings(
          languageCode: language,
          speedMultiplier: speedMultiplier,
          pitch: profile.pitch,
        ),
      );
    } catch (e) {
      debugPrint('[VoiceService] ServerNeuralVoiceGenerationService dispatch exception: $e');
    }

    // Stale check after async network call: guard against interruption/character switch
    if (_activeSpeechRequestId != currentRequestId) {
      debugPrint('[VoiceService] Stale speech request $currentRequestId discarded after network response.');
      return;
    }

    if (neuralAudio != null && neuralAudio.bytes != null && neuralAudio.bytes!.isNotEmpty) {
      final audioBytes = neuralAudio.bytes!;

      // Step 4: Save successful MP3 into LocalVoiceCacheManager
      if (!kIsWeb && hashKey.isNotEmpty) {
        try {
          final savedFile = await LocalVoiceCacheManager.instance.saveAudioBytes(
            hashKey,
            audioBytes,
          );
          if (savedFile != null && await savedFile.exists()) {
            if (_activeSpeechRequestId != currentRequestId) return;
            // Step 5: Play with JustAudio
            await _playCachedFile(savedFile, currentRequestId);
            return;
          }
        } catch (cacheErr) {
          debugPrint('[VoiceService] Warning: Could not cache audio to disk: $cacheErr');
        }
      }

      // Step 5 (Memory/Web fallback): Play with JustAudio
      if (_activeSpeechRequestId != currentRequestId) return;
      await _playAudioBytes(audioBytes, currentRequestId);
      return;
    }

    // Step 6: If the server is unavailable, synthesis fails, times out, or no server URL is configured ->
    // fall back to DeviceTtsVoiceGenerationService / flutter_tts.
    if (_activeSpeechRequestId != currentRequestId) return;

    debugPrint(
      '[VoiceService] Server neural voice unavailable or failed. Falling back to DeviceTtsVoiceGenerationService (flutter_tts).',
    );

    await _deviceTtsVoiceService.synthesize(
      cleanText,
      profile: profile,
      settings: VoiceSettings(
        languageCode: language,
        speedMultiplier: speedMultiplier,
        pitch: profile.pitch,
      ),
    );
  }

  Future<void> _stopActiveEngines() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    try {
      await _flutterTts.stop();
    } catch (_) {}
  }

  Future<void> _playCachedFile(File file, int currentRequestId) async {
    try {
      if (_activeSpeechRequestId != currentRequestId) return;
      _isSpeaking = true;
      onSpeakingStateChanged?.call(true);

      await _audioPlayer.setFilePath(file.path);
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('[VoiceService] Error playing cached file: $e');
      if (_activeSpeechRequestId == currentRequestId) {
        _isSpeaking = false;
        onSpeakingStateChanged?.call(false);
      }
    }
  }

  Future<void> _playAudioBytes(Uint8List bytes, int currentRequestId) async {
    try {
      if (_activeSpeechRequestId != currentRequestId) return;
      _isSpeaking = true;
      onSpeakingStateChanged?.call(true);

      // Create a temporary data source for JustAudio
      final source = _BytesAudioSource(bytes);
      await _audioPlayer.setAudioSource(source);
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('[VoiceService] Error playing audio bytes: $e');
      if (_activeSpeechRequestId == currentRequestId) {
        _isSpeaking = false;
        onSpeakingStateChanged?.call(false);
      }
    }
  }

  Future<Uint8List?> _fetchNeuralAudioStream({
    required String text,
    required String characterId,
    required String language,
    required double speedMultiplier,
    required int currentRequestId,
  }) async {
    if (_serverStreamingGateway == null) return null;

    final response = await http.post(
      Uri.parse(_serverStreamingGateway!),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'text': text,
        'avatarId': characterId,
        'lang': language,
        'speed': speedMultiplier,
      }),
    ).timeout(const Duration(seconds: 15));

    if (currentRequestId != _activeSpeechRequestId) {
      return null;
    }

    if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
      return response.bodyBytes;
    }
    return null;
  }

  Future<void> _speakViaTts({
    required String cleanText,
    required String characterId,
    required String language,
    required double speedMultiplier,
    required int currentRequestId,
    required CharacterVoiceProfile profile,
  }) async {
    if (!_isTtsInitialized) {
      await _initTts();
    }

    if (_activeSpeechRequestId != currentRequestId) return;

    final langCode = language == 'af' ? 'af-ZA' : 'en-US';
    try {
      await _flutterTts.setLanguage(langCode);
    } catch (_) {
      await _flutterTts.setLanguage('en-US');
    }

    final pitch = profile.pitch;
    final baseRate = profile.baseRate;
    final finalRate = (baseRate * (speedMultiplier / 0.85)).clamp(0.20, 0.90);

    String? selectedDeviceVoice;
    try {
      if (_availableVoices != null && _availableVoices!.isNotEmpty) {
        final targetLangPrefix = language == 'af' ? 'af' : 'en';
        final isFemale = characterId == 'eve' || characterId == 'ara';

        for (final v in _availableVoices!) {
          if (v is Map) {
            final name = (v['name'] as String? ?? '').toLowerCase();
            final locale = (v['locale'] as String? ?? '').toLowerCase();
            if (locale.startsWith(targetLangPrefix)) {
              if (isFemale && (name.contains('female') || name.contains('sfg') || name.contains('tpf'))) {
                selectedDeviceVoice = v['name'] as String?;
                await _flutterTts.setVoice({'name': v['name'], 'locale': v['locale']});
                break;
              } else if (!isFemale && (name.contains('male') || name.contains('iol') || name.contains('rgd'))) {
                selectedDeviceVoice = v['name'] as String?;
                await _flutterTts.setVoice({'name': v['name'], 'locale': v['locale']});
                break;
              }
            }
          }
        }
      }
    } catch (voiceErr) {
      debugPrint('[VoiceService] Voice selection notice: $voiceErr');
    }

    debugPrint(
      '[VOICE_DIAGNOSTIC] Speaking for ${profile.characterName} (ID: $characterId) | Engine: Device TTS (flutter_tts) | Device Voice: ${selectedDeviceVoice ?? profile.deviceVoiceName} | Pitch: $pitch | Rate: $finalRate | Lang: $langCode',
    );

    try {
      await _flutterTts.setPitch(pitch);
      await _flutterTts.setSpeechRate(finalRate);
      await _flutterTts.setVolume(1.0);

      if (_activeSpeechRequestId != currentRequestId) return;

      _isSpeaking = true;
      onSpeakingStateChanged?.call(true);
      await _flutterTts.speak(cleanText);
    } catch (e) {
      debugPrint('TTS speak error: $e');
      if (_activeSpeechRequestId == currentRequestId) {
        _isSpeaking = false;
        onSpeakingStateChanged?.call(false);
      }
    }
  }

  /// Plays a neural audio stream or local file URI directly.
  Future<void> playAudioUri(String uri) async {
    final currentRequestId = ++_activeSpeechRequestId;
    try {
      await _stopActiveEngines();
      if (_activeSpeechRequestId != currentRequestId) return;

      _isSpeaking = true;
      onSpeakingStateChanged?.call(true);
      if (uri.startsWith('http://') || uri.startsWith('https://')) {
        await _audioPlayer.setUrl(uri);
      } else {
        await _audioPlayer.setFilePath(uri);
      }
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('VoiceService playAudioUri error: $e');
      if (_activeSpeechRequestId == currentRequestId) {
        _isSpeaking = false;
        onSpeakingStateChanged?.call(false);
      }
    }
  }

  Future<void> stopSpeaking() async {
    _activeSpeechRequestId++;
    await _serverNeuralVoiceService.stop();
    await _stopActiveEngines();
    _isSpeaking = false;
    onSpeakingStateChanged?.call(false);
  }

  void dispose() {
    _silenceTimer?.cancel();
    _speechToText.stop();
    _flutterTts.stop();
    _serverNeuralVoiceService.dispose();
    _audioPlayer.dispose();
  }
}

/// Custom in-memory StreamAudioSource for JustAudio raw byte streams.
class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  _BytesAudioSource(this._bytes);

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/mp3',
    );
  }
}
