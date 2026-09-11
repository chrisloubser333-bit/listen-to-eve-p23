/**
 * Voice Service: Handles Text-to-Speech (voice replies)
 * and Speech Recognition / Audio recording for Listen to Eve
 */

export interface VoiceServiceCallbacks {
  onListeningChange?: (isListening: boolean) => void;
  onSpeakingChange?: (isSpeaking: boolean) => void;
  onTranscript?: (transcript: string) => void;
  onError?: (error: string) => void;
}

// Global speech synthesis tracker to prevent garbage collection bugs
let currentUtterance: SpeechSynthesisUtterance | null = null;

export const voiceService = {
  // Speaks text aloud using the selected voice and language
  speak(
    text: string,
    voiceId: string = 'eve',
    language: 'en' | 'af' = 'en',
    onStart?: () => void,
    onEnd?: () => void,
    speedMultiplier: number = 0.85
  ): void {
    if (!('speechSynthesis' in window)) {
      console.warn('SpeechSynthesis is not supported in this browser.');
      onEnd?.();
      return;
    }

    window.speechSynthesis.cancel();

    // Clean text of markdown asterisks or code formatting
    const cleanText = text.replace(/[*_#`]/g, '').trim();
    if (!cleanText) {
      onEnd?.();
      return;
    }

    const utterance = new SpeechSynthesisUtterance(cleanText);
    currentUtterance = utterance;

    // Pitch and rate adjustments (calm, natural human pacing)
    let baseRate = 0.88;
    switch (voiceId) {
      case 'eve':
        utterance.pitch = 1.04;
        baseRate = 0.86;
        break;
      case 'ara':
        utterance.pitch = 0.96;
        baseRate = 0.84;
        break;
      case 'leo':
        utterance.pitch = 0.88;
        baseRate = 0.90;
        break;
      case 'rex':
        utterance.pitch = 0.92;
        baseRate = 0.94;
        break;
      case 'sal':
        utterance.pitch = 0.84;
        baseRate = 0.82;
        break;
      default:
        utterance.pitch = 1.0;
        baseRate = 0.88;
    }

    utterance.rate = Math.max(0.4, Math.min(1.5, baseRate * (speedMultiplier / 0.85)));

    utterance.lang = language === 'af' ? 'af-ZA' : 'en-US';

    const voices = window.speechSynthesis.getVoices();
    if (voices.length > 0) {
      // Find matching language voice
      const langVoices = voices.filter((v) =>
        language === 'af' ? v.lang.startsWith('af') : v.lang.startsWith('en')
      );

      const targetGender = (voiceId === 'leo' || voiceId === 'rex' || voiceId === 'sal') ? 'male' : 'female';
      const matched = langVoices.find((v) =>
        v.name.toLowerCase().includes(targetGender)
      ) || langVoices[0];

      if (matched) {
        utterance.voice = matched;
      }
    }

    utterance.onstart = () => {
      onStart?.();
    };

    utterance.onend = () => {
      currentUtterance = null;
      onEnd?.();
    };

    utterance.onerror = () => {
      currentUtterance = null;
      onEnd?.();
    };

    window.speechSynthesis.speak(utterance);
  },

  stopSpeaking(): void {
    if ('speechSynthesis' in window) {
      window.speechSynthesis.cancel();
    }
  },

  // Speech to Text (Microphone listening)
  createRecognition(
    language: 'en' | 'af',
    onResult: (text: string) => void,
    onError: (err: string) => void,
    onEnd: () => void
  ): { start: () => void; stop: () => void } | null {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const SpeechRecognitionAPI = (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition;

    if (!SpeechRecognitionAPI) {
      return null;
    }

    const recognition = new SpeechRecognitionAPI();
    recognition.continuous = false;
    recognition.interimResults = true;
    recognition.lang = language === 'af' ? 'af-ZA' : 'en-US';

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    recognition.onresult = (event: any) => {
      let finalTranscript = '';
      for (let i = event.resultIndex; i < event.results.length; ++i) {
        if (event.results[i].isFinal) {
          finalTranscript += event.results[i][0].transcript;
        }
      }
      if (finalTranscript) {
        onResult(finalTranscript.trim());
      }
    };

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    recognition.onerror = (event: any) => {
      onError(event.error || 'Speech recognition error');
    };

    recognition.onend = () => {
      onEnd();
    };

    return {
      start: () => {
        try {
          recognition.start();
        } catch (e) {
          console.warn('Recognition start error:', e);
        }
      },
      stop: () => {
        try {
          recognition.stop();
        } catch (e) {
          console.warn('Recognition stop error:', e);
        }
      },
    };
  },
};
