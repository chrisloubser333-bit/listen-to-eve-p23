import React, { useState } from 'react';
import { Play, Pause, Music, CheckCircle2, Circle, Plane, Dumbbell, Sparkles, ZoomIn, Download, Share2 } from 'lucide-react';
import { RichCardData, PersonaConfig } from '../types';
import { synthMusicService } from '../services/synthMusicService';

interface RichMessageCardProps {
  card: RichCardData;
  persona: PersonaConfig;
  onOpenImage?: (url: string, title?: string) => void;
}

export const RichMessageCard: React.FC<RichMessageCardProps> = ({ card, persona, onOpenImage }) => {
  const [isPlaying, setIsPlaying] = useState(false);
  const [checklist, setChecklist] = useState(card.checklistItems || []);

  const handleTogglePlay = () => {
    if (isPlaying) {
      synthMusicService.stop();
      setIsPlaying(false);
    } else {
      synthMusicService.playTrack(() => {
        setIsPlaying(false);
      });
      setIsPlaying(true);
    }
  };

  const handleToggleCheck = (index: number) => {
    setChecklist((prev) =>
      prev.map((item, i) =>
        i === index ? { ...item, checked: !item.checked } : item
      )
    );
  };

  // Image Card
  if (card.type === 'image' && card.imageUrl) {
    const title = card.title || `${persona.name} ${persona.signatureIcon}`;
    const isFullBody =
      title.toLowerCase().includes('full body') ||
      card.imageUrl.includes('full_body');

    return (
      <div
        role="button"
        tabIndex={0}
        onClick={() => onOpenImage?.(card.imageUrl!, title)}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            onOpenImage?.(card.imageUrl!, title);
          }
        }}
        className={`mt-2.5 relative ${
          isFullBody ? 'max-w-[280px]' : 'max-w-[260px]'
        } rounded-2xl overflow-hidden border border-white/15 shadow-xl group cursor-pointer transition-all hover:scale-[1.02] hover:shadow-2xl focus:outline-none bg-[#0a0d18]`}
        title="Click to view full image, download or share"
      >
        <img
          src={card.imageUrl}
          alt={title}
          referrerPolicy="no-referrer"
          className={`w-full ${
            isFullBody ? 'h-[360px] object-cover object-top' : 'h-52 object-cover object-top'
          } rounded-2xl transition-transform duration-300 group-hover:scale-105`}
        />

        {/* Full body badge tag */}
        {isFullBody && (
          <div className="absolute top-2.5 left-2.5 z-10">
            <span className="px-2 py-0.5 rounded-md bg-black/70 backdrop-blur-md text-[#FF4ECD] text-[10px] font-bold tracking-wider uppercase border border-[#FF4ECD]/40 shadow-sm">
              Full Body
            </span>
          </div>
        )}

        {/* Hover Action Overlay */}
        <div className="absolute inset-0 bg-gradient-to-t from-black/85 via-black/30 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-200 flex flex-col justify-between p-3">
          <div className="flex justify-end">
            <span className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-black/60 backdrop-blur-md text-white text-[11px] font-semibold border border-white/20 shadow-md">
              <ZoomIn className="w-3.5 h-3.5 text-[#00F0FF]" />
              <span>View & Share</span>
            </span>
          </div>

          <div className="flex items-center justify-between">
            <span className="text-xs text-white/90 font-medium">Click to enlarge</span>
            <div className="flex items-center gap-1.5 text-white/80">
              <Download className="w-3.5 h-3.5" />
              <Share2 className="w-3.5 h-3.5" />
            </div>
          </div>
        </div>

        {/* Signature watermark */}
        <div
          className="absolute bottom-2 right-3 pointer-events-none text-xl font-bold drop-shadow-[0_0_8px_rgba(255,255,255,0.7)] group-hover:opacity-0 transition-opacity"
          style={{
            color: persona.colorHex,
            fontFamily: "'Dancing Script', 'Caveat', cursive",
          }}
        >
          {title}
        </div>
      </div>
    );
  }

  // Song Generation In-Progress Card
  if (card.type === 'song' && card.statusText) {
    return (
      <div
        className="mt-2.5 p-3 rounded-2xl border flex items-center gap-3 max-w-[270px]"
        style={{
          background: `linear-gradient(135deg, ${persona.colorHex}15, #151B2D 80%)`,
          borderColor: `${persona.colorHex}40`,
        }}
      >
        <div
          className="w-10 h-10 rounded-full flex items-center justify-center shrink-0"
          style={{
            backgroundColor: `${persona.colorHex}25`,
            color: persona.colorHex,
          }}
        >
          <Music className="w-5 h-5 animate-pulse" />
        </div>
        <div className="flex-1 min-w-0">
          {/* Animated sound wave bars */}
          <div className="flex items-center gap-1 mb-1">
            {[35, 70, 45, 90, 60, 85, 40, 75, 50, 95, 30].map((h, i) => (
              <span
                key={i}
                className="w-1 rounded-full animate-pulse"
                style={{
                  height: `${h * 0.18}px`,
                  backgroundColor: persona.colorHex,
                  animationDelay: `${i * 0.1}s`,
                }}
              />
            ))}
          </div>
          <p className="text-xs text-[#F0F4FF] font-medium leading-tight whitespace-pre-line">
            {card.statusText}
          </p>
        </div>
      </div>
    );
  }

  // Completed Playable Song Card
  if (card.type === 'song' && !card.statusText) {
    return (
      <div
        className="mt-2.5 p-3 rounded-2xl border max-w-[280px] shadow-lg transition-all"
        style={{
          background: `linear-gradient(135deg, #181D2E, ${persona.colorHex}15)`,
          borderColor: `${persona.colorHex}40`,
        }}
      >
        <div className="flex items-center gap-3">
          {/* Play/Pause button */}
          <button
            type="button"
            onClick={handleTogglePlay}
            className="w-10 h-10 rounded-full flex items-center justify-center shrink-0 shadow-md transition-transform active:scale-95"
            style={{
              backgroundColor: persona.colorHex,
              color: '#0B0F1A',
            }}
          >
            {isPlaying ? (
              <Pause className="w-5 h-5 fill-current" />
            ) : (
              <Play className="w-5 h-5 fill-current translate-x-0.5" />
            )}
          </button>

          {/* Sound Wave & Info */}
          <div className="flex-1 min-w-0">
            {/* Waveform graphic */}
            <div className="flex items-center gap-0.5 h-6 mb-1">
              {[12, 18, 24, 14, 28, 16, 22, 30, 20, 26, 14, 22, 18, 12, 26, 16].map(
                (h, i) => (
                  <span
                    key={i}
                    className={`w-1 rounded-full transition-all duration-300 ${
                      isPlaying ? 'animate-pulse' : ''
                    }`}
                    style={{
                      height: `${h * 0.65}px`,
                      backgroundColor: isPlaying
                        ? persona.colorHex
                        : 'rgba(255,255,255,0.3)',
                      animationDelay: `${(i % 5) * 0.15}s`,
                    }}
                  />
                )
              )}
            </div>

            <div className="flex items-center justify-between text-[11px] text-[#94A3B8]">
              <span className="font-medium text-[#F0F4FF] truncate">
                {card.audioTitle || 'Song Preview'}
              </span>
              <span>{card.audioDuration || '2:45'}</span>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // Workout Checklist Card
  if (card.type === 'workout') {
    return (
      <div className="mt-2.5 p-3 rounded-2xl bg-[#14192A] border border-[#2A3348] max-w-[270px] space-y-2">
        <div className="flex items-center gap-2 text-xs font-semibold text-[#00F0FF]">
          <Dumbbell className="w-4 h-4" />
          <span>{card.title || "Here's your workout plan:"}</span>
        </div>

        <div className="space-y-1.5 pt-1">
          {checklist.map((item, idx) => (
            <button
              key={idx}
              type="button"
              onClick={() => handleToggleCheck(idx)}
              className="w-full flex items-center gap-2 text-left text-xs py-1 px-1.5 rounded-lg hover:bg-[#1E263D] transition-colors"
            >
              {item.checked ? (
                <CheckCircle2 className="w-4 h-4 text-[#2EE6A6] shrink-0" />
              ) : (
                <Circle className="w-4 h-4 text-[#64748B] shrink-0" />
              )}
              <span
                className={
                  item.checked ? 'text-[#F0F4FF]' : 'text-[#94A3B8] line-through'
                }
              >
                {item.text}
              </span>
            </button>
          ))}
        </div>
      </div>
    );
  }

  // Planning / Itinerary Card
  if (card.type === 'planning') {
    return (
      <div className="mt-2.5 p-3 rounded-2xl bg-[#14192A] border border-[#F59E0B]/30 max-w-[270px]">
        <div className="flex items-center gap-2.5">
          <div className="w-8 h-8 rounded-full bg-[#F59E0B]/20 text-[#F59E0B] flex items-center justify-center shrink-0">
            <Plane className="w-4 h-4" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-xs font-medium text-[#F0F4FF] leading-snug">
              {card.title || 'Planning the perfect itinerary for you...'}
            </p>
          </div>
          <div className="flex items-center gap-1 shrink-0">
            <span className="w-1.5 h-1.5 rounded-full bg-[#F59E0B] animate-bounce" />
            <span className="w-1.5 h-1.5 rounded-full bg-[#F59E0B] animate-bounce [animation-delay:0.2s]" />
            <span className="w-1.5 h-1.5 rounded-full bg-[#F59E0B] animate-bounce [animation-delay:0.4s]" />
          </div>
        </div>
      </div>
    );
  }

  return null;
};
