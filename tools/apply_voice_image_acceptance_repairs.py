from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"ABORT: expected block not found in {path}")
    p.write_text(text.replace(old, new, 1))
    print(f"patched {path}")


# 1) Dependencies: native gallery save + platform share sheet.
pub = Path("pubspec.yaml")
text = pub.read_text()
needle = "  path_provider: ^2.1.4\n"
addition = "  path_provider: ^2.1.4\n  gal: ^2.3.0\n  share_plus: ^12.0.0\n  cross_file: ^0.3.5\n"
if "  gal:" not in text:
    if needle not in text:
        raise SystemExit("ABORT: path_provider dependency anchor missing")
    pub.write_text(text.replace(needle, addition, 1))
    print("patched pubspec.yaml")

# 2) VoiceService: expose an exact playback-start callback. This is fired when
# JustAudio actually begins play, or from flutter_tts's native start handler.
voice = Path("lib/services/voice_service.dart")
text = voice.read_text()
if "Function()? _pendingPlaybackStarted;" not in text:
    text = text.replace(
        "  Function(bool isSpeaking)? onSpeakingStateChanged;\n",
        "  Function(bool isSpeaking)? onSpeakingStateChanged;\n  Function()? _pendingPlaybackStarted;\n",
        1,
    )
    text = text.replace(
        "      _flutterTts.setStartHandler(() {\n        _isSpeaking = true;\n        onSpeakingStateChanged?.call(true);\n",
        "      _flutterTts.setStartHandler(() {\n        _isSpeaking = true;\n        onSpeakingStateChanged?.call(true);\n        _notifyPlaybackStarted();\n",
        1,
    )
    text = text.replace(
        "  Future<void> speak({\n    required String text,\n    required String characterId,\n    required String language,\n    double speedMultiplier = 0.85,\n  }) async {\n",
        "  Future<void> speak({\n    required String text,\n    required String characterId,\n    required String language,\n    double speedMultiplier = 0.85,\n    Function()? onPlaybackStarted,\n  }) async {\n",
        1,
    )
    text = text.replace(
        "    final currentRequestId = ++_activeSpeechRequestId;\n\n    // Interrupt/stop any currently active playback/synthesis\n",
        "    final currentRequestId = ++_activeSpeechRequestId;\n    _pendingPlaybackStarted = onPlaybackStarted;\n\n    // Interrupt/stop any currently active playback/synthesis\n",
        1,
    )
    # Neural/cache path: callback immediately before actual player.play().
    text = text.replace(
        "      await _audioPlayer.setFilePath(file.path);\n      await _audioPlayer.play();\n",
        "      await _audioPlayer.setFilePath(file.path);\n      _notifyPlaybackStarted();\n      await _audioPlayer.play();\n",
        1,
    )
    text = text.replace(
        "      await _audioPlayer.setAudioSource(source);\n      await _audioPlayer.play();\n",
        "      await _audioPlayer.setAudioSource(source);\n      _notifyPlaybackStarted();\n      await _audioPlayer.play();\n",
        1,
    )
    marker = "  Future<void> _stopActiveEngines() async {\n"
    helper = "  void _notifyPlaybackStarted() {\n    final callback = _pendingPlaybackStarted;\n    _pendingPlaybackStarted = null;\n    if (callback != null) {\n      try {\n        callback();\n      } catch (e) {\n        debugPrint('[VoiceService] playback-start callback error: $e');\n      }\n    }\n  }\n\n"
    if marker not in text:
        raise SystemExit("ABORT: VoiceService helper anchor missing")
    text = text.replace(marker, helper + marker, 1)
    # Clear stale callbacks on interruption.
    text = text.replace(
        "  Future<void> stopSpeaking() async {\n    _activeSpeechRequestId++;\n",
        "  Future<void> stopSpeaking() async {\n    _activeSpeechRequestId++;\n    _pendingPlaybackStarted = null;\n",
        1,
    )
    voice.write_text(text)
    print("patched lib/services/voice_service.dart")

