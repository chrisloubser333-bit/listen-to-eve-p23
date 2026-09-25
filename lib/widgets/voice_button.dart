import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class VoiceButton extends StatelessWidget {
  final bool isListening;
  final bool isSpeaking;
  final VoidCallback onPressed;

  const VoiceButton({
    super.key,
    required this.isListening,
    required this.isSpeaking,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    Color glowColor;
    Color bgColor;
    IconData icon;

    if (isListening) {
      glowColor = AppTheme.accent;
      bgColor = AppTheme.accent.withOpacity(0.25);
      icon = Icons.mic;
    } else if (isSpeaking) {
      glowColor = AppTheme.secondary;
      bgColor = AppTheme.secondary.withOpacity(0.25);
      icon = Icons.volume_up_rounded;
    } else {
      glowColor = AppTheme.primary;
      bgColor = AppTheme.surfaceLight;
      icon = Icons.mic_none_rounded;
    }

    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bgColor,
          border: Border.all(
            color: glowColor.withOpacity(isListening || isSpeaking ? 0.9 : 0.45),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor.withOpacity(isListening || isSpeaking ? 0.55 : 0.22),
              blurRadius: isListening || isSpeaking ? 18 : 10,
              spreadRadius: isListening || isSpeaking ? 2 : 0,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: isListening || isSpeaking ? glowColor : AppTheme.textPrimary,
          size: 26,
        ),
      ),
    );
  }
}
