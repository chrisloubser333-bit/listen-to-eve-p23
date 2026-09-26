import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';

/// Interactive high-resolution viewer for avatars and AI-generated artwork.
/// Supports smooth pinch-to-zoom, pan, download/save to device, and sharing.
class ExplodedImageModal extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? assetPath;
  final String? imageUrl;
  final Color accentColor;
  final bool isAvatar;

  const ExplodedImageModal({
    super.key,
    required this.title,
    this.subtitle,
    this.assetPath,
    this.imageUrl,
    this.accentColor = AppTheme.primary,
    this.isAvatar = false,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    String? subtitle,
    String? assetPath,
    String? imageUrl,
    Color accentColor = AppTheme.primary,
    bool isAvatar = false,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.92),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, anim1, anim2) {
        return ExplodedImageModal(
          title: title,
          subtitle: subtitle,
          assetPath: assetPath,
          imageUrl: imageUrl,
          accentColor: accentColor,
          isAvatar: isAvatar,
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  Future<Uint8List> _resolveImageBytes() async {
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
      final response = await http
          .get(Uri.parse(source))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          response.bodyBytes.isEmpty) {
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
          content: Text(isAvatar
              ? "$title's portrait was saved to your gallery."
              : 'Image saved to your gallery.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not save image: $e'),
            behavior: SnackBarBehavior.floating),
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
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not share image: $e'),
            behavior: SnackBarBehavior.floating),
      );
    }
  }

  Widget _buildImageContent() {
    if (assetPath != null && assetPath!.isNotEmpty) {
      return Image.asset(
        assetPath!,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          Icons.image_not_supported_rounded,
          size: 80,
          color: accentColor.withOpacity(0.5),
        ),
      );
    }

    if (imageUrl != null && imageUrl!.startsWith('data:image')) {
      try {
        final commaIdx = imageUrl!.indexOf(',');
        final base64Str =
            commaIdx != -1 ? imageUrl!.substring(commaIdx + 1) : imageUrl!;
        final bytes = base64Decode(base64Str);
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            Icons.broken_image_rounded,
            size: 80,
            color: accentColor.withOpacity(0.5),
          ),
        );
      } catch (_) {
        return const Icon(Icons.broken_image_rounded,
            size: 80, color: Colors.grey);
      }
    }

    if (imageUrl != null &&
        (imageUrl!.startsWith('/') || imageUrl!.startsWith('file://'))) {
      try {
        final cleanPath = imageUrl!.startsWith('file://')
            ? imageUrl!.replaceFirst('file://', '')
            : imageUrl!;
        final file = File(cleanPath);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(
              Icons.broken_image_rounded,
              size: 80,
              color: accentColor.withOpacity(0.5),
            ),
          );
        } else {
          return Icon(
            Icons.image_not_supported_rounded,
            size: 80,
            color: accentColor.withOpacity(0.5),
          );
        }
      } catch (_) {
        return const Icon(Icons.broken_image_rounded,
            size: 80, color: Colors.grey);
      }
    }

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!
                  : null,
              color: accentColor,
            ),
          );
        },
        errorBuilder: (_, __, ___) => Icon(
          Icons.broken_image_rounded,
          size: 80,
          color: accentColor.withOpacity(0.5),
        ),
      );
    }

    return Icon(Icons.person_rounded, size: 100, color: accentColor);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            // Interactive Zoom Canvas
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                panEnabled: true,
                scaleEnabled: true,
                child: Center(
                  child: Container(
                    constraints:
                        const BoxConstraints(maxWidth: 500, maxHeight: 560),
                    margin: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 60),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: accentColor.withOpacity(0.6),
                        width: 2.0,
                      ),
                      boxShadow:
                          AppTheme.glow(accentColor, blur: 30, spread: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildImageContent(),
                  ),
                ),
              ),
            ),

            // Top Header: Title, Subtitle, and Close Button
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 28),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.6),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Text(
                            subtitle!,
                            style: TextStyle(
                              color: accentColor.withOpacity(0.9),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Action Bar: Download/Save & Share
            Positioned(
              bottom: 24,
              left: 20,
              right: 20,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppTheme.border.withOpacity(0.8),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Download / Save Button
                      ElevatedButton.icon(
                        onPressed: () async => _handleSave(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: AppTheme.background,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                        ),
                        icon: const Icon(Icons.download_rounded, size: 20),
                        label: Text(
                          isAvatar ? 'Save Portrait' : 'Save Image',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Share Button
                      OutlinedButton.icon(
                        onPressed: () async => _handleShare(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                              color: accentColor.withOpacity(0.7), width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text(
                          'Share',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