# 3) ChatProvider: keep assistant reply hidden while neural audio is being
# prepared, reveal it on playback start, and guarantee a fallback reveal if
# speech cannot start.
chat = Path("lib/providers/chat_provider.dart")
text = chat.read_text()
old = """      final assistantMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: finalReply,
        timestamp: DateTime.now(),
      );
      _messages.add(assistantMsg);

      // Speak the reply with character-specific humanized voice
      if (_settings.autoVoiceReply && finalReply.trim().isNotEmpty) {
        // Fire and let TTS speak without blocking the UI
        _voiceService.speak(
          text: finalReply,
          characterId: _settings.characterId,
          language: _settings.language,
          speedMultiplier: _settings.speechSpeed,
        );
      }

      await _storage.saveMessages(_messages);
"""
new = """      final assistantMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: finalReply,
        timestamp: DateTime.now(),
      );

      // Voice/text synchronization: when automatic voice is enabled, do not
      // reveal the assistant bubble while neural audio is still synthesizing.
      // Reveal it at the exact playback-start signal. If voice fails before
      // playback starts, reveal after speak() returns so text is never lost.
      if (_settings.autoVoiceReply && finalReply.trim().isNotEmpty) {
        var revealed = false;
        void revealReply() {
          if (revealed) return;
          revealed = true;
          _messages.add(assistantMsg);
          notifyListeners();
        }

        try {
          await _voiceService.speak(
            text: finalReply,
            characterId: _settings.characterId,
            language: _settings.language,
            speedMultiplier: _settings.speechSpeed,
            onPlaybackStarted: revealReply,
          );
        } catch (voiceErr) {
          debugPrint('Voice reply error (non-fatal): $voiceErr');
        } finally {
          revealReply();
        }
      } else {
        _messages.add(assistantMsg);
      }

      await _storage.saveMessages(_messages);
"""
if old in text:
    chat.write_text(text.replace(old, new, 1))
    print("patched lib/providers/chat_provider.dart")
elif "onPlaybackStarted: revealReply" not in text:
    raise SystemExit("ABORT: ChatProvider response block not found")

# 4) Exploded image modal: replace clipboard-only fake save/share with real
# bytes -> gallery and real image file -> native platform share sheet.
modal = Path("lib/widgets/exploded_image_modal.dart")
text = modal.read_text()
text = text.replace("import 'package:flutter/services.dart';\n", "import 'package:flutter/services.dart';\nimport 'package:http/http.dart' as http;\nimport 'package:gal/gal.dart';\nimport 'package:share_plus/share_plus.dart';\nimport 'package:cross_file/cross_file.dart';\nimport 'package:path_provider/path_provider.dart';\n")
start = text.find("  void _handleSave(BuildContext context) {")
end = text.find("  Widget _buildImageContent() {", start)
if start == -1 or end == -1:
    if "Future<Uint8List> _resolveImageBytes()" not in text:
        raise SystemExit("ABORT: image save/share handlers not found")
else:
    handlers = r'''  Future<Uint8List> _resolveImageBytes() async {
    if (assetPath != null && assetPath!.isNotEmpty) {
      final data = await rootBundle.load(assetPath!);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }

    final source = imageUrl?.trim() ?? '';
    if (source.startsWith('data:image')) {
      final comma = source.indexOf(',');
      if (comma < 0) throw Exception('Invalid image data');
      return base64Decode(source.substring(comma + 1));
    }

    if (source.startsWith('/') || source.startsWith('file://')) {
      final path = source.startsWith('file://') ? source.substring(7) : source;
      return File(path).readAsBytes();
    }

    if (source.startsWith('http://') || source.startsWith('https://')) {
      final response = await http.get(Uri.parse(source)).timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300 || response.bodyBytes.isEmpty) {
        throw Exception('Image download failed (${response.statusCode})');
      }
      return response.bodyBytes;
    }

    throw Exception('No image data is available');
  }

  String _safeFileName() {
    final cleaned = title.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    return '${cleaned.isEmpty ? 'listen_to_eve_image' : cleaned}_${DateTime.now().millisecondsSinceEpoch}.jpg';
  }

  Future<void> _handleSave(BuildContext context) async {
    try {
      final bytes = await _resolveImageBytes();
      await Gal.putImageBytes(bytes, name: _safeFileName());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isAvatar ? '$title portrait saved to Photos.' : 'Image saved to Photos.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save image: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleShare(BuildContext context) async {
    try {
      final bytes = await _resolveImageBytes();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${_safeFileName()}');
      await file.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;

      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/jpeg')],
          text: 'Listen to Eve — $title',
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not share image: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

'''
    text = text[:start] + handlers + text[end:]
    text = text.replace("onPressed: () => _handleSave(context),", "onPressed: () async => _handleSave(context),")
    text = text.replace("onPressed: () => _handleShare(context),", "onPressed: () async => _handleShare(context),")
    modal.write_text(text)
    print("patched lib/widgets/exploded_image_modal.dart")

print("Voice/text synchronization and native image save/share repairs applied successfully.")
