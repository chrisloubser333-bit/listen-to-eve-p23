import React, { useState } from 'react';
import {
  ArrowLeft,
  Plus,
  Heart,
  Sliders,
  Flag,
  Brain,
  Trash2,
  Trash,
  User,
  MoreHorizontal,
  Check,
  X,
} from 'lucide-react';
import { MemoryItem } from '../types';
import { AppTheme } from '../theme/appTheme';
import { storageService } from '../services/storageService';

interface MemoryScreenProps {
  language: 'en' | 'af';
  onBack: () => void;
}

export const MemoryScreen: React.FC<MemoryScreenProps> = ({ language, onBack }) => {
  const isAf = language === 'af';
  const [memories, setMemories] = useState<MemoryItem[]>(() => storageService.getMemories());
  const [filter, setFilter] = useState<string>('all');
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [newContent, setNewContent] = useState('');
  const [newType, setNewType] = useState<MemoryItem['type']>('fact');
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  const showToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => setToastMessage(null), 2500);
  };

  const getTypeColor = (type: string) => {
    switch (type) {
      case 'health':
        return '#2EE6A6';
      case 'preference':
        return '#00F0FF';
      case 'goal':
        return '#A855F7';
      default:
        return '#FF4ECD';
    }
  };

  const getTypeIcon = (type: string) => {
    switch (type) {
      case 'health':
        return <Heart className="w-4 h-4" />;
      case 'preference':
        return <Sliders className="w-4 h-4" />;
      case 'goal':
        return <Flag className="w-4 h-4" />;
      default:
        return <Brain className="w-4 h-4" />;
    }
  };

  const formatTimeAgo = (isoString: string) => {
    try {
      const diffMs = Date.now() - new Date(isoString).getTime();
      const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
      const diffHours = Math.floor(diffMs / (1000 * 60 * 60));

      if (diffDays > 1) {
        return isAf ? `${diffDays} dae gelede` : `${diffDays} days ago`;
      }
      if (diffDays === 1) return isAf ? '1 dag gelede' : '1 day ago';
      if (diffHours >= 1) {
        return isAf ? `${diffHours} ure gelede` : `${diffHours} hours ago`;
      }
      return isAf ? 'Pas nou' : 'Just now';
    } catch {
      return '';
    }
  };

  const handleAddMemory = () => {
    if (!newContent.trim()) return;
    const newItem: MemoryItem = {
      id: Date.now().toString(),
      content: newContent.trim(),
      type: newType,
      importance: 3,
      createdAt: new Date().toISOString(),
    };
    const updated = [newItem, ...memories];
    setMemories(updated);
    storageService.setMemories(updated);
    setNewContent('');
    setIsAddOpen(false);
    showToast(isAf ? 'Herinnering gestoor' : 'Memory saved');
  };

  const handleDeleteMemory = (id: string) => {
    const updated = memories.filter((m) => m.id !== id);
    setMemories(updated);
    storageService.setMemories(updated);
    showToast(isAf ? 'Herinnering verwyder' : 'Memory deleted');
  };

  const handleClearShortTerm = () => {
    showToast(isAf ? 'Korttermyngeheue uitgevee' : 'Short-term memory cleared');
  };

  const handleDeleteAll = () => {
    if (
      window.confirm(
        isAf
          ? 'Is jy seker jy wil alle herinneringe uitvee?'
          : 'Are you sure you want to permanently delete all memories?'
      )
    ) {
      setMemories([]);
      storageService.setMemories([]);
      showToast(isAf ? 'Alle herinneringe uitgevee' : 'All memories erased');
    }
  };

  const filteredMemories =
    filter === 'all' ? memories : memories.filter((m) => m.type === filter);

  return (
    <div className="flex flex-col h-full bg-[#0B0F1A] text-[#F0F4FF] overflow-y-auto">
      {/* Header */}
      <header className="sticky top-0 z-10 flex items-center justify-between px-4 py-3.5 bg-[#0B0F1A]/90 backdrop-blur-md border-b border-[#2A3348]">
        <div className="flex items-center gap-3">
          <button
            id="back-from-memory"
            type="button"
            onClick={onBack}
            className="p-2 -ml-2 rounded-xl text-[#94A3B8] hover:text-[#F0F4FF] hover:bg-[#151B2D] transition-colors"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <h1 className="text-lg font-semibold tracking-wide text-[#F0F4FF]">
            {isAf ? 'Geheue' : 'Memory'}
          </h1>
        </div>

        <button
          id="add-memory-btn"
          type="button"
          onClick={() => setIsAddOpen(true)}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#00F0FF]/20 text-[#00F0FF] hover:bg-[#00F0FF]/30 border border-[#00F0FF]/40 text-xs font-semibold tracking-wide transition-all"
        >
          <Plus className="w-4 h-4" />
          <span>{isAf ? 'Voeg by' : 'Add'}</span>
        </button>
      </header>

      <div className="flex-1 max-w-2xl w-full mx-auto p-4 space-y-6 pb-16">
        {/* Core Profile Card */}
        <section className="space-y-2">
          <h2 className="text-sm font-semibold tracking-wider text-[#F0F4FF]">
            {isAf ? 'Kernprofiel' : 'Core Profile'}
          </h2>
          <div className="p-4 bg-[#151B2D]/70 border border-[#A855F7]/40 rounded-2xl space-y-3 shadow-[0_0_15px_rgba(168,85,247,0.1)]">
            <div className="flex items-center gap-2 text-[#A855F7]">
              <User className="w-5 h-5" />
              <h3 className="text-sm font-semibold text-[#F0F4FF]">
                {isAf ? 'Oor jou' : 'About you'}
              </h3>
            </div>
            <div className="space-y-2 text-xs text-[#94A3B8] pl-2 border-l border-[#A855F7]/30">
              <p>• {isAf ? 'Verkies Afrikaans & Engels' : 'Prefers Afrikaans & English'}</p>
              <p>• {isAf ? 'Gebruik Eve as hoofstem' : 'Uses Eve as main voice'}</p>
              <p>• {isAf ? 'Belangstellings: gesondheid, gesprekke & leer' : 'Interests: health, conversations & learning'}</p>
            </div>
          </div>
        </section>

        {/* Filters */}
        <section className="space-y-2">
          <h2 className="text-sm font-semibold tracking-wider text-[#F0F4FF]">
            {isAf ? 'Herinneringe' : 'Memories'}
          </h2>
          <div className="flex items-center gap-2 overflow-x-auto pb-1 no-scrollbar">
            {[
              { id: 'all', label: isAf ? 'Alles' : 'All' },
              { id: 'health', label: isAf ? 'Gesondheid' : 'Health' },
              { id: 'preference', label: isAf ? 'Voorkeure' : 'Preferences' },
              { id: 'goal', label: isAf ? 'Doelwitte' : 'Goals' },
              { id: 'fact', label: isAf ? 'Feite' : 'Facts' },
            ].map((tab) => {
              const active = filter === tab.id;
              return (
                <button
                  key={tab.id}
                  id={`filter-tab-${tab.id}`}
                  type="button"
                  onClick={() => setFilter(tab.id)}
                  className={`px-3.5 py-1.5 rounded-full text-xs font-medium whitespace-nowrap transition-all ${
                    active
                      ? 'bg-[#00F0FF]/20 text-[#00F0FF] border border-[#00F0FF]/70 shadow-[0_0_10px_rgba(0,240,255,0.3)]'
                      : 'bg-[#151B2D]/70 text-[#94A3B8] border border-[#2A3348] hover:text-[#F0F4FF]'
                  }`}
                >
                  {tab.label}
                </button>
              );
            })}
          </div>
        </section>

        {/* Memory List */}
        <section className="space-y-2.5">
          {filteredMemories.length === 0 ? (
            <div className="p-8 text-center bg-[#151B2D]/40 border border-[#2A3348] rounded-2xl space-y-2">
              <Brain className="w-10 h-10 mx-auto text-[#94A3B8]/40" />
              <p className="text-sm text-[#94A3B8]">
                {isAf
                  ? 'Nog geen herinneringe in hierdie kategorie nie'
                  : 'No memories in this category yet'}
              </p>
            </div>
          ) : (
            filteredMemories.map((m) => {
              const color = getTypeColor(m.type);
              return (
                <div
                  key={m.id}
                  id={`memory-item-${m.id}`}
                  className="flex items-start justify-between p-3.5 bg-[#151B2D]/70 border border-[#2A3348] hover:border-[#00F0FF]/40 rounded-2xl transition-all"
                  style={{ borderColor: `${color}35` }}
                >
                  <div className="flex items-start gap-3">
                    <div
                      className="w-8 h-8 rounded-xl flex items-center justify-center shrink-0 mt-0.5"
                      style={{
                        backgroundColor: `${color}20`,
                        color: color,
                      }}
                    >
                      {getTypeIcon(m.type)}
                    </div>
                    <div>
                      <p className="text-sm text-[#F0F4FF] leading-snug">
                        {m.content}
                      </p>
                      <div className="flex items-center gap-2 mt-1 text-[11px] font-medium" style={{ color: color }}>
                        <span className="uppercase tracking-wider">{m.type}</span>
                        <span>•</span>
                        <span className="text-[#94A3B8]">{formatTimeAgo(m.createdAt)}</span>
                      </div>
                    </div>
                  </div>

                  <button
                    type="button"
                    onClick={() => handleDeleteMemory(m.id)}
                    className="p-1.5 text-[#94A3B8] hover:text-[#FF6B6B] transition-colors"
                    title="Delete"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              );
            })
          )}
        </section>

        {/* Privacy Section */}
        <section className="space-y-2 pt-3">
          <h2 className="text-sm font-semibold tracking-wider text-[#F0F4FF]">
            {isAf ? 'Privaatheid' : 'Privacy'}
          </h2>
          <div className="divide-y divide-[#2A3348] bg-[#151B2D]/70 border border-[#2A3348] rounded-2xl overflow-hidden">
            <button
              id="clear-short-term-btn"
              type="button"
              onClick={handleClearShortTerm}
              className="w-full flex items-center gap-3 p-3.5 text-left text-sm text-[#F0F4FF] hover:bg-[#1E263C] transition-colors"
            >
              <Trash className="w-4 h-4 text-[#94A3B8]" />
              <span>{isAf ? 'Vee korttermyngeheue uit' : 'Clear short-term memory'}</span>
            </button>
            <button
              id="delete-all-memories-btn"
              type="button"
              onClick={handleDeleteAll}
              className="w-full flex items-center gap-3 p-3.5 text-left text-sm text-[#FF6B6B] hover:bg-[#FF6B6B]/10 transition-colors"
            >
              <Trash2 className="w-4 h-4 text-[#FF6B6B]" />
              <span>{isAf ? 'Vee alle herinneringe uit' : 'Delete all memories'}</span>
            </button>
          </div>
        </section>
      </div>

      {/* Add Memory Modal */}
      {isAddOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm">
          <div className="max-w-md w-full bg-[#151B2D] border border-[#2A3348] rounded-2xl p-5 space-y-4 shadow-2xl">
            <div className="flex items-center justify-between">
              <h3 className="text-base font-semibold text-[#F0F4FF]">
                {isAf ? 'Voeg herinnering by' : 'Add memory'}
              </h3>
              <button
                type="button"
                onClick={() => setIsAddOpen(false)}
                className="p-1 text-[#94A3B8] hover:text-[#F0F4FF]"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <textarea
              id="new-memory-text"
              rows={3}
              value={newContent}
              onChange={(e) => setNewContent(e.target.value)}
              placeholder={
                isAf ? 'Wat moet Eve onthou?' : 'What should Eve remember?'
              }
              className="w-full p-3 bg-[#0B0F1A] border border-[#2A3348] focus:border-[#00F0FF]/60 rounded-xl text-sm text-[#F0F4FF] placeholder-[#94A3B8] outline-none resize-none"
            />

            <div className="space-y-1.5">
              <label className="text-xs text-[#94A3B8] font-medium">
                {isAf ? 'Tipe' : 'Type'}
              </label>
              <div className="flex flex-wrap gap-2">
                {(['fact', 'preference', 'health', 'goal'] as const).map((t) => (
                  <button
                    key={t}
                    type="button"
                    onClick={() => setNewType(t)}
                    className={`px-3 py-1 rounded-xl text-xs font-medium capitalize transition-all ${
                      newType === t
                        ? 'bg-[#00F0FF]/25 text-[#00F0FF] border border-[#00F0FF]/60'
                        : 'bg-[#0B0F1A] text-[#94A3B8] border border-[#2A3348]'
                    }`}
                  >
                    {t}
                  </button>
                ))}
              </div>
            </div>

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                type="button"
                onClick={() => setIsAddOpen(false)}
                className="px-4 py-2 rounded-xl text-sm font-medium text-[#94A3B8] hover:text-[#F0F4FF]"
              >
                {isAf ? 'Kanselleer' : 'Cancel'}
              </button>
              <button
                id="save-new-memory-btn"
                type="button"
                onClick={handleAddMemory}
                disabled={!newContent.trim()}
                className="px-4 py-2 rounded-xl text-sm font-semibold bg-[#00F0FF] hover:bg-[#00F0FF]/90 text-[#0B0F1A] disabled:opacity-40 disabled:cursor-not-allowed shadow-[0_0_15px_rgba(0,240,255,0.4)]"
              >
                {isAf ? 'Stoor' : 'Save'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Toast Notification */}
      {toastMessage && (
        <div className="fixed bottom-6 left-1/2 -translate-x-1/2 px-4 py-2 rounded-xl bg-[#2EE6A6] text-[#0B0F1A] font-semibold text-xs shadow-xl z-50 animate-fade-in">
          {toastMessage}
        </div>
      )}
    </div>
  );
};
