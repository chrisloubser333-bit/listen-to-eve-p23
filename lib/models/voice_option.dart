class VoiceOption {
  final String id;
  final String name;
  final String description;
  final bool isCustom;
  final String? gender;
  final String? tone;

  const VoiceOption({
    required this.id,
    required this.name,
    required this.description,
    this.isCustom = false,
    this.gender,
    this.tone,
  });

  // Default built-in voice options
  static const List<VoiceOption> defaults = [
    VoiceOption(
      id: 'eve',
      name: 'Eve',
      description: 'Clear, friendly, general-purpose',
      gender: 'female',
      tone: 'friendly',
    ),
    VoiceOption(
      id: 'ara',
      name: 'Ara',
      description: 'Warm and conversational',
      gender: 'female',
      tone: 'warm',
    ),
    VoiceOption(
      id: 'leo',
      name: 'Leo',
      description: 'Confident and direct',
      gender: 'male',
      tone: 'confident',
    ),
    VoiceOption(
      id: 'rex',
      name: 'Rex',
      description: 'Energetic and characterful',
      gender: 'male',
      tone: 'energetic',
    ),
    VoiceOption(
      id: 'sal',
      name: 'Sal',
      description: 'Distinctive conversational tone',
      gender: 'neutral',
      tone: 'casual',
    ),
  ];
}
