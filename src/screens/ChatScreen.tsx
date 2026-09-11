import React, { useState, useRef, useEffect } from 'react';
import {
  Menu,
  Settings,
  Plus,
  Smile,
  AlertCircle,
  X,
  VolumeX,
  ChevronDown,
  Sparkles,
  ZoomIn,
  CheckCheck,
  Copy,
  Check,
  ClipboardPaste,
} from 'lucide-react';
import { ChatMessage, AppSettings, PersonaConfig, PersonaId } from '../types';
import { MessageBubble } from '../components/MessageBubble';
import { HeroAvatar } from '../components/HeroAvatar';
import { VoiceButton } from '../components/VoiceButton';
import { BottomNav, NavTab } from '../components/BottomNav';
import { PersonaSwitcherModal } from '../components/PersonaSwitcherModal';
import { QuickActionsModal } from '../components/QuickActionsModal';
import { ImageViewerModal } from '../components/ImageViewerModal';
import { voiceService } from '../services/voiceService';
import { PERSONAS } from '../data/personas';

interface ChatScreenProps {
  settings: AppSettings;
  persona: PersonaConfig;
  messages: ChatMessage[];
  onSendMessage: (
    content: string,
    isVoice?: boolean,
    forcedCard?: 'image' | 'song' | 'workout' | 'planning'
  ) => Promise<void>;
  onSelectPersona: (id: PersonaId) => void;
  onOpenSettings: () => void;
  onOpenMemory: () => void;
  onOpenVoices: () => void;
  onClearHistory: () => void;
  onToggleLanguage: () => void;
  isProcessing: boolean;
  errorMessage: string | null;
  onDismissError: () => void;
}

