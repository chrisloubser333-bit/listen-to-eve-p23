import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Top-level helper executed in a background Isolate to sanitize text and compute SHA-256.
Map<String, String> _isolateSanitizeAndHash(Map<String, dynamic> params) {
  final rawText = params['text'] as String? ?? '';
  final characterId = params['characterId'] as String? ?? 'eve';
  final language = params['language'] as String? ?? 'en';
  final speedMultiplier = (params['speedMultiplier'] as num?)?.toDouble() ?? 0.85;
  final pitch = (params['pitch'] as num?)?.toDouble() ?? 1.0;
  final baseRate = (params['baseRate'] as num?)?.toDouble() ?? 0.39;
  final neuralVoiceId = params['neuralVoiceId'] as String? ?? '';
  final voiceEngineVersion = params['voiceEngineVersion'] as String? ?? 'legacy';

  // 1. Strip markdown, emojis, asterisks, hashtags, bracket meta-tokens, and collapse whitespace
  final cleanText = rawText
      .replaceAll(RegExp(r'\*+'), '')
      .replaceAll(RegExp(r'#+'), '')
      .replaceAll(RegExp(r'\[.*?\]'), '')
      .replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}|\u{1F300}-\u{1F5FF}|\u{1F680}-\u{1F6FF}|\u{1F1E0}-\u{1F1FF}|\u{2600}-\u{26FF}|\u{2700}-\u{27BF}]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // 2. Build deterministic canonical signature string
  final signature = 'text=$cleanText|char=$characterId|lang=$language|speed=${speedMultiplier.toStringAsFixed(3)}|pitch=${pitch.toStringAsFixed(3)}|rate=${baseRate.toStringAsFixed(3)}|neural=$neuralVoiceId|engine=$voiceEngineVersion';

  // 3. Compute SHA-256
  final bytes = utf8.encode(signature);
  final digest = sha256.convert(bytes);

  return {
    'cleanText': cleanText,
    'hashKey': digest.toString(),
  };
}

/// Production-hardened disk-backed caching layer for synthesized and streamed voices.
///
/// Features:
/// - Computes deterministic SHA-256 key matching text, character profile, and acoustic settings.
/// - Offloads string sanitization and cryptographic hashing to background Dart isolates (`Isolate.run`).
/// - Stores audio files on disk in the application document cache to eliminate redundant network roundtrips.
/// - Thread-safe with automatic cache size pruning.
class LocalVoiceCacheManager {
  static final LocalVoiceCacheManager _instance = LocalVoiceCacheManager._internal();
  static LocalVoiceCacheManager get instance => _instance;

  Directory? _cacheDir;
  bool _isInitializing = false;
  static const int _maxCacheSizeBytes = 100 * 1024 * 1024; // 100 MB max audio cache

  LocalVoiceCacheManager._internal();

  /// Resolves or initializes the private local directory used for voice audio caching.
  Future<Directory> getStorageDirectory() async {
    if (_cacheDir != null && await _cacheDir!.exists()) {
      return _cacheDir!;
    }

    if (kIsWeb) {
      throw UnsupportedError('Local filesystem voice caching is not supported on Web.');
    }

    Directory baseDir;
    try {
      baseDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      baseDir = await getApplicationSupportDirectory();
    }

    final voiceDir = Directory('${baseDir.path}/cached_voices');
    if (!await voiceDir.exists()) {
      await voiceDir.create(recursive: true);
    }
    _cacheDir = voiceDir;
    return _cacheDir!;
  }

  /// Sanitizes text and computes a deterministic SHA-256 cache key in a background isolate.
  Future<Map<String, String>> sanitizeAndComputeKey({
    required String text,
    required String characterId,
    required String language,
    required double speedMultiplier,
    double? pitch,
    double? baseRate,
    String? neuralVoiceId,
    String? voiceEngineVersion,
  }) async {
    final params = {
      'text': text,
      'characterId': characterId,
      'language': language,
      'speedMultiplier': speedMultiplier,
      'pitch': pitch ?? 1.0,
      'baseRate': baseRate ?? 0.39,
      'neuralVoiceId': neuralVoiceId ?? '',
      'voiceEngineVersion': voiceEngineVersion ?? 'legacy',
    };

    try {
      return await Isolate.run(() => _isolateSanitizeAndHash(params));
    } catch (_) {
      // Fallback in case Isolate.run is unavailable
      return _isolateSanitizeAndHash(params);
    }
  }

  /// Checks if a cached audio file exists for the given SHA-256 hash key.
  Future<File?> getCachedAudioFile(String hashKey, {String extension = 'mp3'}) async {
    if (kIsWeb || hashKey.isEmpty) return null;
    try {
      final dir = await getStorageDirectory();
      final file = File('${dir.path}/$hashKey.$extension');
      if (await file.exists() && await file.length() > 0) {
        return file;
      }
    } catch (e) {
      debugPrint('[LocalVoiceCacheManager] Check cache error: $e');
    }
    return null;
  }

  /// Persists synthesized/streamed audio binary bytes to disk.
  Future<File?> saveAudioBytes(
    String hashKey,
    Uint8List bytes, {
    String extension = 'mp3',
  }) async {
    if (kIsWeb || hashKey.isEmpty || bytes.isEmpty) return null;
    try {
      final dir = await getStorageDirectory();
      final file = File('${dir.path}/$hashKey.$extension');
      await file.writeAsBytes(bytes, flush: true);

      // Async background pruning if cache exceeds threshold
      _pruneCacheIfNeeded();

      return file;
    } catch (e) {
      debugPrint('[LocalVoiceCacheManager] Save audio error: $e');
      return null;
    }
  }

  /// Background pruning to keep disk cache bounded within limits.
  void _pruneCacheIfNeeded() {
    if (kIsWeb) return;
    Future.microtask(() async {
      try {
        final dir = await getStorageDirectory();
        final entities = await dir.list().toList();
        final files = entities.whereType<File>().toList();

        int totalBytes = 0;
        final fileStats = <Map<String, dynamic>>[];
        for (final f in files) {
          final stat = await f.stat();
          totalBytes += stat.size;
          fileStats.add({
            'file': f,
            'size': stat.size,
            'modified': stat.modified,
          });
        }

        if (totalBytes > _maxCacheSizeBytes) {
          // Sort oldest first
          fileStats.sort((a, b) => (a['modified'] as DateTime).compareTo(b['modified'] as DateTime));
          int bytesToRemove = totalBytes - (_maxCacheSizeBytes ~/ 2);
          for (final item in fileStats) {
            if (bytesToRemove <= 0) break;
            final file = item['file'] as File;
            final size = item['size'] as int;
            try {
              await file.delete();
              bytesToRemove -= size;
            } catch (_) {}
          }
          debugPrint('[LocalVoiceCacheManager] Pruned audio cache to maintain disk threshold.');
        }
      } catch (_) {}
    });
  }

  /// Clears all cached audio files.
  Future<void> clearCache() async {
    if (kIsWeb) return;
    try {
      final dir = await getStorageDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint('[LocalVoiceCacheManager] Clear cache error: $e');
    }
  }
}
