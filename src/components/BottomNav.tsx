import React from 'react';
import { MessageSquare, Sparkles, AudioWaveform, Brain } from 'lucide-react';
import { PersonaConfig } from '../types';

export type NavTab = 'chat' | 'models' | 'voices' | 'memory';

interface BottomNavProps {
  activeTab: NavTab;
  persona: PersonaConfig;
  onSelectTab: (tab: NavTab) => void;
}

export const BottomNav: React.FC<BottomNavProps> = ({
  activeTab,
  persona,
  onSelectTab,
}) => {
  const tabs = [
    { id: 'chat' as NavTab, label: 'Chat', icon: MessageSquare },
    { id: 'models' as NavTab, label: 'Models', icon: Sparkles },
    { id: 'voices' as NavTab, label: 'Voices', icon: AudioWaveform },
    { id: 'memory' as NavTab, label: 'Memory', icon: Brain },
  ];

  return (
    <nav className="w-full bg-[#060810]/95 backdrop-blur-lg border-t border-[#1C2337] py-2 px-6 flex items-center justify-between z-30 select-none">
      {tabs.map((tab) => {
        const Icon = tab.icon;
        const isActive = activeTab === tab.id;

        return (
          <button
            key={tab.id}
            id={`nav-tab-${tab.id}`}
            type="button"
            onClick={() => onSelectTab(tab.id)}
            className="flex flex-col items-center gap-1 group py-1 px-3 rounded-xl transition-all"
          >
            {/* Active Indicator bar */}
            {isActive && (
              <span
                className="w-5 h-1 rounded-full mb-0.5"
                style={{
                  backgroundColor: persona.colorHex,
                  boxShadow: `0 0 8px ${persona.colorHex}`,
                }}
              />
            )}

            <Icon
              className="w-5 h-5 transition-colors"
              style={{
                color: isActive ? persona.colorHex : '#64748B',
              }}
            />
            <span
              className="text-[10px] font-medium transition-colors"
              style={{
                color: isActive ? '#F0F4FF' : '#64748B',
              }}
            >
              {tab.label}
            </span>
          </button>
        );
      })}
    </nav>
  );
};
