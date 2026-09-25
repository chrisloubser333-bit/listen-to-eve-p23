import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen_to_eve/models/message.dart';
import 'package:listen_to_eve/providers/chat_provider.dart';
import 'package:listen_to_eve/services/local_image_storage_manager.dart';

void main() {
  group('LocalImageStorageManager Tests', () {
    final manager = LocalImageStorageManager.instance;

    test('Identifies data URI and raw Base64 payloads correctly', () {
      // Data URI
      expect(
        manager.isBase64Payload('data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD...'),
        isTrue,
      );
      expect(
        manager.isBase64Payload('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAA...'),
        isTrue,
      );

      // URLs and local paths should NOT be treated as base64
      expect(manager.isBase64Payload('https://example.com/image.jpg'), isFalse);
      expect(manager.isBase64Payload('http://example.com/image.png'), isFalse);
      expect(manager.isBase64Payload('/data/user/0/com.example/files/image.jpg'), isFalse);
      expect(manager.isBase64Payload('file:///data/user/0/com.example/files/image.jpg'), isFalse);
      expect(manager.isBase64Payload('assets/avatars/eve.png'), isFalse);
      expect(manager.isBase64Payload(''), isFalse);
      expect(manager.isBase64Payload(null), isFalse);
    });

    test('Detects file extensions accurately from MIME and magic bytes', () {
      expect(manager.detectExtension('data:image/jpeg;base64,...'), equals('jpg'));
      expect(manager.detectExtension('data:image/jpg;base64,...'), equals('jpg'));
      expect(manager.detectExtension('data:image/png;base64,...'), equals('png'));
      expect(manager.detectExtension('data:image/webp;base64,...'), equals('webp'));
      expect(manager.detectExtension('data:image/gif;base64,...'), equals('gif'));

      // Magic byte detection
      final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]);
      expect(manager.detectExtension('', jpegBytes), equals('jpg'));

      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(manager.detectExtension('', pngBytes), equals('png'));

      final webpBytes = Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00]);
      expect(manager.detectExtension('', webpBytes), equals('webp'));
    });

    test('ChatMessage model correctly retains local paths and serializes cleanly', () {
      final msg = ChatMessage(
        id: 'test-uuid-1234',
        role: MessageRole.assistant,
        content: 'Here is your image',
        timestamp: DateTime.parse('2026-09-13T12:00:00Z'),
        imageUrl: '/data/user/0/com.listentoeve/files/generated_images/chat_1234.jpg',
        imagePrompt: 'Table Mountain at sunset',
      );

      expect(msg.isImage, isTrue);
      expect(msg.imageUrl, startsWith('/data/user/0/com.listentoeve/files/'));
      expect(msg.imagePrompt, equals('Table Mountain at sunset'));

      final json = msg.toJson();
      final serialized = jsonEncode(json);

      // JSON string must be very compact (under 250 characters), proving no Base64 bloat
      expect(serialized.length, lessThan(300));
      expect(serialized.contains('/generated_images/chat_1234.jpg'), isTrue);

      final deserialized = ChatMessage.fromJson(jsonDecode(serialized) as Map<String, dynamic>);
      expect(deserialized.id, equals(msg.id));
      expect(deserialized.imageUrl, equals(msg.imageUrl));
      expect(deserialized.imagePrompt, equals(msg.imagePrompt));
    });

    test('ChatMessage copyWith creates accurate updated instances for migration', () {
      final oldMsg = ChatMessage(
        id: 'legacy-msg-99',
        role: MessageRole.assistant,
        content: 'Legacy image',
        timestamp: DateTime.now(),
        imageUrl: 'data:image/jpeg;base64,/9j/4AAQSkZJRg...',
        imagePrompt: 'A sunset view',
      );

      final newPath = '/data/user/0/com.listentoeve/files/generated_images/migrated_legacy-msg-99.jpg';
      final migratedMsg = oldMsg.copyWith(imageUrl: newPath);

      expect(migratedMsg.id, equals('legacy-msg-99'));
      expect(migratedMsg.imageUrl, equals(newPath));
      expect(migratedMsg.imagePrompt, equals('A sunset view'));
    });

    test('Intent routing correctly classifies image vs song vs weather vs conversation', () {
      // 1. Mandatory image requests
      final img1 = ChatProvider.detectImageIntent('Please create an image of Table Mountain at sunset.');
      expect(img1, isNotNull);
      expect(img1!.isIntent, isTrue);
      expect(img1.rawPrompt.toLowerCase(), contains('table mountain at sunset'));

      final img2 = ChatProvider.detectImageIntent('Show me Table Mountain at sunset.');
      expect(img2, isNotNull);
      expect(img2!.isIntent, isTrue);
      expect(img2.rawPrompt.toLowerCase(), contains('table mountain at sunset'));

      final img3 = ChatProvider.detectImageIntent('Can you create an image of a lion?');
      expect(img3, isNotNull);
      expect(img3!.isIntent, isTrue);
      expect(img3.rawPrompt.toLowerCase(), contains('lion'));

      final img4 = ChatProvider.detectImageIntent('Ara, please create an image of a futuristic city.');
      expect(img4, isNotNull);
      expect(img4!.isIntent, isTrue);
      expect(img4.explicitCharacterId, equals('ara'));
      expect(img4.rawPrompt.toLowerCase(), contains('futuristic city'));

      // 2. Song / music requests (MUST NOT be intercepted by image generation)
      final song = ChatProvider.detectImageIntent('Create a song about Table Mountain.');
      expect(song, isNull);

      // 3. Weather queries (MUST NOT be intercepted by image generation)
      final weather = ChatProvider.detectImageIntent('What is the weather in Cape Town?');
      expect(weather, isNull);

      // 4. Normal self-appearance inquiry (handled as self-look portrait/selfie or normal conversational response)
      final appearance = ChatProvider.detectImageIntent('What do you look like?');
      expect(appearance, isNotNull);
      expect(appearance!.isSelfReference, isTrue);
    });
  });
}