export const ChatScreen: React.FC<ChatScreenProps> = ({
  settings,
  persona,
  messages,
  onSendMessage,
  onSelectPersona,
  onOpenSettings,
  onOpenMemory,
  onOpenVoices,
  onClearHistory,
  onToggleLanguage,
  isProcessing,
  errorMessage,
  onDismissError,
}) => {
  const isAf = settings.language === 'af';
  const [inputText, setInputText] = useState('');
  const [isListening, setIsListening] = useState(false);
  const [isSpeaking, setIsSpeaking] = useState(false);
  const [isPersonaModalOpen, setIsPersonaModalOpen] = useState(false);
  const [isQuickActionsOpen, setIsQuickActionsOpen] = useState(false);
  const [activeImage, setActiveImage] = useState<{
    url: string;
    title?: string;
    subtitle?: string;
  } | null>(null);
  const [copiedAll, setCopiedAll] = useState(false);
  const [selectionNotice, setSelectionNotice] = useState<string | null>(null);

  const chatContainerRef = useRef<HTMLDivElement>(null);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const recognitionRef = useRef<{ start: () => void; stop: () => void } | null>(null);

  // Select all text in the chat area
  const handleSelectAllChatText = () => {
    if (chatContainerRef.current) {
      const selection = window.getSelection();
      if (selection) {
        const range = document.createRange();
        range.selectNodeContents(chatContainerRef.current);
        selection.removeAllRanges();
        selection.addRange(range);
        setSelectionNotice(isAf ? 'Alle klets teks gekies!' : 'All chat text selected!');
        setTimeout(() => setSelectionNotice(null), 2500);
      }
    }
  };

  // Copy all chat messages transcript to clipboard
  const handleCopyAllChatText = async () => {
    if (messages.length === 0) return;
    try {
      const transcript = messages
        .map((m) => {
          const sender = m.role === 'user' ? 'Me' : persona.name;
          const text = m.content || (m.richCard?.type === 'image' ? '[Image shared]' : '');
          return `${sender}: ${text}`;
        })
        .filter((line) => line.trim().length > 0)
        .join('\n\n');

      await navigator.clipboard.writeText(transcript);
      setCopiedAll(true);
      setSelectionNotice(isAf ? 'Alle klets gekopieer!' : 'All chat copied!');
      setTimeout(() => {
        setCopiedAll(false);
        setSelectionNotice(null);
      }, 2500);
    } catch {
      handleSelectAllChatText();
    }
  };

  // Paste text from clipboard into message input
  const handlePasteToInput = async () => {
    try {
      const text = await navigator.clipboard.readText();
      if (text) {
        setInputText((prev) => (prev ? `${prev} ${text}` : text));
        const inputEl = document.getElementById('chat-message-input') as HTMLInputElement;
        inputEl?.focus();
      }
    } catch {
      // Fallback: focus input field so user can press Ctrl+V / Cmd+V
      const inputEl = document.getElementById('chat-message-input') as HTMLInputElement;
      if (inputEl) {
        inputEl.focus();
        setSelectionNotice(isAf ? 'Druk Ctrl+V om te plak' : 'Press Ctrl+V to paste');
        setTimeout(() => setSelectionNotice(null), 2500);
      }
    }
  };

  // Auto-scroll to bottom on new messages
  const scrollToBottom = () => {
    if (chatContainerRef.current) {
      chatContainerRef.current.scrollTo({
        top: chatContainerRef.current.scrollHeight,
        behavior: 'smooth',
      });
    } else {
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  };

  useEffect(() => {
    scrollToBottom();
    const timer = setTimeout(scrollToBottom, 60);
    return () => clearTimeout(timer);
  }, [messages, isProcessing]);

  // Voice playback
  const handleSpeakText = (text: string) => {
    if (isSpeaking) {
      voiceService.stopSpeaking();
      setIsSpeaking(false);
      return;
    }
    voiceService.speak(
      text,
      settings.voiceId,
      settings.language,
      () => setIsSpeaking(true),
      () => setIsSpeaking(false),
      settings.speechSpeed ?? 0.85
    );
  };

  // Voice speech-to-text recognition
  const handleToggleVoiceInput = () => {
    if (isSpeaking) {
      voiceService.stopSpeaking();
      setIsSpeaking(false);
    }

    if (isListening) {
      recognitionRef.current?.stop();
      setIsListening(false);
      return;
    }

    const rec = voiceService.createRecognition(
      settings.language,
      (transcript) => {
        setIsListening(false);
        if (transcript.trim()) {
          onSendMessage(transcript.trim(), true);
        }
      },
      (err) => {
        console.warn('Recognition error:', err);
        setIsListening(false);
      },
      () => {
        setIsListening(false);
      }
    );

    if (rec) {
      recognitionRef.current = rec;
      rec.start();
      setIsListening(true);
    } else {
      const promptText = isAf
        ? 'Spraakherkenning word nie ten volle in hierdie blaaier ondersteun nie. Tik asseblief jou boodskap!'
        : 'Speech recognition is not fully supported in this browser. Please type your message!';
      alert(promptText);
    }
  };

  const handleSendText = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if (!inputText.trim() || isProcessing) return;
    const text = inputText.trim();
    setInputText('');
    await onSendMessage(text, false);
  };

  const handleAddEmoji = () => {
    const emojis = ['😊', '💜', '✨', '🌸', '💪', '🎸', '✈️'];
    const randomEmoji = emojis[Math.floor(Math.random() * emojis.length)];
    setInputText((prev) => prev + (prev.endsWith(' ') || !prev ? '' : ' ') + randomEmoji + ' ');
  };

  const handleNavSelect = (tab: NavTab) => {
    if (tab === 'models') {
      setIsPersonaModalOpen(true);
    } else if (tab === 'voices') {
      onOpenVoices();
    } else if (tab === 'memory') {
      onOpenMemory();
    }
  };

  const currentTitle = isAf ? persona.titleAfrikaans : persona.appTitle;

  return (
    <div className="flex flex-col h-full bg-[#060810] text-[#F0F4FF] overflow-hidden">
      {/* Top App Bar with Title, Avatar Selection Button, and Settings */}
      <header className="sticky top-0 z-20 flex items-center justify-between px-3 sm:px-4 py-2.5 bg-[#060810]/95 backdrop-blur-md border-b border-[#181D2E] select-none">
        {/* Left Hamburger */}
        <button
          id="menu-toggle-btn"
          type="button"
          onClick={() => setIsPersonaModalOpen(true)}
          className="p-2 -ml-1 text-[#94A3B8] hover:text-[#F0F4FF] hover:bg-[#14192A] rounded-xl transition-colors shrink-0"
          title="Switch Persona"
        >
          <Menu className="w-5 h-5" />
        </button>

        {/* Center Section: App Title & Avatar Selection Button */}
        <div className="flex items-center gap-2 sm:gap-3">
          <button
            type="button"
            onClick={() => setIsPersonaModalOpen(true)}
            className="text-center group flex items-center gap-1.5"
          >
            <h1 className="text-xs sm:text-sm font-extrabold tracking-widest text-[#F0F4FF] group-hover:text-white transition-colors uppercase">
              {currentTitle}
            </h1>
          </button>

          {/* Friends with Eve Button */}
          <button
            id="top-avatar-select-btn"
            type="button"
            onClick={() => setIsPersonaModalOpen(true)}
            className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-[#121625] hover:bg-[#1A2238] border transition-all hover:scale-105 active:scale-95 shadow-md group"
            style={{
              borderColor: `${persona.colorHex}60`,
              boxShadow: `0 0 12px ${persona.colorHex}25`,
            }}
            title="Friends with Eve (Switch Persona)"
          >
            <div
              className="w-5 h-5 rounded-full overflow-hidden border shrink-0"
              style={{ borderColor: persona.colorHex }}
            >
              <img
                src={persona.avatarUrl}
                alt={persona.name}
                className="w-full h-full object-cover"
              />
            </div>
            <span className="text-xs sm:text-sm font-bold text-[#F0F4FF]">
              {persona.id === 'eve' ? 'Friends with Eve' : `Friends with ${persona.name}`}
            </span>
            <ChevronDown className="w-3.5 h-3.5 text-[#94A3B8] group-hover:text-white transition-colors" />
          </button>
        </div>

        {/* Right Settings Gear */}
        <button
          id="nav-to-settings-btn"
          type="button"
          onClick={onOpenSettings}
          className="p-2 -mr-1 text-[#94A3B8] hover:text-[#00F0FF] hover:bg-[#14192A] rounded-xl transition-colors shrink-0"
          title="Settings"
        >
          <Settings className="w-5 h-5" />
        </button>
      </header>

      {/* Error Banner */}
      {errorMessage && (
        <div className="px-4 py-2 bg-[#FF6B6B]/15 border-b border-[#FF6B6B]/30 text-xs flex items-center justify-between text-[#FF6B6B] shrink-0">
          <div className="flex items-center gap-2">
            <AlertCircle className="w-4 h-4 shrink-0" />
            <span className="truncate">{errorMessage}</span>
          </div>
          <button
            type="button"
            onClick={onDismissError}
            className="text-[#FF6B6B] hover:text-white"
          >
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      )}

      {/* Speaking Banner */}
      {isSpeaking && (
        <div
          className="px-4 py-1.5 border-b flex items-center justify-between text-xs shrink-0"
          style={{
            backgroundColor: `${persona.colorHex}20`,
            borderColor: `${persona.colorHex}40`,
            color: persona.colorHex,
          }}
        >
          <div className="flex items-center gap-2">
            <span className="flex h-2 w-2 relative">
              <span
                className="animate-ping absolute inline-flex h-full w-full rounded-full opacity-75"
                style={{ backgroundColor: persona.colorHex }}
              />
              <span
                className="relative inline-flex rounded-full h-2 w-2"
                style={{ backgroundColor: persona.colorHex }}
              />
            </span>
            <span>
              {isAf ? `${persona.name} praat tans...` : `${persona.name} is speaking...`}
            </span>
          </div>
          <button
            type="button"
            onClick={() => {
              voiceService.stopSpeaking();
              setIsSpeaking(false);
            }}
            className="flex items-center gap-1 text-[#F0F4FF] hover:text-[#FF6B6B] text-[11px]"
          >
            <VolumeX className="w-3.5 h-3.5" />
            <span>Stop</span>
          </button>
        </div>
      )}

      {/* Centered Avatar on Top - Just below the LISTEN TO EVE banner */}
      <div className="w-full bg-[#070A14] border-b border-[#181D2E] py-2.5 px-4 flex flex-col items-center justify-center shrink-0 z-10 shadow-md select-none">
        <HeroAvatar
          persona={persona}
          isListening={isListening}
          isSpeaking={isSpeaking}
          isProcessing={isProcessing}
          onStatusClick={() => setIsPersonaModalOpen(true)}
          onAvatarClick={() =>
            setActiveImage({
              url: persona.avatarUrl,
              title: `${persona.name} ${persona.signatureIcon}`,
              subtitle: isAf ? 'Metgesel Foto' : 'Companion Portrait',
            })
          }
        />
      </div>

      {/* Main Content Area: Full width chat */}
      <div className="flex-1 flex flex-col min-h-0 overflow-hidden relative">
        {/* Chat Column */}
        <div className="flex-1 flex flex-col min-h-0 min-w-0">
          {/* Action Toolbar: Message count and Selection notice */}
          <div className="flex items-center justify-between px-3 sm:px-4 py-1.5 bg-[#080B16] border-b border-[#14192B] text-xs shrink-0 select-none">
            <div className="flex items-center gap-2">
              <span className="text-[11px] font-medium text-[#64748B]">
                {messages.length} {messages.length === 1 ? (isAf ? 'boodskap' : 'message') : (isAf ? 'boodskappe' : 'messages')}
              </span>
              {selectionNotice && (
                <span className="text-[10px] text-emerald-400 font-semibold animate-fadeIn bg-emerald-500/10 px-2 py-0.5 rounded-full border border-emerald-500/20">
                  {selectionNotice}
                </span>
              )}
            </div>
          </div>

          {/* Chat Messages Scroll Area */}
          <div
            ref={chatContainerRef}
            className="flex-1 min-h-0 overflow-y-auto px-3 sm:px-5 py-3 space-y-1.5 scroll-smooth select-text"
          >
            {messages.map((msg) => (
              <MessageBubble
                key={msg.id}
                message={msg}
                persona={persona}
                onPlayVoice={handleSpeakText}
                onOpenImage={(url, title) =>
                  setActiveImage({
                    url,
                    title: title || `${persona.name} Shared Image`,
                    subtitle: isAf ? 'Klik om af te laai of te deel' : 'Click to download or share',
                  })
                }
              />
            ))}

            {/* Assistant Processing Bounce indicator */}
            {isProcessing && (
              <div className="flex items-center gap-2.5 my-2 px-1">
                <div
                  className="w-7 h-7 rounded-full overflow-hidden shrink-0 border"
                  style={{ borderColor: `${persona.colorHex}60` }}
                >
                  <img
                    src={persona.avatarUrl}
                    alt={persona.name}
                    className="w-full h-full object-cover"
                  />
                </div>
                <div
                  className="flex items-center gap-1.5 py-2 px-3.5 rounded-2xl border"
                  style={{
                    backgroundColor: '#121625',
                    borderColor: `${persona.colorHex}30`,
                  }}
                >
                  <div
                    className="w-2 h-2 rounded-full animate-bounce"
                    style={{ backgroundColor: persona.colorHex }}
                  />
                  <div
                    className="w-2 h-2 rounded-full animate-bounce [animation-delay:0.2s]"
                    style={{ backgroundColor: persona.colorHex }}
                  />
                  <div
                    className="w-2 h-2 rounded-full animate-bounce [animation-delay:0.4s]"
                    style={{ backgroundColor: persona.colorHex }}
                  />
                </div>
              </div>
            )}

            <div ref={messagesEndRef} className="h-1" />
          </div>
        </div>
      </div>

      {/* Sticky Bottom Input Bar matching screenshots */}
      <div className="px-3 sm:px-4 py-2 bg-[#060810]/95 backdrop-blur-md border-t border-[#181D2E]">
        <form
          onSubmit={handleSendText}
          className="max-w-2xl mx-auto flex items-center gap-2"
        >
          {/* Plus button for quick actions */}
          <button
            type="button"
            onClick={() => setIsQuickActionsOpen(true)}
            className="w-9 h-9 rounded-full bg-[#131828] hover:bg-[#1C2337] border border-[#222B42] text-[#94A3B8] hover:text-white flex items-center justify-center shrink-0 transition-all active:scale-95"
            title="Quick actions"
          >
            <Plus className="w-5 h-5" />
          </button>

          {/* Text Input Pill Container */}
          <div className="flex-1 flex items-center bg-[#131828] border border-[#222B42] focus-within:border-white/30 rounded-full px-4 py-2 transition-colors">
            <input
              id="chat-message-input"
              type="text"
              value={inputText}
              onChange={(e) => setInputText(e.target.value)}
              placeholder={
                isListening
                  ? isAf
                    ? `${persona.name} luister...`
                    : `${persona.name} is listening...`
                  : 'Type a message...'
              }
              className="flex-1 bg-transparent text-xs sm:text-sm text-[#F0F4FF] placeholder-[#64748B] outline-none"
            />

            {/* Quick Paste button */}
            <button
              id="chat-paste-btn"
              type="button"
              onClick={handlePasteToInput}
              className="text-[#94A3B8] hover:text-[#00F0FF] p-1 px-1.5 hover:bg-[#1C253C] rounded-md transition-colors flex items-center gap-1 shrink-0 cursor-pointer"
              title={isAf ? 'Plak vanaf knipbord (Ctrl+V)' : 'Paste from clipboard (Ctrl+V)'}
            >
              <ClipboardPaste className="w-4 h-4" />
              <span className="text-[10px] font-semibold hidden sm:inline">
                {isAf ? 'Plak' : 'Paste'}
              </span>
            </button>

            {/* Smiley Emoji button */}
            <button
              type="button"
              onClick={handleAddEmoji}
              className="text-[#64748B] hover:text-[#F0F4FF] p-1 transition-colors shrink-0"
              title="Add emoji"
            >
              <Smile className="w-4 h-4" />
            </button>
          </div>

          {/* Mic Button matching persona color */}
          <VoiceButton
            isListening={isListening}
            isSpeaking={isSpeaking}
            onToggle={handleToggleVoiceInput}
            disabled={isProcessing}
            colorHex={persona.colorHex}
          />
        </form>
      </div>

      {/* Bottom Navigation Bar */}
      <BottomNav
        activeTab="chat"
        persona={persona}
        onSelectTab={handleNavSelect}
      />

      {/* Persona Switcher Modal */}
      <PersonaSwitcherModal
        isOpen={isPersonaModalOpen}
        onClose={() => setIsPersonaModalOpen(false)}
        activePersonaId={persona.id}
        onSelectPersona={onSelectPersona}
        language={settings.language}
      />

      {/* Quick Actions Modal */}
      <QuickActionsModal
        isOpen={isQuickActionsOpen}
        onClose={() => setIsQuickActionsOpen(false)}
        persona={persona}
        onAction={(prompt, cardType) => onSendMessage(prompt, false, cardType)}
        language={settings.language}
        onToggleLanguage={onToggleLanguage}
        onClearChat={onClearHistory}
      />

      {/* Full-Screen Image Viewer Modal with Enlarge, Download & Share */}
      <ImageViewerModal
        isOpen={!!activeImage}
        onClose={() => setActiveImage(null)}
        imageUrl={activeImage?.url || null}
        title={activeImage?.title}
        subtitle={activeImage?.subtitle}
        persona={persona}
      />
    </div>
  );
};
