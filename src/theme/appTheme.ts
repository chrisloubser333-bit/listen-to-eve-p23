/**
 * Futuristic "Soft Neon" theme for Listen to Eve (LTE)
 * Direct reproduction of lib/theme/app_theme.dart
 */

export const AppTheme = {
  // Core colours
  background: '#0B0F1A',
  surface: '#151B2D',
  surfaceLight: '#1E263C',
  primary: '#00F0FF',      // Electric Cyan
  secondary: '#A855F7',    // Neon Purple
  accent: '#FF4ECD',       // Soft Magenta
  success: '#2EE6A6',      // Neon Teal
  textPrimary: '#F0F4FF',
  textSecondary: '#94A3B8',
  border: '#2A3348',
  danger: '#FF6B6B',
  warning: '#FFB020',

  // Default built-in Grok voices
  defaultVoices: [
    {
      id: 'eve',
      name: 'Eve',
      description: 'Clear, friendly, general-purpose',
      gender: 'female',
      tone: 'friendly',
    },
    {
      id: 'ara',
      name: 'Ara',
      description: 'Warm and conversational',
      gender: 'female',
      tone: 'warm',
    },
    {
      id: 'leo',
      name: 'Leo',
      description: 'Confident and direct',
      gender: 'male',
      tone: 'confident',
    },
    {
      id: 'rex',
      name: 'Rex',
      description: 'Energetic and characterful',
      gender: 'male',
      tone: 'energetic',
    },
    {
      id: 'sal',
      name: 'Sal',
      description: 'Distinctive conversational tone',
      gender: 'neutral',
      tone: 'casual',
    },
  ] as const,
};
