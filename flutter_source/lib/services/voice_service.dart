import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

/// Manages Speech-To-Text (STT) and Text-To-Speech (TTS) for Listen to Eve.
///
/// Implements:
/// - Continuous listening with configurable silence pause duration (1.0s - 3.0s).
/// - Automatic dispatch after silence.
/// - Character-specific speech synthesis with distinct pitch and rate.
/// - Bilingual support (English and Afrikaans).
/// - Graceful fallback when platform audio hardware/services are restricted.
class VoiceService {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isSttInitialized = false;
  bool _isTtsInitialized = false;
  bool _isListening = false;
  bool _isSpeaking = false;

  Timer? _silenceTimer;
  String _currentWords = '';

  // Callbacks
  Function(String words)? onPartialText;
  Function(String finalWords)? onSpeechCompleted;
  Function(bool isListening)? onListeningStateChanged;
  Function(bool isSpeaking)? onSpeakingStateChanged;

  VoiceService() {
    _initTts();
  }

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;

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
              // If stopped without silence timer triggering, finalize words
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
  /// [pauseDurationSeconds]: Time of silence before auto-dispatching (e.g. 1.5s or 2.0s).
  Future<bool> startListening({
    required String language,
    double pauseDurationSeconds = 1.8,
  }) async {
    // If Eve is speaking, interrupt first
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

    // Reset silence timer on any newly recognized word
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

  /// Speaks text with character-specific humanized acoustic settings.
  Future<void> speak({
    required String text,
    required String characterId,
    required String language,
    double speedMultiplier = 0.85,
  }) async {
    if (text.trim().isEmpty) return;

    // Clean markdown asterisks and hashtags for clean vocal delivery
    final cleanText = text
        .replaceAll(RegExp(r'\*+'), '')
        .replaceAll(RegExp(r'#+'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .trim();

    if (!_isTtsInitialized) {
      await _initTts();
    }

    // Stop previous speech if running
    await _flutterTts.stop();

    // Configure language
    final langCode = language == 'af' ? 'af-ZA' : 'en-US';
    try {
      await _flutterTts.setLanguage(langCode);
    } catch (_) {
      await _flutterTts.setLanguage('en-US');
    }

    // Character-specific distinct vocal acoustic profile (natural, relaxed human cadence)
    double pitch = 1.0;
    // Base rate is reduced from rushed 0.50+ down to a relaxed, natural 0.38-0.42 base
    double baseRate = 0.40;

    switch (characterId.toLowerCase()) {
      case 'eve':
        // Warm, friendly, melodic and clear female presence
        pitch = 1.06;
        baseRate = 0.39;
        break;
      case 'ara':
        // Reflective, poetic, thoughtful female pacing
        pitch = 1.12;
        baseRate = 0.37;
        break;
      case 'leo':
        // Confident, articulated, sharp masculine cadence
        pitch = 0.88;
        baseRate = 0.42;
        break;
      case 'rex':
        // Bold, energetic, spirited masculine cadence
        pitch = 0.94;
        baseRate = 0.44;
        break;
      case 'sal':
        // Calm, unhurried, grounded masculine warmth
        pitch = 0.82;
        baseRate = 0.36;
        break;
      default:
        pitch = 1.0;
        baseRate = 0.40;
    }

    // Multiply by user's speed setting from Settings (default 0.85x - 1.0x)
    // Clamp to safe TTS engine bounds
    final finalRate = (baseRate * (speedMultiplier / 0.85)).clamp(0.20, 0.90);

    try {
      await _flutterTts.setPitch(pitch);
      await _flutterTts.setSpeechRate(finalRate);
      await _flutterTts.setVolume(1.0);
      _isSpeaking = true;
      onSpeakingStateChanged?.call(true);
      await _flutterTts.speak(cleanText);
    } catch (e) {
      debugPrint('TTS speak error: $e');
      _isSpeaking = false;
      onSpeakingStateChanged?.call(false);
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _flutterTts.stop();
    } catch (_) {}
    _isSpeaking = false;
    onSpeakingStateChanged?.call(false);
  }

  void dispose() {
    _silenceTimer?.cancel();
    _speechToText.stop();
    _flutterTts.stop();
  }
}
