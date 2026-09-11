import React, { useState, useCallback, useMemo } from 'react';
import { ChatMessage, AppSettings, VoiceOption, PersonaId } from './types';
import { ChatScreen } from './screens/ChatScreen';
import { SettingsScreen } from './screens/SettingsScreen';
import { MemoryScreen } from './screens/MemoryScreen';
import { VoiceRecorderScreen } from './screens/VoiceRecorderScreen';
import { storageService } from './services/storageService';
import { aiService } from './services/aiService';
import { voiceService } from './services/voiceService';
import { PERSONAS, getStarterMessagesForPersona, eveAvatar, eveSelfie } from './data/personas';

type ActiveScreen = 'chat' | 'settings' | 'memory' | 'voices';

export default function App() {
  const [activeScreen, setActiveScreen] = useState<ActiveScreen>('chat');

  const [settings, setSettings] = useState<AppSettings>(() => ({
    language: storageService.getLanguage(),
    voiceId: storageService.getVoiceId(),
    activePersona: storageService.getActivePersona(),
    darkMode: storageService.getDarkMode(),
    apiKey: storageService.getApiKey(),
    customVoices: storageService.getCustomVoices(),
  }));

  // Store messages map by persona so each persona has their own conversation
  const [personaMessages, setPersonaMessages] = useState<Record<string, ChatMessage[]>>(() => {
    const saved = storageService.getMessages();
    if (saved && saved.length > 0) {
      // Migrate only specific legacy placeholder images, preserving full body and custom generated images
      const migrated = saved.map((m) => {
        const url = m.richCard?.imageUrl || '';
        const title = m.richCard?.title || '';
        const isLegacyPlaceholder =
          url.includes('eve_avatar_portrait') ||
          url.includes('eve_selfie_1788798758453') ||
          url.includes('eve_black_top_1788800610597');

        if (m.richCard?.type === 'image' && isLegacyPlaceholder && !title.toLowerCase().includes('full body')) {
          return {
            ...m,
            richCard: {
              ...m.richCard,
              imageUrl: eveSelfie,
            },
          };
        }
        return m;
      });
      return { [settings.activePersona]: migrated };
    }
    // Initialize with screenshot conversations for each persona
    return {
      eve: getStarterMessagesForPersona('eve'),
      ara: getStarterMessagesForPersona('ara'),
      leo: getStarterMessagesForPersona('leo'),
      rex: getStarterMessagesForPersona('rex'),
      sal: getStarterMessagesForPersona('sal'),
    };
  });

  const [isProcessing, setIsProcessing] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const currentPersona = useMemo(() => {
    return PERSONAS[settings.activePersona] || PERSONAS.eve;
  }, [settings.activePersona]);

  const currentMessages = useMemo(() => {
    return personaMessages[settings.activePersona] || getStarterMessagesForPersona(settings.activePersona);
  }, [personaMessages, settings.activePersona]);

  const handleUpdateSettings = (newSettings: Partial<AppSettings>) => {
    setSettings((prev) => {
      const updated = { ...prev, ...newSettings };
      if (newSettings.language) storageService.setLanguage(newSettings.language);
      if (newSettings.voiceId) storageService.setVoiceId(newSettings.voiceId);
      if (newSettings.apiKey !== undefined) storageService.setApiKey(newSettings.apiKey);
      if (newSettings.activePersona) storageService.setActivePersona(newSettings.activePersona);
      return updated;
    });
  };

  const handleSelectPersona = (personaId: PersonaId) => {
    storageService.setActivePersona(personaId);
    setSettings((prev) => ({
      ...prev,
      activePersona: personaId,
      voiceId: personaId,
    }));
  };

  const handleSendMessage = useCallback(
    async (
      content: string,
      isVoice: boolean = false,
      forcedCard?: 'image' | 'song' | 'workout' | 'planning'
    ) => {
      setErrorMessage(null);

      const userMsg: ChatMessage = {
        id: Date.now().toString(),
        role: 'user',
        content,
        timestamp: new Date().toISOString(),
        isVoice,
        personaId: settings.activePersona,
      };

      const updatedWithUser = [...currentMessages, userMsg];
      setPersonaMessages((prev) => ({
        ...prev,
        [settings.activePersona]: updatedWithUser,
      }));
      storageService.setMessages(updatedWithUser);
      setIsProcessing(true);

      try {
        const conversationHistory = updatedWithUser.map((m) => ({
          role: m.role,
          content: m.content,
          richCard: m.richCard,
        }));

        let response;
        if (forcedCard === 'song') {
          response = {
            reply:
              settings.language === 'af'
                ? `Hier is 'n lieflike liedjie net vir jou! 🎸`
                : `Here is a custom song just for you! 🎸`,
            richCard: {
              type: 'song' as const,
              audioTitle: 'Happy Days With You',
              audioDuration: '2:45',
              isPlaying: false,
            },
          };
        } else if (forcedCard === 'workout') {
          response = {
            reply:
              settings.language === 'af'
                ? `Hier is jou hoë-energie oefenplan vir vandag! 💪`
                : `How about a high energy full body workout? 💪`,
            richCard: {
              type: 'workout' as const,
              title: "Here's your workout plan:",
              checklistItems: [
                { text: 'Warm up - 5 min', checked: true },
                { text: 'Push ups - 4 sets', checked: true },
                { text: 'Squats - 4 sets', checked: true },
                { text: 'Plank - 3 sets', checked: true },
                { text: 'Cool down - 5 min', checked: true },
              ],
            },
          };
        } else if (forcedCard === 'planning') {
          response = {
            reply:
              settings.language === 'af'
                ? `Puik keuse! Ek beplan die perfekte reis vir jou. ✈️`
                : `Great choice! Planning the perfect itinerary for you... ✈️`,
            richCard: {
              type: 'planning' as const,
              title: 'Planning the perfect itinerary for you...',
            },
          };
        } else {
          response = await aiService.sendMessage(
            conversationHistory,
            currentPersona,
            settings.language,
            settings.apiKey
          );
        }

        const assistantMsg: ChatMessage = {
          id: (Date.now() + 1).toString(),
          role: 'assistant',
          content: response.reply,
          timestamp: new Date().toISOString(),
          isVoice,
          personaId: settings.activePersona,
          richCard: response.richCard,
        };

        const updatedWithAssistant = [...updatedWithUser, assistantMsg];
        setPersonaMessages((prev) => ({
          ...prev,
          [settings.activePersona]: updatedWithAssistant,
        }));
        storageService.setMessages(updatedWithAssistant);

        // If user used voice to send, speak response aloud
        if (isVoice && response.reply) {
          voiceService.speak(response.reply, settings.voiceId, settings.language);
        }
      } catch (err: unknown) {
        console.error('Error in send message:', err);
        const msg = err instanceof Error ? err.message : String(err);
        setErrorMessage(msg);
      } finally {
        setIsProcessing(false);
      }
    },
    [currentMessages, currentPersona, settings.activePersona, settings.language, settings.apiKey, settings.voiceId]
  );

  const handleClearHistory = () => {
    setPersonaMessages((prev) => ({
      ...prev,
      [settings.activePersona]: [],
    }));
    storageService.clearMessages();
  };

  const handleToggleLanguage = () => {
    const nextLang = settings.language === 'en' ? 'af' : 'en';
    handleUpdateSettings({ language: nextLang });
  };

  const handleVoiceAdded = (newVoice: VoiceOption) => {
    setSettings((prev) => ({
      ...prev,
      customVoices: [...prev.customVoices, newVoice],
      voiceId: newVoice.id,
    }));
    storageService.setVoiceId(newVoice.id);
  };

  return (
    <div className="h-screen w-screen overflow-hidden bg-[#060810] text-[#F0F4FF] flex flex-col font-sans">
      {activeScreen === 'chat' && (
        <ChatScreen
          settings={settings}
          persona={currentPersona}
          messages={currentMessages}
          onSendMessage={handleSendMessage}
          onSelectPersona={handleSelectPersona}
          onOpenSettings={() => setActiveScreen('settings')}
          onOpenMemory={() => setActiveScreen('memory')}
          onOpenVoices={() => setActiveScreen('voices')}
          onClearHistory={handleClearHistory}
          onToggleLanguage={handleToggleLanguage}
          isProcessing={isProcessing}
          errorMessage={errorMessage}
          onDismissError={() => setErrorMessage(null)}
        />
      )}

      {activeScreen === 'settings' && (
        <SettingsScreen
          settings={settings}
          onUpdateSettings={handleUpdateSettings}
          onBack={() => setActiveScreen('chat')}
          onNavigateToMemory={() => setActiveScreen('memory')}
          onNavigateToVoiceRecorder={() => setActiveScreen('voices')}
          onClearHistory={handleClearHistory}
        />
      )}

      {activeScreen === 'memory' && (
        <MemoryScreen
          language={settings.language}
          onBack={() => setActiveScreen('chat')}
        />
      )}

      {activeScreen === 'voices' && (
        <VoiceRecorderScreen
          language={settings.language}
          onBack={() => setActiveScreen('chat')}
          onVoiceAdded={handleVoiceAdded}
        />
      )}
    </div>
  );
}
