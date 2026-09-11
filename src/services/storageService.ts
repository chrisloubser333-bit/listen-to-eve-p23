import { ChatMessage, MemoryItem, VoiceOption, PersonaId } from '../types';

const KEY_API_KEY = 'xai_api_key';
const KEY_LANGUAGE = 'preferred_language';
const KEY_VOICE_ID = 'selected_voice_id';
const KEY_ACTIVE_PERSONA = 'active_persona_id';
const KEY_DARK_MODE = 'dark_mode';
const KEY_MESSAGES = 'chat_messages';
const KEY_MEMORIES = 'user_memories';
const KEY_CUSTOM_VOICES = 'custom_voices';

export const storageService = {
  // Active Persona
  getActivePersona(): PersonaId {
    const p = localStorage.getItem(KEY_ACTIVE_PERSONA);
    if (p === 'ara' || p === 'leo' || p === 'rex' || p === 'sal' || p === 'eve') {
      return p;
    }
    return 'eve';
  },
  setActivePersona(personaId: PersonaId): void {
    localStorage.setItem(KEY_ACTIVE_PERSONA, personaId);
  },
  // API Key
  getApiKey(): string {
    return localStorage.getItem(KEY_API_KEY) || '';
  },
  setApiKey(key: string): void {
    localStorage.setItem(KEY_API_KEY, key.trim());
  },

  // Language ('en' or 'af')
  getLanguage(): 'en' | 'af' {
    const lang = localStorage.getItem(KEY_LANGUAGE);
    return lang === 'af' ? 'af' : 'en';
  },
  setLanguage(lang: 'en' | 'af'): void {
    localStorage.setItem(KEY_LANGUAGE, lang);
  },

  // Voice ID
  getVoiceId(): string {
    return localStorage.getItem(KEY_VOICE_ID) || 'eve';
  },
  setVoiceId(voiceId: string): void {
    localStorage.setItem(KEY_VOICE_ID, voiceId);
  },

  // Dark Mode
  getDarkMode(): boolean {
    const dm = localStorage.getItem(KEY_DARK_MODE);
    return dm === null ? true : dm === 'true';
  },
  setDarkMode(val: boolean): void {
    localStorage.setItem(KEY_DARK_MODE, String(val));
  },

  // Messages
  getMessages(): ChatMessage[] {
    const raw = localStorage.getItem(KEY_MESSAGES);
    if (!raw) return [];
    try {
      return JSON.parse(raw);
    } catch {
      return [];
    }
  },
  setMessages(messages: ChatMessage[]): void {
    localStorage.setItem(KEY_MESSAGES, JSON.stringify(messages));
  },
  clearMessages(): void {
    localStorage.removeItem(KEY_MESSAGES);
  },

  // Memories
  getMemories(): MemoryItem[] {
    const raw = localStorage.getItem(KEY_MEMORIES);
    if (!raw) {
      // Default initial memories matching Flutter MemoryScreen
      return [
        {
          id: '1',
          content: 'Asthma symptoms improve when avoiding cold air at night',
          type: 'health',
          importance: 5,
          createdAt: new Date(Date.now() - 2 * 86400000).toISOString(),
        },
        {
          id: '2',
          content: 'Prefers Eve as the main voice',
          type: 'preference',
          importance: 4,
          createdAt: new Date(Date.now() - 5 * 86400000).toISOString(),
        },
        {
          id: '3',
          content: 'Wants to practise more Afrikaans conversation',
          type: 'goal',
          importance: 3,
          createdAt: new Date(Date.now() - 1 * 86400000).toISOString(),
        },
      ];
    }
    try {
      return JSON.parse(raw);
    } catch {
      return [];
    }
  },
  setMemories(memories: MemoryItem[]): void {
    localStorage.setItem(KEY_MEMORIES, JSON.stringify(memories));
  },

  // Custom Voices
  getCustomVoices(): VoiceOption[] {
    const raw = localStorage.getItem(KEY_CUSTOM_VOICES);
    if (!raw) return [];
    try {
      return JSON.parse(raw);
    } catch {
      return [];
    }
  },
  setCustomVoices(voices: VoiceOption[]): void {
    localStorage.setItem(KEY_CUSTOM_VOICES, JSON.stringify(voices));
  },
};
