import React, { useState } from 'react';
import { Volume2, CheckCheck, Copy, Check } from 'lucide-react';
import { ChatMessage, PersonaConfig } from '../types';
import { RichMessageCard } from './RichMessageCard';

interface MessageBubbleProps {
  message: ChatMessage;
  persona: PersonaConfig;
  onPlayVoice?: (text: string) => void;
  onOpenImage?: (url: string, title?: string) => void;
}

export const MessageBubble: React.FC<MessageBubbleProps> = ({
  message,
  persona,
  onPlayVoice,
  onOpenImage,
}) => {
  const [copied, setCopied] = useState(false);
  const isUser = message.role === 'user';

  const handleCopy = async (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!message.content) return;
    try {
      await navigator.clipboard.writeText(message.content);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Fallback
    }
  };

  const formatTime = (isoString?: string) => {
    if (!isoString) return '10:33 AM';
    try {
      const dt = new Date(isoString);
      return dt.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } catch {
      return '10:33 AM';
    }
  };

  if (isUser) {
    return (
      <div
        id={`message-${message.id}`}
        className="flex w-full justify-end my-1 px-1"
      >
        <div className="max-w-[78%] sm:max-w-[70%] bg-[#171C2C] border border-[#262D42] rounded-2xl px-3.5 py-2.5 shadow-md relative group">
          {/* Top-right time & quick copy action */}
          <div className="flex items-center justify-between gap-2 text-[10px] text-[#64748B] mb-1">
            <button
              type="button"
              onClick={handleCopy}
              className="text-[#64748B] hover:text-[#00F0FF] p-0.5 rounded transition-colors flex items-center gap-1"
              title="Copy message"
            >
              {copied ? (
                <span className="flex items-center gap-0.5 text-emerald-400 font-semibold text-[10px]">
                  <Check className="w-3 h-3" /> Copied
                </span>
              ) : (
                <Copy className="w-3 h-3 opacity-60 group-hover:opacity-100 transition-opacity" />
              )}
            </button>
            <span>{formatTime(message.timestamp)}</span>
          </div>

          {/* User Message Text - selectable with cursor */}
          <p className="text-[13px] sm:text-sm text-[#F0F4FF] leading-snug break-words select-text cursor-text">
            {message.content}
          </p>

          {/* Bottom-right double checkmarks */}
          <div className="flex justify-end items-center gap-1 mt-1">
            <CheckCheck
              className="w-3.5 h-3.5"
              style={{ color: persona.colorHex }}
            />
          </div>
        </div>
      </div>
    );
  }

  // Assistant / Persona Message
  return (
    <div
      id={`message-${message.id}`}
      className="flex w-full justify-start items-start gap-2.5 my-2 px-1"
    >
      {/* Mini persona avatar */}
      <button
        type="button"
        onClick={() => onOpenImage?.(persona.avatarUrl, `${persona.name} ${persona.signatureIcon}`)}
        className="w-7 h-7 rounded-full overflow-hidden shrink-0 border mt-1 hover:scale-105 transition-transform cursor-pointer focus:outline-none"
        style={{ borderColor: `${persona.colorHex}60` }}
        title={`View ${persona.name}'s photo`}
      >
        <img
          src={persona.avatarUrl}
          alt={persona.name}
          className="w-full h-full object-cover"
        />
      </button>

      {/* Message Content Container */}
      <div className="max-w-[82%] sm:max-w-[75%] space-y-1 group">
        {/* Name & Time header with Voice and Copy actions */}
        <div className="flex items-center gap-2 text-[11px] text-[#94A3B8] px-1">
          <span className="font-semibold text-[#F0F4FF]">{persona.name}</span>
          <span className="text-[10px] text-[#64748B]">
            {formatTime(message.timestamp)}
          </span>
          {onPlayVoice && message.content && (
            <button
              type="button"
              onClick={() => onPlayVoice(message.content)}
              className="p-0.5 text-[#64748B] hover:text-[#00F0FF] transition-colors ml-0.5"
              title="Speak message"
            >
              <Volume2 className="w-3 h-3" />
            </button>
          )}
          {message.content && (
            <button
              type="button"
              onClick={handleCopy}
              className="p-0.5 text-[#64748B] hover:text-[#00F0FF] transition-colors ml-0.5 flex items-center gap-1"
              title="Copy message"
            >
              {copied ? (
                <span className="flex items-center gap-0.5 text-emerald-400 text-[10px] font-semibold">
                  <Check className="w-3 h-3" /> Copied
                </span>
              ) : (
                <Copy className="w-3 h-3 opacity-60 group-hover:opacity-100 transition-opacity" />
              )}
            </button>
          )}
        </div>

        {/* Message Bubble Text - selectable with cursor */}
        {message.content && (
          <div className="bg-[#121625] border border-[#22293D] rounded-2xl px-3.5 py-2.5 shadow-md">
            <p className="text-[13px] sm:text-sm text-[#E2E8F0] leading-relaxed whitespace-pre-wrap break-words select-text cursor-text">
              {message.content}
            </p>
          </div>
        )}

        {/* Rich Card (Image, Song, Workout, Planning) */}
        {message.richCard && (
          <RichMessageCard
            card={message.richCard}
            persona={persona}
            onOpenImage={onOpenImage}
          />
        )}
      </div>
    </div>
  );
};
