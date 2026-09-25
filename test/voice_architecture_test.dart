import 'package:flutter_test/flutter_test.dart';
import 'package:listen_to_eve/services/voice_generation_service.dart';
import 'package:listen_to_eve/services/local_voice_cache_manager.dart';

void main() {
  group('Voice Architecture Tests', () {
    test('All 5 characters have distinct and valid CharacterVoiceProfiles', () {
      final characters = ['eve', 'ara', 'leo', 'rex', 'sal'];

      for (final charId in characters) {
        final profile = CharacterVoiceProfile.forCharacter(charId);
        expect(profile.characterId, equals(charId));
        expect(profile.characterName.isNotEmpty, isTrue);
        expect(profile.pitch, greaterThan(0.5));
        expect(profile.pitch, lessThan(2.0));
        expect(profile.baseRate, greaterThan(0.2));
        expect(profile.baseRate, lessThan(0.8));
        expect(profile.neuralVoiceId.isNotEmpty, isTrue);
        expect(profile.deviceVoiceName.isNotEmpty, isTrue);
      }

      // Verify pitch differentiations (e.g. Ara > Eve > Rex > Leo > Sal)
      final ara = CharacterVoiceProfile.forCharacter('ara');
      final eve = CharacterVoiceProfile.forCharacter('eve');
      final leo = CharacterVoiceProfile.forCharacter('leo');
      final sal = CharacterVoiceProfile.forCharacter('sal');

      expect(ara.pitch, greaterThan(eve.pitch));
      expect(eve.pitch, greaterThan(leo.pitch));
      expect(leo.pitch, greaterThan(sal.pitch));
    });

    test('LocalVoiceCacheManager generates deterministic cache keys', () async {
      final manager = LocalVoiceCacheManager.instance;

      final key1 = await manager.sanitizeAndComputeKey(
        text: 'Hello, I am Eve.',
        characterId: 'eve',
        language: 'en',
        speedMultiplier: 0.85,
      );

      final key2 = await manager.sanitizeAndComputeKey(
        text: 'Hello, I am Eve.',
        characterId: 'eve',
        language: 'en',
        speedMultiplier: 0.85,
      );

      final keyAra = await manager.sanitizeAndComputeKey(
        text: 'Hello, I am Eve.',
        characterId: 'ara',
        language: 'en',
        speedMultiplier: 0.85,
      );

      expect(key1['hashKey'], equals(key2['hashKey']));
      expect(key1['hashKey'], isNot(equals(keyAra['hashKey'])));
    });

    test('VoiceSettings copyWith operates immutably and accurately', () {
      const base = VoiceSettings(
        speedMultiplier: 0.85,
        pitch: 1.0,
        volume: 1.0,
        languageCode: 'en-US',
      );

      final modified = base.copyWith(
        speedMultiplier: 1.10,
        languageCode: 'af-ZA',
      );

      expect(modified.speedMultiplier, equals(1.10));
      expect(modified.pitch, equals(1.0));
      expect(modified.volume, equals(1.0));
      expect(modified.languageCode, equals('af-ZA'));
      expect(base.speedMultiplier, equals(0.85)); // Original untouched
    });
  });
}
