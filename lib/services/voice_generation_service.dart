import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/character_profile.dart';

/// Represents synthesized audio data from any voice provider.
class GeneratedAudio {
  final Uint8List? bytes;
  final String? localFilePath;
  final String mimeType;
  final Duration? duration;
  final String provider;
  final String? voiceId;

  const GeneratedAudio({
    this.bytes,
    this.localFilePath,
    this.mimeType = 'audio/mp3',
    this.duration,
    required this.provider,
    this.voiceId,
  });

  bool get hasFile => localFilePath != null && localFilePath!.isNotEmpty;
  bool get hasBytes => bytes != null && bytes!.isNotEmpty;
}

/// Acoustical and behavioral settings for speech generation.
class VoiceSettings {
  final double speedMultiplier;
  final double pitch;
  final double volume;
  final String languageCode; // e.g. 'en-US' or 'af-ZA'

  const VoiceSettings({
    this.speedMultiplier = 0.85,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.languageCode = 'en-US',
  });

  VoiceSettings copyWith({
    double? speedMultiplier,
    double? pitch,
    double? volume,
    String? languageCode,
  }) {
    return VoiceSettings(
      speedMultiplier: speedMultiplier ?? this.speedMultiplier,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      languageCode: languageCode ?? this.languageCode,
    );
  }
}

/// Character-specific voice acoustic profile.
class CharacterVoiceProfile {
  final String characterId;
  final String characterName;
  final double pitch;
  final double baseRate;
  final String deviceVoiceName;
  final String neuralVoiceId;
  final String personalityVocalCadence;

  const CharacterVoiceProfile({
    required this.characterId,
    required this.characterName,
    required this.pitch,
    required this.baseRate,
    required this.deviceVoiceName,
    required this.neuralVoiceId,
    required this.personalityVocalCadence,
  });

  /// Registry of distinct vocal profiles for all 5 characters in Listen to Eve.
  static const Map<String, CharacterVoiceProfile> characterProfiles = {
    'eve': CharacterVoiceProfile(
      characterId: 'eve',
      characterName: 'Eve',
      pitch: 1.06,
      baseRate: 0.39,
      deviceVoiceName: 'en-us-x-sfg#female_1-local',
      neuralVoiceId: 'en-US-Journey-F',
      personalityVocalCadence: 'Warm, melodic, calm, emotionally perceptive, and grounded.',
    ),
    'ara': CharacterVoiceProfile(
      characterId: 'ara',
      characterName: 'Ara',
      pitch: 1.12,
      baseRate: 0.37,
      deviceVoiceName: 'en-us-x-tpf#female_2-local',
      neuralVoiceId: 'en-US-Journey-O',
      personalityVocalCadence: 'Reflective, lyrical, thoughtful, poetic cadence.',
    ),
    'leo': CharacterVoiceProfile(
      characterId: 'leo',
      characterName: 'Leo',
      pitch: 0.88,
      baseRate: 0.42,
      deviceVoiceName: 'en-us-x-iol#male_1-local',
      neuralVoiceId: 'en-US-Journey-D',
      personalityVocalCadence: 'Confident, articulate, sharp, intellectual masculine resonance.',
    ),
    'rex': CharacterVoiceProfile(
      characterId: 'rex',
      characterName: 'Rex',
      pitch: 0.94,
      baseRate: 0.44,
      deviceVoiceName: 'en-us-x-rgd#male_2-local',
      neuralVoiceId: 'en-US-Neural2-J',
      personalityVocalCadence: 'Bold, energetic, spirited, adventurous cadence.',
    ),
    'sal': CharacterVoiceProfile(
      characterId: 'sal',
      characterName: 'Sal',
      pitch: 0.82,
      baseRate: 0.36,
      deviceVoiceName: 'en-us-x-sfg#male_3-local',
      neuralVoiceId: 'en-US-Neural2-D',
      personalityVocalCadence: 'Calm, steady, unhurried, reassuring baritone warmth.',
    ),
  };

  static CharacterVoiceProfile forCharacter(String characterId) {
    return characterProfiles[characterId.toLowerCase()] ?? characterProfiles['eve']!;
  }
}

/// Provider-independent voice synthesis and generation contract.
///
/// Ensures ChatProvider is decoupled from specific voice engines (device TTS,
/// Google Cloud TTS, Neural TTS, or Gemini Live API).
abstract class VoiceGenerationService {
  /// Synthesizes text into audio or directly delivers speech playback.
  Future<GeneratedAudio?> synthesize(
    String text, {
    required CharacterVoiceProfile profile,
    VoiceSettings settings = const VoiceSettings(),
    String? cancellationToken,
  });

  /// Immediately interrupts/stops any active speech synthesis or playback.
  Future<void> stop();

  /// Releases resources.
  Future<void> dispose();
}

/// Device-native TTS implementation conforming to VoiceGenerationService.
class DeviceTtsVoiceGenerationService implements VoiceGenerationService {
  final Future<void> Function({
    required String text,
    required String characterId,
    required String language,
    double speedMultiplier,
  }) _speakFunction;

  final Future<void> Function() _stopFunction;

  DeviceTtsVoiceGenerationService({
    required Future<void> Function({
      required String text,
      required String characterId,
      required String language,
      double speedMultiplier,
    }) speakFunction,
    required Future<void> Function() stopFunction,
  })  : _speakFunction = speakFunction,
        _stopFunction = stopFunction;

  @override
  Future<GeneratedAudio?> synthesize(
    String text, {
    required CharacterVoiceProfile profile,
    VoiceSettings settings = const VoiceSettings(),
    String? cancellationToken,
  }) async {
    await _speakFunction(
      text: text,
      characterId: profile.characterId,
      language: settings.languageCode.startsWith('af') ? 'af' : 'en',
      speedMultiplier: settings.speedMultiplier,
    );

    return GeneratedAudio(
      provider: 'device_tts',
      voiceId: profile.deviceVoiceName,
      mimeType: 'audio/x-raw-tts',
    );
  }

  @override
  Future<void> stop() async {
    await _stopFunction();
  }

  @override
  Future<void> dispose() async {
    await _stopFunction();
  }
}

