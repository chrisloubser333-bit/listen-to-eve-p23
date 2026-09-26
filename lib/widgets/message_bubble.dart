import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';
import 'exploded_image_modal.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String? avatarAsset;
  final Color accentColor;

  const MessageBubble({
    super.key,
    required this.message,
    this.avatarAsset,
    this.accentColor = AppTheme.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: AppTheme.glow(accentColor, blur: 8, spread: 0),
              ),
              child: ClipOval(
                child: avatarAsset != null
                    ? Image.asset(
                        avatarAsset!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.face_3_rounded,
                          size: 18,
                          color: accentColor,
                        ),
                      )
                    : Icon(Icons.face_3_rounded, size: 18, color: accentColor),
              ),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.76,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isUser
                      ? [
                          primary.withValues(alpha: 0.18),
                          scheme.surface.withValues(alpha: 0.96),
                        ]
                      : [
                          accentColor.withValues(alpha: 0.16),
                          scheme.surface.withValues(alpha: 0.96),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 18),
                ),
                border: Border.all(
                  color: isUser
                      ? primary.withValues(alpha: 0.35)
                      : accentColor.withValues(alpha: 0.30),
                  width: 1,
                ),
                boxShadow: isUser
                    ? AppTheme.glow(primary, blur: 10, spread: 0)
                    : AppTheme.glow(accentColor, blur: 10, spread: 0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.isVoice)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        size: 16,
                        color: (isUser ? primary : scheme.secondary)
                            .withValues(alpha: 0.8),
                      ),
                    ),
                  if (message.isImage && message.imageUrl != null)
                    _buildImageContent(context, message.imageUrl!),
                  SelectableText(
                    message.content,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15.5,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageContent(BuildContext context, String imageUrl) {
    final scheme = Theme.of(context).colorScheme;
    debugPrint('[IMAGE_RENDER_REQUEST] Rendering image in MessageBubble: ${imageUrl.startsWith("/") ? "Local File Path" : (imageUrl.startsWith("http") ? "Remote URL" : "Data URI")}');
    Widget imageWidget;
    if (imageUrl.startsWith('data:image')) {
      try {
        final commaIdx = imageUrl.indexOf(',');
        final base64Str = commaIdx != -1 ? imageUrl.substring(commaIdx + 1) : imageUrl;
        final bytes = base64Decode(base64Str);
        imageWidget = Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildImageError(context),
        );
      } catch (_) {
        imageWidget = _buildImageError(context);
      }
    } else if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      imageWidget = Image.network(
        imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            height: 180,
            color: scheme.surfaceContainerHighest,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
                color: accentColor,
                strokeWidth: 2.5,
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _buildImageError(context),
      );
    } else if (imageUrl.startsWith('/') || imageUrl.startsWith('file://')) {
      final cleanPath = imageUrl.startsWith('file://')
          ? imageUrl.replaceFirst('file://', '')
          : imageUrl;
      final file = File(cleanPath);
      imageWidget = file.existsSync()
          ? Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildImageError(context),
            )
          : _buildImageError(context);
    } else {
      imageWidget = Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildImageError(context),
      );
    }

    return GestureDetector(
      onTap: () {
        ExplodedImageModal.show(
          context,
          title: message.imagePrompt ?? 'Generated Artwork',
          subtitle: message.content,
          imageUrl: imageUrl,
          accentColor: accentColor,
          isAvatar: false,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withValues(alpha: 0.35), width: 1),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.18),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 260,
                minHeight: 120,
                minWidth: double.infinity,
              ),
              child: imageWidget,
            ),
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24, width: 0.8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Zoom',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageError(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 140,
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_rounded,
            size: 36,
            color: accentColor.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 6),
          Text(
            'Unable to preview image',
            style: TextStyle(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
