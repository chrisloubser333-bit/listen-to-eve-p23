import 'package:flutter/material.dart';

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
    final scheme = Theme.of(context).colorScheme;
    Color glowColor;
    Color bgColor;
    IconData icon;

    if (isListening) {
      glowColor = scheme.tertiary;
      bgColor = scheme.tertiary.withValues(alpha: 0.18);
      icon = Icons.mic;
    } else if (isSpeaking) {
      glowColor = scheme.secondary;
      bgColor = scheme.secondary.withValues(alpha: 0.18);
      icon = Icons.volume_up_rounded;
    } else {
      glowColor = scheme.primary;
      bgColor = scheme.surfaceContainerHighest;
      icon = Icons.mic_none_rounded;
    }

    final active = isListening || isSpeaking;

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
            color: glowColor.withValues(alpha: active ? 0.9 : 0.45),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: active ? 0.45 : 0.16),
              blurRadius: active ? 18 : 10,
              spreadRadius: active ? 2 : 0,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: active ? glowColor : scheme.onSurface,
          size: 26,
        ),
      ),
    );
  }
}
