export type MessageRole = 'user' | 'assistant' | 'system';

export type PersonaId = 'eve' | 'ara' | 'leo' | 'rex' | 'sal';

export interface PersonaConfig {
  id: PersonaId;
  name: string;
  appTitle: string;
  titleAfrikaans: string;
  signature: string;
  signatureIcon: string;
  avatarUrl: string;
  colorHex: string;
  secondaryHex: string;
  accentGradient: string;
  glowColor: string;
  defaultStatus: string;
  statusIconColor: string;
  description: string;
  systemPromptEn: string;
  systemPromptAf: string;
  starterMessages: {
    user: string;
    assistant: string;
    cardType?: 'image' | 'song' | 'workout' | 'planning';
    cardData?: any;
  }[];
}

export interface RichCardData {
  type: 'image' | 'song' | 'workout' | 'planning';
  title?: string;
  imageUrl?: string;
  imageUrls?: string[];
  audioDuration?: string;
  audioTitle?: string;
  audioUrl?: string;
  isPlaying?: boolean;
  statusText?: string;
  checklistItems?: { text: string; checked: boolean }[];
}

export interface ChatMessage {
  id: string;
  role: MessageRole;
  content: string;
  timestamp: string; // ISO date string or formatted
  isVoice?: boolean;
  audioPath?: string;
  personaId?: PersonaId;
  richCard?: RichCardData;
}

export interface VoiceOption {
  id: string;
  name: string;
  description: string;
  isCustom?: boolean;
  gender?: 'female' | 'male' | 'neutral';
  tone?: 'friendly' | 'warm' | 'confident' | 'energetic' | 'casual' | 'custom';
}

export interface MemoryItem {
  id: string;
  content: string;
  type: 'health' | 'preference' | 'goal' | 'fact' | 'other';
  importance: number;
  createdAt: string;
}

export interface AppSettings {
  language: 'en' | 'af';
  voiceId: string;
  activePersona: PersonaId;
  darkMode: boolean;
  apiKey: string;
  customVoices: VoiceOption[];
  speechSpeed?: number;
}
