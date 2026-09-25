import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Top-level or static decode function suitable for background isolates via compute().
Uint8List _decodeBase64Payload(String cleanBase64) {
  return base64Decode(cleanBase64);
}

/// Production-hardened manager for local image persistence.
///
/// Prevents SharedPreferences bloat, high startup memory, and OOM crashes by:
/// 1. Decoding Base64/data-URI payloads in a background isolate.
/// 2. Storing raw binary bytes in the app's private document/support directory.
/// 3. Returning lightweight local filesystem paths (e.g. `/.../generated_images/img_<uuid>.jpg`).
/// 4. Guaranteeing that large Base64 strings are never stored in SharedPreferences.
class LocalImageStorageManager {
  static final LocalImageStorageManager _instance = LocalImageStorageManager._internal();
  static LocalImageStorageManager get instance => _instance;

  final Uuid _uuid = const Uuid();
  Directory? _storageDir;
  bool _isInitializing = false;

  LocalImageStorageManager._internal();

  /// Returns the private local directory used for storing generated images.
  Future<Directory> getStorageDirectory() async {
    if (_storageDir != null && await _storageDir!.exists()) {
      return _storageDir!;
    }

    if (kIsWeb) {
      throw UnsupportedError('Local filesystem storage is not supported on Web.');
    }

    Directory baseDir;
    try {
      baseDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      baseDir = await getApplicationSupportDirectory();
    }

    final imagesDir = Directory('${baseDir.path}/generated_images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    _storageDir = imagesDir;
    return _storageDir!;
  }

  /// Determines if a given string represents a Base64 or data URI payload.
  bool isBase64Payload(String? str) {
    if (str == null || str.trim().isEmpty) return false;
    final trimmed = str.trim();
    if (trimmed.startsWith('data:image')) return true;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return false;
    if (trimmed.startsWith('/') || trimmed.startsWith('file://')) return false;
    if (trimmed.startsWith('assets/')) return false;

    // Check for raw Base64: long string without path delimiters, containing valid base64 chars
    if (trimmed.length > 80 && !trimmed.contains('\n') && !trimmed.contains(' ')) {
      final base64Regex = RegExp(r'^[A-Za-z0-9+/=]+$');
      final sample = trimmed.length > 200 ? trimmed.substring(0, 200) : trimmed;
      return base64Regex.hasMatch(sample);
    }
    return false;
  }

  /// Inspects header or magic bytes to determine the appropriate image file extension.
  String detectExtension(String payload, [Uint8List? decodedBytes]) {
    final lower = payload.toLowerCase();
    if (lower.startsWith('data:image/jpeg') || lower.startsWith('data:image/jpg')) {
      return 'jpg';
    }
    if (lower.startsWith('data:image/png')) {
      return 'png';
    }
    if (lower.startsWith('data:image/webp')) {
      return 'webp';
    }
    if (lower.startsWith('data:image/gif')) {
      return 'gif';
    }

    if (decodedBytes != null && decodedBytes.length >= 8) {
      // JPEG magic bytes: FF D8 FF
      if (decodedBytes[0] == 0xFF && decodedBytes[1] == 0xD8 && decodedBytes[2] == 0xFF) {
        return 'jpg';
      }
      // PNG magic bytes: 89 50 4E 47
      if (decodedBytes[0] == 0x89 &&
          decodedBytes[1] == 0x50 &&
          decodedBytes[2] == 0x4E &&
          decodedBytes[3] == 0x47) {
        return 'png';
      }
      // WEBP magic bytes: RIFF....WEBP
      if (decodedBytes[0] == 0x52 &&
          decodedBytes[1] == 0x49 &&
          decodedBytes[2] == 0x46 &&
          decodedBytes[3] == 0x46) {
        return 'webp';
      }
    }

    return 'jpg';
  }

  /// Persists a Base64 or data-URI image payload to a local binary file.
  ///
  /// - Returns a lightweight local filesystem path.
  /// - If the payload is already a local path or remote URL, it is returned unchanged.
  /// - Offloads Base64 decoding to a background isolate via [compute] to prevent UI stalls.
  Future<String> persistImagePayload(
    String payload, {
    String? imageId,
    String? prefix,
  }) async {
    final trimmed = payload.trim();
    if (trimmed.isEmpty) return '';

    // If it is already a local file path or remote URL, preserve it
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('/') ||
        trimmed.startsWith('file://') ||
        trimmed.startsWith('assets/')) {
      return trimmed;
    }

    // On web, filesystem is not available; return trimmed data URI directly
    if (kIsWeb) {
      return trimmed;
    }

    // Extract raw base64 string
    String cleanBase64;
    final commaIdx = trimmed.indexOf(',');
    if (trimmed.startsWith('data:image') && commaIdx != -1) {
      cleanBase64 = trimmed.substring(commaIdx + 1).trim();
    } else {
      cleanBase64 = trimmed;
    }

    // Strip whitespace or newlines that may have been injected
    cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');

    // Decode in background isolate to prevent UI frame drops
    final Uint8List bytes;
    try {
      bytes = await compute(_decodeBase64Payload, cleanBase64);
    } catch (e) {
      debugPrint('[LocalImageStorageManager] Failed to decode base64 payload: $e');
      rethrow;
    }

    if (bytes.isEmpty) {
      throw const FormatException('Decoded image bytes are empty.');
    }

    final ext = detectExtension(trimmed, bytes);
    final dir = await getStorageDirectory();

    // Generate collision-safe filename
    final uniqueId = imageId ?? _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePrefix = prefix != null ? '${prefix}_' : 'img_';
    final fileName = '${filePrefix}${timestamp}_${uniqueId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '')}.$ext';
    final targetFile = File('${dir.path}/$fileName');

    // Asynchronously write bytes to disk
    await targetFile.writeAsBytes(bytes, flush: true);

    debugPrint('[LocalImageStorageManager] Persisted image (${bytes.lengthInBytes} bytes) to ${targetFile.path}');
    return targetFile.path;
  }

  /// Checks whether a local file path exists.
  Future<bool> imageExists(String filePath) async {
    if (kIsWeb || filePath.isEmpty) return false;
    try {
      return await File(filePath).exists();
    } catch (_) {
      return false;
    }
  }

  /// Deletes a local image file.
  Future<bool> deleteImage(String filePath) async {
    if (kIsWeb || filePath.isEmpty) return false;
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[LocalImageStorageManager] Deleted image: $filePath');
        return true;
      }
    } catch (e) {
      debugPrint('[LocalImageStorageManager] Error deleting image $filePath: $e');
    }
    return false;
  }

  /// Cleans up orphaned images in the storage directory that are no longer referenced.
  Future<int> cleanupUnusedImages(Set<String> activePaths) async {
    if (kIsWeb) return 0;
    int deletedCount = 0;
    try {
      final dir = await getStorageDirectory();
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File && !activePaths.contains(entity.path)) {
          await entity.delete();
          deletedCount++;
        }
      }
      if (deletedCount > 0) {
        debugPrint('[LocalImageStorageManager] Cleaned up $deletedCount orphaned images.');
      }
    } catch (e) {
      debugPrint('[LocalImageStorageManager] Cleanup error: $e');
    }
    return deletedCount;
  }
}
