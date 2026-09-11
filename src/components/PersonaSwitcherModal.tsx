import React from 'react';
import { X, Check, Sparkles } from 'lucide-react';
import { PERSONAS } from '../data/personas';
import { PersonaId, PersonaConfig } from '../types';

interface PersonaSwitcherModalProps {
  isOpen: boolean;
  onClose: () => void;
  activePersonaId: PersonaId;
  onSelectPersona: (id: PersonaId) => void;
  language: 'en' | 'af';
}

export const PersonaSwitcherModal: React.FC<PersonaSwitcherModalProps> = ({
  isOpen,
  onClose,
  activePersonaId,
  onSelectPersona,
  language,
}) => {
  if (!isOpen) return null;

  const isAf = language === 'af';
  const personaList = Object.values(PERSONAS);

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/75 backdrop-blur-sm animate-in fade-in duration-200">
      <div
        className="w-full max-w-md bg-[#0B0F1A] border border-[#2A3348] rounded-t-3xl sm:rounded-3xl overflow-hidden shadow-2xl flex flex-col max-h-[85vh]"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-[#1C2337]">
          <div className="flex items-center gap-2">
            <Sparkles className="w-5 h-5 text-[#00F0FF]" />
            <h2 className="text-base font-semibold text-[#F0F4FF]">
              {isAf ? 'Kies jou KI-Stemmetel' : 'Choose Your AI Companion'}
            </h2>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-full text-[#94A3B8] hover:text-white hover:bg-[#1E263D] transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Persona Cards List */}
        <div className="p-4 space-y-3 overflow-y-auto">
          {personaList.map((p) => {
            const isSelected = p.id === activePersonaId;

            return (
              <button
                key={p.id}
                type="button"
                onClick={() => {
                  onSelectPersona(p.id);
                  onClose();
                }}
                className={`w-full flex items-center gap-3.5 p-3 rounded-2xl border transition-all text-left ${
                  isSelected
                    ? 'bg-[#151B2D] border-opacity-100 shadow-lg'
                    : 'bg-[#0E1322] border-[#1C2337] hover:border-[#2A3348] hover:bg-[#141A2B]'
                }`}
                style={{
                  borderColor: isSelected ? p.colorHex : undefined,
                  boxShadow: isSelected ? `0 0 20px ${p.glowColor}` : undefined,
                }}
              >
                {/* Persona Avatar */}
                <div
                  className="relative w-14 h-14 rounded-full overflow-hidden shrink-0 border-2"
                  style={{ borderColor: p.colorHex }}
                >
                  <img
                    src={p.avatarUrl}
                    alt={p.name}
                    className="w-full h-full object-cover"
                  />
                  {isSelected && (
                    <div
                      className="absolute inset-0 flex items-center justify-center bg-black/40"
                    >
                      <Check className="w-5 h-5 text-white" />
                    </div>
                  )}
                </div>

                {/* Details */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-sm text-[#F0F4FF]">
                        {p.name}
                      </span>
                      <span
                        className="text-lg font-bold"
                        style={{
                          color: p.colorHex,
                          fontFamily: "'Dancing Script', 'Caveat', cursive",
                        }}
                      >
                        {p.signatureIcon}
                      </span>
                    </div>

                    <span
                      className="text-[10px] uppercase font-bold px-2 py-0.5 rounded-full"
                      style={{
                        backgroundColor: `${p.colorHex}20`,
                        color: p.colorHex,
                      }}
                    >
                      {p.defaultStatus}
                    </span>
                  </div>

                  <p className="text-xs text-[#94A3B8] mt-1 line-clamp-2">
                    {p.description}
                  </p>
                </div>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
};
