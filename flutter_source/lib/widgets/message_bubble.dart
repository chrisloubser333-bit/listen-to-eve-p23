import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          // Glass-style backgrounds with neon tint
          gradient: isUser
              ? LinearGradient(
                  colors: [
                    AppTheme.primary.withOpacity(0.22),
                    AppTheme.primary.withOpacity(0.10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : LinearGradient(
                  colors: [
                    AppTheme.secondary.withOpacity(0.20),
                    AppTheme.secondary.withOpacity(0.08),
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
                ? AppTheme.primary.withOpacity(0.35)
                : AppTheme.secondary.withOpacity(0.30),
            width: 1,
          ),
          boxShadow: isUser
              ? AppTheme.glow(AppTheme.primary, blur: 10, spread: 0)
              : AppTheme.glow(AppTheme.secondary, blur: 10, spread: 0),
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
                  color: isUser
                      ? AppTheme.primary.withOpacity(0.8)
                      : AppTheme.secondary.withOpacity(0.8),
                ),
              ),
            SelectableText(
              message.content,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                color: AppTheme.textSecondary.withOpacity(0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
