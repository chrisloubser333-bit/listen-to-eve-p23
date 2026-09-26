import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

Map<String, String> _isolateSanitizeAndHash(Map<String, dynamic> params) {
  final rawText = params['text'] as String? ?? '';
  final characterId = params['characterId'] as String? ?? 'eve';
  final language = params['language'] as String? ?? 'en';
  final speedMultiplier = (params['speedMultiplier'] as num?)?.toDouble() ?? 0.85;
  final pitch = (params['pitch'] as num?)?.toDouble() ?? 1.0;
  final baseRate = (params['baseRate'] as num?)?.toDouble() ?? 0.39;
  final neuralVoiceId = params['neuralVoiceId'] as String? ?? '';
  final voiceEngineVersion = params['voiceEngineVersion'] as String? ?? 'legacy';

  final cleanText = rawText
      .replaceAll(RegExp(r'\*+'), '')
      .replaceAll(RegExp(r'#+'), '')
      .replaceAll(RegExp(r'\[.*?\]'), '')
      .replaceAll(RegExp(r'[\u{1F600}-\u{1F64F}|\u{1F300}-\u{1F5FF}|\u{1F680}-\u{1F6FF}|\u{1F1E0}-\u{1F1FF}|\u{2600}-\u{26FF}|\u{2700}-\u{27BF}]', unicode: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final signature = 'text=$cleanText|char=$characterId|lang=$language|speed=${speedMultiplier.toStringAsFixed(3)}|pitch=${pitch.toStringAsFixed(3)}|rate=${baseRate.toStringAsFixed(3)}|neural=$neuralVoiceId|engine=$voiceEngineVersion';
  final bytes = utf8.encode(signature);
  final digest = sha256.convert(bytes);

  return {
    'cleanText': cleanText,
    'hashKey': digest.toString(),
  };
}

class LocalVoiceCacheManager {
  static final LocalVoiceCacheManager _instance = LocalVoiceCacheManager._internal();
  static LocalVoiceCacheManager get instance => _instance;

  Directory? _cacheDir;
  static const int _maxCacheSizeBytes = 100 * 1024 * 1024;

  LocalVoiceCacheManager._internal();

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
      return _isolateSanitizeAndHash(params);
    }
  }

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
      _pruneCacheIfNeeded();
      return file;
    } catch (e) {
      debugPrint('[LocalVoiceCacheManager] Save audio error: $e');
      return null;
    }
  }

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
