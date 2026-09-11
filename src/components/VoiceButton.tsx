import React from 'react';
import { Mic, Volume2 } from 'lucide-react';

interface VoiceButtonProps {
  isListening: boolean;
  isSpeaking: boolean;
  onToggle: () => void;
  disabled?: boolean;
  colorHex?: string;
}

export const VoiceButton: React.FC<VoiceButtonProps> = ({
  isListening,
  isSpeaking,
  onToggle,
  disabled = false,
  colorHex = '#A855F7',
}) => {
  return (
    <button
      id="voice-toggle-button"
      type="button"
      onClick={onToggle}
      disabled={disabled}
      className={`relative w-11 h-11 rounded-full flex items-center justify-center transition-all duration-200 text-white shrink-0 shadow-lg ${
        disabled ? 'opacity-40 cursor-not-allowed' : 'active:scale-90 hover:brightness-110'
      }`}
      style={{
        backgroundColor: colorHex,
        boxShadow: `0 0 15px ${colorHex}60`,
      }}
      title={
        isListening
          ? 'Listening... Click to stop'
          : isSpeaking
          ? 'Speaking... Click to cancel'
          : 'Tap to speak'
      }
    >
      {isSpeaking ? (
        <Volume2 className="w-5 h-5 animate-pulse" />
      ) : (
        <Mic className={`w-5 h-5 ${isListening ? 'animate-bounce' : ''}`} />
      )}

      {(isListening || isSpeaking) && (
        <span
          className="absolute -inset-1 rounded-full animate-ping opacity-60 pointer-events-none"
          style={{ backgroundColor: colorHex }}
        />
      )}
    </button>
  );
};
