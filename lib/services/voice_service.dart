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
  Function()? _pendingPlaybackStarted;

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
    _serverStreamingGateway =
        (url != null && url.trim().isNotEmpty) ? url.trim() : null;
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
        _notifyPlaybackStarted();
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

  void _onSpeechResult(
      SpeechRecognitionResult result, double pauseDurationSeconds) {
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

  /// Maximum text size sent in one neural synthesis request.
  ///
  /// Kept below the backend/provider ceiling so punctuation and normal
  /// conversational responses do not accidentally exceed the request limit.
  static const int _maxNeuralChunkChars = 450;

  /// Splits sanitized speech text into ordered neural synthesis chunks.
  ///
  /// Preference order:
  /// 1. Sentence boundary.
  /// 2. Clause/punctuation boundary.
  /// 3. Whitespace.
  /// 4. Hard character boundary as a last resort.
  ///
  /// No non-whitespace content is discarded.
  static List<String> _splitNeuralTextIntoChunks(
    String text, {
    int maxChars = _maxNeuralChunkChars,
  }) {
    final normalized = text.trim();
    if (normalized.isEmpty) return const <String>[];

    if (maxChars < 1) {
      throw ArgumentError.value(maxChars, 'maxChars', 'Must be greater than 0');
    }

    if (normalized.length <= maxChars) {
      return <String>[normalized];
    }

    final chunks = <String>[];
    var remaining = normalized;

    while (remaining.length > maxChars) {
      final window = remaining.substring(0, maxChars + 1);

      int splitAt = -1;

      // Prefer complete sentence endings.
      for (var i = maxChars; i > 0; i--) {
        final previous = window[i - 1];
        final next = i < window.length ? window[i] : '';

        if ((previous == '.' || previous == '!' || previous == '?') &&
            (next.isEmpty || RegExp(r'\s').hasMatch(next))) {
          splitAt = i;
          break;
        }
      }

      // Then prefer softer punctuation boundaries.
      if (splitAt <= 0) {
        for (var i = maxChars; i > 0; i--) {
          final previous = window[i - 1];
          final next = i < window.length ? window[i] : '';

          if ((previous == ';' ||
                  previous == ':' ||
                  previous == ',' ||
                  previous == '—' ||
                  previous == '–') &&
              (next.isEmpty || RegExp(r'\s').hasMatch(next))) {
            splitAt = i;
            break;
          }
        }
      }

      // Then use the nearest whitespace boundary.
      if (splitAt <= 0) {
        for (var i = maxChars; i > 0; i--) {
          if (RegExp(r'\s').hasMatch(window[i - 1])) {
            splitAt = i;
            break;
          }
        }
      }

      // A single uninterrupted token may itself exceed the limit.
      if (splitAt <= 0) {
        splitAt = maxChars;
      }

      final chunk = remaining.substring(0, splitAt).trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }

      remaining = remaining.substring(splitAt).trimLeft();
    }

    if (remaining.trim().isNotEmpty) {
      chunks.add(remaining.trim());
    }

    return chunks;
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
    Function()? onPlaybackStarted,
  }) async {
    if (text.trim().isEmpty) return;

    final currentRequestId = ++_activeSpeechRequestId;
    _pendingPlaybackStarted = onPlaybackStarted;

    // Interrupt/stop any currently active playback/synthesis
    await _stopActiveEngines();
    await _serverNeuralVoiceService.stop();

    if (_activeSpeechRequestId != currentRequestId) return;

    // Offload text sanitization and SHA-256 computation to background isolate
    final profile = CharacterVoiceProfile.forCharacter(characterId);
    final voiceEngineVersion = language.toLowerCase().startsWith('af')
        ? 'google-cloud-tts-af-wavenet-v1'
        : 'gemini-3.1-flash-tts-preview-v1';

    final sanitizeResult =
        await LocalVoiceCacheManager.instance.sanitizeAndComputeKey(
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

    final chunks = _splitNeuralTextIntoChunks(cleanText);

    if (chunks.isEmpty) return;

    debugPrint(
      '[VoiceService] Neural speech split into ${chunks.length} chunk(s) '
      'for request $currentRequestId.',
    );

    for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
      if (_activeSpeechRequestId != currentRequestId) {
        debugPrint(
          '[VoiceService] Speech request $currentRequestId interrupted '
          'before chunk ${chunkIndex + 1}/${chunks.length}.',
        );
        return;
      }

      final chunk = chunks[chunkIndex];

      // Cache keys must be generated per chunk. Reusing the full-response key
      // would make independently synthesized chunks collide in the cache.
      final chunkCacheResult =
          await LocalVoiceCacheManager.instance.sanitizeAndComputeKey(
        text: chunk,
        characterId: characterId,
        language: language,
        speedMultiplier: speedMultiplier,
        pitch: profile.pitch,
        baseRate: profile.baseRate,
        neuralVoiceId: profile.neuralVoiceId,
        voiceEngineVersion: voiceEngineVersion,
      );

      if (_activeSpeechRequestId != currentRequestId) return;

      final chunkText = chunkCacheResult['cleanText'] ?? chunk;
      final chunkHashKey = chunkCacheResult['hashKey'] ?? '';

      if (chunkText.trim().isEmpty) {
        continue;
      }

      debugPrint(
        '[VoiceService] Processing neural chunk '
        '${chunkIndex + 1}/${chunks.length} '
        '(len=${chunkText.length}).',
      );

      // Step 1: Check the local neural cache for this chunk.
      if (!kIsWeb && chunkHashKey.isNotEmpty) {
        final cachedFile =
            await LocalVoiceCacheManager.instance.getCachedAudioFile(
          chunkHashKey,
        );

        if (_activeSpeechRequestId != currentRequestId) return;

        if (cachedFile != null && await cachedFile.exists()) {
          debugPrint(
            '[VoiceService] Cache hit for neural chunk '
            '${chunkIndex + 1}/${chunks.length}.',
          );

          await _playCachedFile(cachedFile, currentRequestId);

          if (_activeSpeechRequestId != currentRequestId) return;
          continue;
        }
      }

      // Step 2: Synthesize this chunk through the server neural provider.
      GeneratedAudio? neuralAudio;
      try {
        neuralAudio = await _serverNeuralVoiceService.synthesize(
          chunkText,
          profile: profile,
          settings: VoiceSettings(
            languageCode: language,
            speedMultiplier: speedMultiplier,
            pitch: profile.pitch,
          ),
        );
      } catch (e) {
        debugPrint(
          '[VoiceService] Neural chunk ${chunkIndex + 1}/${chunks.length} '
          'dispatch exception: $e',
        );
      }

      if (_activeSpeechRequestId != currentRequestId) {
        debugPrint(
          '[VoiceService] Stale speech request $currentRequestId discarded '
          'after neural chunk ${chunkIndex + 1}/${chunks.length}.',
        );
        return;
      }

      final audioBytes = neuralAudio?.bytes;

      if (audioBytes != null && audioBytes.isNotEmpty) {
        var playedFromCacheFile = false;

        // Step 3: Cache successful neural audio for this exact chunk.
        if (!kIsWeb && chunkHashKey.isNotEmpty) {
          try {
            final savedFile =
                await LocalVoiceCacheManager.instance.saveAudioBytes(
              chunkHashKey,
              audioBytes,
            );

            if (_activeSpeechRequestId != currentRequestId) return;

            if (savedFile != null && await savedFile.exists()) {
              await _playCachedFile(savedFile, currentRequestId);
              playedFromCacheFile = true;
            }
          } catch (cacheErr) {
            debugPrint(
              '[VoiceService] Warning: Could not cache neural chunk '
              '${chunkIndex + 1}/${chunks.length}: $cacheErr',
            );
          }
        }

        if (_activeSpeechRequestId != currentRequestId) return;

        // Web or cache-write failure: play directly from memory.
        if (!playedFromCacheFile) {
          await _playAudioBytes(audioBytes, currentRequestId);
        }

        if (_activeSpeechRequestId != currentRequestId) return;
        continue;
      }

      // Neural synthesis failed for this chunk. Do not restart the whole
      // response from the beginning: speak only this chunk and the remaining
      // chunks through the device fallback.
      if (_activeSpeechRequestId != currentRequestId) return;

      final remainingText = chunks.sublist(chunkIndex).join(' ').trim();

      debugPrint(
        '[VoiceService] Neural synthesis unavailable at chunk '
        '${chunkIndex + 1}/${chunks.length}. Falling back to device TTS '
        'for the remaining ${chunks.length - chunkIndex} chunk(s).',
      );

      if (remainingText.isNotEmpty) {
        _notifyPlaybackStarted();

        await _deviceTtsVoiceService.synthesize(
          remainingText,
          profile: profile,
          settings: VoiceSettings(
            languageCode: language,
            speedMultiplier: speedMultiplier,
            pitch: profile.pitch,
          ),
        );
      }

      return;
    }
  }

  void _notifyPlaybackStarted() {
    final callback = _pendingPlaybackStarted;
    _pendingPlaybackStarted = null;
    if (callback != null) {
      try {
        callback();
      } catch (e) {
        debugPrint('[VoiceService] playback-start callback error: $e');
      }
    }
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
      _notifyPlaybackStarted();
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
      _notifyPlaybackStarted();
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

    final response = await http
        .post(
          Uri.parse(_serverStreamingGateway!),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'text': text,
            'avatarId': characterId,
            'lang': language,
            'speed': speedMultiplier,
          }),
        )
        .timeout(const Duration(seconds: 15));

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
              if (isFemale &&
                  (name.contains('female') ||
                      name.contains('sfg') ||
                      name.contains('tpf'))) {
                selectedDeviceVoice = v['name'] as String?;
                await _flutterTts
                    .setVoice({'name': v['name'], 'locale': v['locale']});
                break;
              } else if (!isFemale &&
                  (name.contains('male') ||
                      name.contains('iol') ||
                      name.contains('rgd'))) {
                selectedDeviceVoice = v['name'] as String?;
                await _flutterTts
                    .setVoice({'name': v['name'], 'locale': v['locale']});
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
    _pendingPlaybackStarted = null;
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
