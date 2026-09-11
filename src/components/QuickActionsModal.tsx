import React from 'react';
import { Camera, Music, Dumbbell, Plane, Globe, Trash2, X, Sparkles } from 'lucide-react';
import { PersonaConfig } from '../types';

interface QuickActionsModalProps {
  isOpen: boolean;
  onClose: () => void;
  persona: PersonaConfig;
  onAction: (prompt: string, cardType?: 'image' | 'song' | 'workout' | 'planning') => void;
  language: 'en' | 'af';
  onToggleLanguage: () => void;
  onClearChat: () => void;
}

export const QuickActionsModal: React.FC<QuickActionsModalProps> = ({
  isOpen,
  onClose,
  persona,
  onAction,
  language,
  onToggleLanguage,
  onClearChat,
}) => {
  if (!isOpen) return null;

  const isAf = language === 'af';

  const actions = [
    {
      icon: Camera,
      label: isAf ? `Volle lyf prent van ${persona.name}` : `Full body photo of ${persona.name}`,
      prompt: `${persona.name}, please create a full body image of you`,
      type: 'image' as const,
      color: '#FF4ECD',
    },
    {
      icon: Camera,
      label: isAf ? `Portretfoto van ${persona.name}` : `Portrait photo of ${persona.name}`,
      prompt: `${persona.name}, can you create a portrait photo of yourself?`,
      type: 'image' as const,
      color: '#E026A8',
    },
    {
      icon: Sparkles,
      label: isAf ? 'Skep prent van sonsondergang' : 'Generate AI image of a sunset',
      prompt: `${persona.name}, create an image of a breathtaking sunset over the ocean with neon reflections`,
      type: 'image' as const,
      color: '#8B5CF6',
    },
    {
      icon: Music,
      label: isAf ? 'Skep ’n lekker liedjie' : 'Create a happy song for me',
      prompt: `${persona.name}, can you make a happy song for me?`,
      type: 'song' as const,
      color: '#F43F5E',
    },
    {
      icon: Dumbbell,
      label: isAf ? 'Oefensessie plan' : 'Plan a workout routine',
      prompt: `${persona.name}, what's a good workout for today?`,
      type: 'workout' as const,
      color: '#00F0FF',
    },
    {
      icon: Plane,
      label: isAf ? 'Beplan reis na Japan' : 'Plan a trip to Japan',
      prompt: `${persona.name}, can you help me plan a trip to Japan?`,
      type: 'planning' as const,
      color: '#F59E0B',
    },
  ];

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center p-3 bg-black/70 backdrop-blur-sm"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md bg-[#0F1424] border border-[#2A3348] rounded-3xl p-4 space-y-3 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between pb-2 border-b border-[#1C2337]">
          <span className="text-xs font-semibold uppercase tracking-wider text-[#94A3B8]">
            {isAf ? 'Vinnige Aksies' : 'Quick Actions'}
          </span>
          <button
            type="button"
            onClick={onClose}
            className="p-1 text-[#94A3B8] hover:text-white"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="grid grid-cols-2 gap-2.5">
          {actions.map((act, i) => {
            const Icon = act.icon;
            return (
              <button
                key={i}
                type="button"
                onClick={() => {
                  onAction(act.prompt, act.type);
                  onClose();
                }}
                className="flex flex-col items-start gap-2 p-3 rounded-2xl bg-[#151B2D] hover:bg-[#1E263D] border border-[#2A3348] transition-all text-left group"
              >
                <div
                  className="w-8 h-8 rounded-xl flex items-center justify-center"
                  style={{ backgroundColor: `${act.color}20`, color: act.color }}
                >
                  <Icon className="w-4 h-4" />
                </div>
                <span className="text-xs font-medium text-[#F0F4FF] group-hover:text-white leading-snug">
                  {act.label}
                </span>
              </button>
            );
          })}
        </div>

        <div className="flex items-center justify-between pt-2 border-t border-[#1C2337] text-xs">
          <button
            type="button"
            onClick={() => {
              onToggleLanguage();
              onClose();
            }}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#151B2D] text-[#94A3B8] hover:text-[#00F0FF]"
          >
            <Globe className="w-3.5 h-3.5" />
            <span>Taal: {isAf ? 'Afrikaans' : 'English'}</span>
          </button>

          <button
            type="button"
            onClick={() => {
              onClearChat();
              onClose();
            }}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#151B2D] text-[#94A3B8] hover:text-[#FF6B6B]"
          >
            <Trash2 className="w-3.5 h-3.5" />
            <span>{isAf ? 'Maak skoon' : 'Clear Chat'}</span>
          </button>
        </div>
      </div>
    </div>
  );
};
