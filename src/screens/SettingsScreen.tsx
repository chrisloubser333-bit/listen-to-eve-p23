import React, { useState } from 'react';
import {
  ArrowLeft,
  Eye,
  EyeOff,
  Save,
  CheckCircle,
  Mic,
  User,
  Brain,
  Trash2,
  Sparkles,
  ShieldAlert,
} from 'lucide-react';
import { AppSettings, VoiceOption } from '../types';
import { AppTheme } from '../theme/appTheme';
import { storageService } from '../services/storageService';
import { PERSONAS } from '../data/personas';

interface SettingsScreenProps {
  settings: AppSettings;
  onUpdateSettings: (newSettings: Partial<AppSettings>) => void;
  onBack: () => void;
  onNavigateToMemory: () => void;
  onNavigateToVoiceRecorder: () => void;
  onClearHistory: () => void;
}

export const SettingsScreen: React.FC<SettingsScreenProps> = ({
  settings,
  onUpdateSettings,
  onBack,
  onNavigateToMemory,
  onNavigateToVoiceRecorder,
  onClearHistory,
}) => {
  const isAf = settings.language === 'af';
  const activePersonaConfig = PERSONAS[settings.activePersona] || PERSONAS.eve;
  const [apiKeyInput, setApiKeyInput] = useState(settings.apiKey);
  const [showKey, setShowKey] = useState(false);
  const [saveBanner, setSaveBanner] = useState(false);
  const [showConfirmClear, setShowConfirmClear] = useState(false);

  const allVoices: VoiceOption[] = [
    ...AppTheme.defaultVoices,
    ...settings.customVoices,
  ];

  const handleSaveApiKey = () => {
    storageService.setApiKey(apiKeyInput);
    onUpdateSettings({ apiKey: apiKeyInput.trim() });
    setSaveBanner(true);
    setTimeout(() => setSaveBanner(false), 2500);
  };

  const handleSelectLanguage = (lang: 'en' | 'af') => {
    storageService.setLanguage(lang);
    onUpdateSettings({ language: lang });
  };

  const handleSelectVoice = (voiceId: string) => {
    storageService.setVoiceId(voiceId);
    onUpdateSettings({ voiceId });
  };

  return (
    <div className="flex flex-col h-full bg-[#0B0F1A] text-[#F0F4FF] overflow-y-auto">
      {/* Header */}
      <header className="sticky top-0 z-10 flex items-center gap-3 px-4 py-3.5 bg-[#0B0F1A]/90 backdrop-blur-md border-b border-[#2A3348]">
        <button
          id="back-from-settings"
          type="button"
          onClick={onBack}
          className="p-2 -ml-2 rounded-xl text-[#94A3B8] hover:text-[#F0F4FF] hover:bg-[#151B2D] transition-colors"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-lg font-semibold tracking-wide text-[#F0F4FF]">
          {isAf ? 'Instellings' : 'Settings'}
        </h1>
      </header>

      <div className="flex-1 max-w-2xl w-full mx-auto p-4 space-y-7 pb-16">
        {/* API Engine & Status Section */}
        <section className="space-y-3">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-semibold tracking-wider text-[#F0F4FF]">
              {isAf ? 'KI Enjin & API Status' : 'AI Engine & API Status'}
            </h2>
            <span className="flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 text-[11px] font-medium">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
              {isAf ? 'Beeld & Stem Aktief' : 'Image & Voice Active'}
            </span>
          </div>

          <div className="p-3 bg-[#13192B]/80 border border-[#222C44] rounded-2xl space-y-2">
            <div className="flex items-center justify-between text-xs text-[#CBD5E1]">
              <span className="flex items-center gap-2">
                <Sparkles className="w-4 h-4 text-[#FF4ECD]" />
                <span>{isAf ? 'KI Beeldgenerator' : 'AI Image Generator'}</span>
              </span>
              <span className="text-emerald-400 font-medium">
                {isAf ? 'Gereed (Geen sleutel nodig)' : 'Ready (No key required)'}
              </span>
            </div>
            <div className="flex items-center justify-between text-xs text-[#CBD5E1]">
              <span className="flex items-center gap-2">
                <Mic className="w-4 h-4 text-[#00F0FF]" />
                <span>{isAf ? 'Stem & Spraakherkenning' : 'Voice & Speech Synthesis'}</span>
              </span>
              <span className="text-emerald-400 font-medium">
                {isAf ? 'Gereed' : 'Ready'}
              </span>
            </div>
          </div>

          {/* Optional xAI Key */}
          <div className="space-y-1.5">
            <div className="flex items-center justify-between">
              <span className="text-xs font-medium text-[#94A3B8]">
                {isAf ? 'Opsionele xAI API-sleutel (vir pasgemaakte modelle)' : 'Optional xAI API Key (for custom models)'}
              </span>
              {settings.apiKey ? (
                <span className="text-[10px] text-emerald-400 font-medium">{isAf ? 'Aangeheg' : 'Connected'}</span>
              ) : (
                <span className="text-[10px] text-[#64748B]">{isAf ? 'Opsioneel' : 'Optional'}</span>
              )}
            </div>

            <div className="p-3 bg-[#151B2D]/70 border border-[#2A3348] rounded-2xl focus-within:border-[#00F0FF]/60 shadow-[0_4px_20px_rgba(0,0,0,0.2)]">
              <div className="flex items-center gap-2">
                <input
                  id="xai-api-key-input"
                  type={showKey ? 'text' : 'password'}
                  value={apiKeyInput}
                  onChange={(e) => setApiKeyInput(e.target.value)}
                  placeholder={settings.apiKey ? '••••••••••••••••' : 'xai-... (optional)'}
                  className="flex-1 bg-transparent text-sm text-[#F0F4FF] placeholder-[#64748B] outline-none font-mono"
                />
                <button
                  type="button"
                  onClick={() => setShowKey(!showKey)}
                  className="p-1.5 text-[#94A3B8] hover:text-[#F0F4FF] transition-colors"
                  title={showKey ? 'Hide key' : 'Show key'}
                >
                  {showKey ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
                <button
                  id="save-api-key-btn"
                  type="button"
                  onClick={handleSaveApiKey}
                  className="flex items-center gap-1 px-3 py-1.5 rounded-xl bg-[#00F0FF]/20 text-[#00F0FF] hover:bg-[#00F0FF]/30 border border-[#00F0FF]/40 text-xs font-medium transition-all cursor-pointer"
                >
                  <Save className="w-3.5 h-3.5" />
                  <span>{isAf ? 'Stoor' : 'Save'}</span>
                </button>
              </div>
            </div>
            <p className="text-[11px] text-[#64748B]">
              {isAf
                ? 'Eve kan prente genereer en gesels sonder enige sleutel. Voer slegs in as jy xAI wil koppel.'
                : 'Eve can create images and chat without any key. Only enter if you want to connect xAI directly.'}
            </p>
          </div>

          {saveBanner && (
            <div className="flex items-center gap-2 p-2.5 rounded-xl bg-[#2EE6A6]/15 border border-[#2EE6A6]/40 text-[#2EE6A6] text-xs">
              <CheckCircle className="w-4 h-4" />
              <span>{isAf ? 'API-sleutel gestoor' : 'API key saved'}</span>
            </div>
          )}
        </section>

        {/* AI Companion / Persona Section */}
        <section className="space-y-2">
          <h2 className="text-sm font-semibold tracking-wider text-[#F0F4FF]">
            {isAf ? 'KI Metgesel (Persona)' : 'AI Companion (Persona)'}
          </h2>
          <div className="grid grid-cols-5 gap-2">
            {[
              { id: 'eve', name: 'Eve', icon: '♡', color: '#FF4ECD' },
              { id: 'ara', name: 'Ara', icon: '🌸', color: '#F59E0B' },
              { id: 'leo', name: 'Leo', icon: '👑', color: '#00F0FF' },
              { id: 'rex', name: 'Rex', icon: '⚔️', color: '#F43F5E' },
              { id: 'sal', name: 'Sal', icon: '✨', color: '#8B5CF6' },
            ].map((p) => {
              const active = settings.activePersona === p.id;
              return (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => {
                    onUpdateSettings({ activePersona: p.id as any, voiceId: p.id });
                    storageService.setActivePersona(p.id as any);
                    storageService.setVoiceId(p.id);
                  }}
                  className={`p-2 rounded-2xl flex flex-col items-center gap-1 border transition-all ${
                    active
                      ? 'bg-[#151B2D] shadow-lg'
                      : 'bg-[#151B2D]/40 border-[#2A3348] hover:border-[#3E4C6D]'
                  }`}
                  style={{
                    borderColor: active ? p.color : undefined,
                    boxShadow: active ? `0 0 15px ${p.color}40` : undefined,
                  }}
                >
                  <span className="text-lg">{p.icon}</span>
                  <span className="text-xs font-semibold text-[#F0F4FF]">{p.name}</span>
                </button>
              );
            })}
          </div>
        </section>

        {/* Language Section */}
        <section className="space-y-2">
          <h2 className="text-sm font-semibold tracking-wider text-[#F0F4FF]">
            {isAf ? 'Taal' : 'Language'}
          </h2>
          <div className="grid grid-cols-2 gap-3 p-1.5 bg-[#151B2D]/70 border border-[#2A3348] rounded-2xl">
            <button
              id="lang-en-btn"
              type="button"
              onClick={() => handleSelectLanguage('en')}
              className={`py-2.5 px-4 rounded-xl text-sm font-medium transition-all duration-200 ${
                settings.language === 'en'
                  ? 'bg-[#00F0FF]/20 text-[#00F0FF] border border-[#00F0FF]/60 shadow-[0_0_12px_rgba(0,240,255,0.25)]'
                  : 'text-[#94A3B8] hover:text-[#F0F4FF]'
              }`}
            >
              English
            </button>
            <button
              id="lang-af-btn"
              type="button"
              onClick={() => handleSelectLanguage('af')}
              className={`py-2.5 px-4 rounded-xl text-sm font-medium transition-all duration-200 ${
                settings.language === 'af'
                  ? 'bg-[#00F0FF]/20 text-[#00F0FF] border border-[#00F0FF]/60 shadow-[0_0_12px_rgba(0,240,255,0.25)]'
                  : 'text-[#94A3B8] hover:text-[#F0F4FF]'
              }`}
            >
              Afrikaans
            </button>
          </div>
        </section>

        {/* Bound Voice & Speech Cadence */}
        <section className="space-y-2.5">
          <h2 className="text-sm font-semibold tracking-wider text-[#F0F4FF]">
            {isAf ? 'Stem & Spraakspoed' : 'Voice & Speech Cadence'}
          </h2>
          <div
            className="p-4 rounded-2xl bg-[#151B2D]/80 border space-y-4"
            style={{ borderColor: `${activePersonaConfig.colorHex}50` }}
          >
            <div className="flex items-center gap-3">
              <div
                className="w-10 h-10 rounded-xl flex items-center justify-center shrink-0"
                style={{
                  backgroundColor: `${activePersonaConfig.colorHex}25`,
                  color: activePersonaConfig.colorHex,
                }}
              >
                <Mic className="w-5 h-5" />
              </div>
              <div className="flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-semibold text-[#F0F4FF]">
                    {isAf ? `${activePersonaConfig.name} se gekoppelde stem` : `${activePersonaConfig.name}'s Bound Voice`}
                  </span>
                  <span
                    className="px-2 py-0.5 text-[10px] font-bold rounded-full"
                    style={{
                      backgroundColor: `${activePersonaConfig.colorHex}25`,
                      color: activePersonaConfig.colorHex,
                    }}
                  >
                    AUTO-BOUND
                  </span>
                </div>
                <p className="text-xs text-[#94A3B8]">
                  {isAf
                    ? 'Stem bind outomaties aan gekose karakteravatar'
                    : 'Acoustic timbre binds directly to selected character'}
                </p>
              </div>
            </div>

            <div className="pt-2 border-t border-[#2A3348] space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-semibold text-[#F0F4FF]">
                  {isAf ? 'Praatspoed / Tempo:' : 'Speech Speed / Tempo:'}
                </span>
                <span
                  className="px-2 py-0.5 text-xs font-bold rounded-lg"
                  style={{
                    backgroundColor: `${activePersonaConfig.colorHex}20`,
                    color: activePersonaConfig.colorHex,
                  }}
                >
                  {(settings.speechSpeed ?? 0.85).toFixed(2)}x {(settings.speechSpeed ?? 0.85) <= 0.85 ? (isAf ? '(Natuurlik)' : '(Calm & Natural)') : ''}
                </span>
              </div>
              <input
                type="range"
                min="0.50"
                max="1.30"
                step="0.05"
                value={settings.speechSpeed ?? 0.85}
                onChange={(e) => {
                  const val = parseFloat(e.target.value);
                  onUpdateSettings({ speechSpeed: val });
                }}
                className="w-full accent-[#00F0FF] cursor-pointer"
                style={{ accentColor: activePersonaConfig.colorHex }}
              />
              <p className="text-[11px] text-[#94A3B8] italic">
                {isAf
                  ? "0.85x lewer 'n rustige, natuurlike menslike gesprekspas sonder om gejaagd te klink."
                  : '0.85x delivers a relaxed, natural human tempo with room to breathe.'}
              </p>
            </div>
          </div>
        </section>

        {/* Memory Navigation */}
        <section className="space-y-2">
          <h2 className="text-sm font-semibold tracking-wider text-[#F0F4FF]">
            {isAf ? 'Geheue' : 'Memory'}
          </h2>
          <div
            id="manage-memory-card"
            onClick={onNavigateToMemory}
            className="flex items-center justify-between p-4 bg-[#151B2D]/70 border border-[#2A3348] hover:border-[#A855F7]/50 rounded-2xl cursor-pointer transition-all duration-200"
          >
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-[#A855F7]/15 text-[#A855F7] flex items-center justify-center">
                <Brain className="w-5 h-5" />
              </div>
              <div>
                <h3 className="text-sm font-semibold text-[#F0F4FF]">
                  {isAf ? 'Bestuur geheue' : 'Manage memory'}
                </h3>
                <p className="text-xs text-[#94A3B8]">
                  {isAf
                    ? 'Sien en beheer wat Eve onthou'
                    : 'View and control what Eve remembers'}
                </p>
              </div>
            </div>
            <span className="text-[#94A3B8] text-sm">→</span>
          </div>
        </section>

        {/* Appearance */}
        <section className="space-y-2">
          <h2 className="text-sm font-semibold tracking-wider text-[#F0F4FF]">
            {isAf ? 'Voorkoms' : 'Appearance'}
          </h2>
          <div className="flex items-center justify-between p-4 bg-[#151B2D]/70 border border-[#2A3348] rounded-2xl">
            <div>
              <h3 className="text-sm font-medium text-[#F0F4FF]">
                {isAf ? 'Donker futuristiese tema' : 'Dark futuristic theme'}
              </h3>
              <p className="text-xs text-[#94A3B8]">
                {isAf
                  ? 'Altyd aktief in hierdie weergawe'
                  : 'Always on in this version'}
              </p>
            </div>
            <div className="w-10 h-6 bg-[#00F0FF]/30 border border-[#00F0FF] rounded-full flex items-center justify-end px-1">
              <div className="w-4 h-4 rounded-full bg-[#00F0FF]" />
            </div>
          </div>
        </section>

        {/* Danger Zone */}
        <section className="space-y-2 pt-2">
          <h2 className="text-sm font-semibold tracking-wider text-[#FF6B6B]">
            {isAf ? 'Gevaar sone' : 'Danger zone'}
          </h2>
          <button
            id="clear-chat-history-btn"
            type="button"
            onClick={() => setShowConfirmClear(true)}
            className="w-full py-3 px-4 rounded-2xl border border-[#FF6B6B]/40 hover:border-[#FF6B6B] text-[#FF6B6B] bg-[#FF6B6B]/10 hover:bg-[#FF6B6B]/15 text-sm font-medium flex items-center justify-center gap-2 transition-colors"
          >
            <Trash2 className="w-4 h-4" />
            <span>
              {isAf ? 'Vee kletsgeskiedenis uit' : 'Clear chat history'}
            </span>
          </button>
        </section>
      </div>

      {/* Clear Confirmation Modal */}
      {showConfirmClear && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm">
          <div className="max-w-sm w-full bg-[#151B2D] border border-[#2A3348] rounded-2xl p-5 space-y-4 shadow-2xl">
            <div className="flex items-center gap-3 text-[#FF6B6B]">
              <ShieldAlert className="w-6 h-6 shrink-0" />
              <h3 className="text-base font-semibold text-[#F0F4FF]">
                {isAf ? 'Vee kletsgeskiedenis uit?' : 'Clear chat history?'}
              </h3>
            </div>
            <p className="text-sm text-[#94A3B8]">
              {isAf
                ? 'Dit kan nie ongedaan gemaak word nie.'
                : 'This will permanently erase your current conversation. This cannot be undone.'}
            </p>
            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                type="button"
                onClick={() => setShowConfirmClear(false)}
                className="px-4 py-2 rounded-xl text-sm font-medium text-[#94A3B8] hover:text-[#F0F4FF] hover:bg-[#1E263C]"
              >
                {isAf ? 'Kanselleer' : 'Cancel'}
              </button>
              <button
                type="button"
                onClick={() => {
                  onClearHistory();
                  setShowConfirmClear(false);
                }}
                className="px-4 py-2 rounded-xl text-sm font-medium bg-[#FF6B6B] hover:bg-[#FF6B6B]/90 text-white shadow-lg"
              >
                {isAf ? 'Vee uit' : 'Clear'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
