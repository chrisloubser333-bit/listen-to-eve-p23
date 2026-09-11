import React from 'react';
import { ZoomIn } from 'lucide-react';
import { PersonaConfig } from '../types';

interface HeroAvatarProps {
  persona: PersonaConfig;
  customStatus?: string;
  isListening?: boolean;
  isSpeaking?: boolean;
  isProcessing?: boolean;
  onStatusClick?: () => void;
  onAvatarClick?: () => void;
}

export const HeroAvatar: React.FC<HeroAvatarProps> = ({
  persona,
  customStatus,
  isListening = false,
  isSpeaking = false,
  isProcessing = false,
  onStatusClick,
  onAvatarClick,
}) => {
  // Determine dynamic status
  let statusText = customStatus || persona.defaultStatus;
  let statusColor = persona.colorHex;
  let isMusicState = persona.id === 'rex' && statusText.toLowerCase().includes('song');

  if (isListening) {
    statusText = 'Listening';
    statusColor = '#F59E0B';
  } else if (isProcessing) {
    statusText = 'Thinking';
    statusColor = '#00F0FF';
  } else if (isSpeaking) {
    statusText = 'Speaking';
    statusColor = persona.colorHex;
  }

  return (
    <div className="flex flex-col items-center select-none relative">
      {/* Central Portrait Wrapper */}
      <div className="relative flex items-center justify-center">
        {/* Ambient Glow behind portrait */}
        <div
          className="absolute -inset-2 rounded-full opacity-60 blur-xl pointer-events-none transition-all duration-700"
          style={{
            background: `radial-gradient(circle, ${persona.colorHex} 0%, transparent 70%)`,
          }}
        />

        {/* Circular Avatar Frame with enlarge/download click */}
        <button
          type="button"
          onClick={onAvatarClick}
          className="group/avatar relative w-32 h-32 sm:w-36 sm:h-36 md:w-40 md:h-40 rounded-full overflow-hidden border-[3px] p-1 transition-all hover:scale-105 active:scale-95 focus:outline-none cursor-pointer"
          style={{
            borderColor: `${persona.colorHex}80`,
            boxShadow: `0 0 22px ${persona.glowColor}, inset 0 0 15px ${persona.colorHex}40`,
          }}
          title={`Click to view larger ${persona.name} photo, download or share`}
        >
          <img
            src={persona.avatarUrl}
            alt={persona.name}
            className="w-full h-full object-cover rounded-full pointer-events-none transition-transform duration-300 group-hover/avatar:scale-105"
          />

          {/* Hover zoom overlay */}
          <div className="absolute inset-0 bg-black/40 backdrop-blur-[1px] opacity-0 group-hover/avatar:opacity-100 flex flex-col items-center justify-center gap-0.5 transition-opacity duration-200">
            <ZoomIn className="w-5 h-5 text-white drop-shadow-md" />
            <span className="text-[9px] font-bold text-white uppercase tracking-wider">
              Enlarge
            </span>
          </div>

          {/* Glowing ring animation when speaking or listening */}
          {(isListening || isSpeaking || isProcessing) && (
            <span
              className="absolute inset-0 rounded-full border-2 animate-ping pointer-events-none opacity-40"
              style={{ borderColor: persona.colorHex }}
            />
          )}
        </button>

        {/* Neon Cursive Signature Sticker */}
        <div
          className="absolute -right-8 sm:-right-12 top-1 pointer-events-none rotate-[-4deg] flex items-center gap-1 drop-shadow-[0_0_12px_rgba(255,255,255,0.4)]"
          style={{
            color: persona.colorHex,
            fontFamily: "'Dancing Script', 'Caveat', cursive",
            textShadow: `0 0 8px ${persona.colorHex}, 0 0 18px ${persona.colorHex}`,
          }}
        >
          <span className="text-xl sm:text-2xl md:text-3xl font-bold tracking-wide">
            {persona.signature}
          </span>
          <span className="text-base sm:text-lg mt-0.5">
            {persona.signatureIcon}
          </span>
        </div>
      </div>

      {/* Status Pill beneath portrait */}
      <button
        type="button"
        onClick={onStatusClick}
        className="mt-2.5 inline-flex items-center gap-2 px-3 py-1 rounded-full bg-[#111625]/90 border text-[11px] sm:text-xs font-medium tracking-wide transition-all hover:scale-105 active:scale-95 shadow-md"
        style={{
          borderColor: `${persona.colorHex}40`,
          color: '#F0F4FF',
          boxShadow: `0 0 12px ${persona.colorHex}25`,
        }}
      >
        {isMusicState ? (
          <span className="text-sm" style={{ color: persona.colorHex }}>
            🎵
          </span>
        ) : (
          <span
            className="w-2 h-2 rounded-full animate-pulse"
            style={{
              backgroundColor:
                statusText === 'Ready to talk'
                  ? '#2EE6A6'
                  : statusColor,
              boxShadow: `0 0 8px ${
                statusText === 'Ready to talk' ? '#2EE6A6' : statusColor
              }`,
            }}
          />
        )}
        <span className="text-[11px] sm:text-[12px] text-[#E2E8F0] font-medium">
          {statusText}
        </span>
      </button>
    </div>
  );
};

