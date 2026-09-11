import React, { useState } from 'react';
import { X, Download, Share2, Check, ExternalLink, ZoomIn } from 'lucide-react';
import { PersonaConfig } from '../types';

interface ImageViewerModalProps {
  isOpen: boolean;
  onClose: () => void;
  imageUrl: string | null;
  title?: string;
  subtitle?: string;
  persona?: PersonaConfig;
}

export const ImageViewerModal: React.FC<ImageViewerModalProps> = ({
  isOpen,
  onClose,
  imageUrl,
  title = 'Image Preview',
  subtitle,
  persona,
}) => {
  const [downloading, setDownloading] = useState(false);
  const [shareFeedback, setShareFeedback] = useState<string | null>(null);

  if (!isOpen || !imageUrl) return null;

  const accentColor = persona?.colorHex || '#FF4ECD';

  // Handle image download
  const handleDownload = async () => {
    try {
      setDownloading(true);
      // Clean query params like ?v=2 for filename
      const cleanUrl = imageUrl.split('?')[0];
      const filename = cleanUrl.substring(cleanUrl.lastIndexOf('/') + 1) || 'image.jpg';

      const response = await fetch(imageUrl);
      const blob = await response.blob();
      const blobUrl = URL.createObjectURL(blob);

      const link = document.createElement('a');
      link.href = blobUrl;
      link.download = filename.endsWith('.jpg') || filename.endsWith('.png') ? filename : `${filename}.jpg`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(blobUrl);

      setShareFeedback('Downloaded successfully!');
      setTimeout(() => setShareFeedback(null), 3000);
    } catch (err) {
      console.warn('Direct blob download failed, trying standard download link:', err);
      // Fallback
      const link = document.createElement('a');
      link.href = imageUrl;
      link.download = 'image.jpg';
      link.target = '_blank';
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      setShareFeedback('Opening download...');
      setTimeout(() => setShareFeedback(null), 3000);
    } finally {
      setDownloading(false);
    }
  };

  // Handle share (Web Share API with Clipboard fallback)
  const handleShare = async () => {
    const fullUrl = imageUrl.startsWith('http')
      ? imageUrl
      : `${window.location.origin}${imageUrl.startsWith('/') ? '' : '/'}${imageUrl}`;

    if (navigator.share) {
      try {
        await navigator.share({
          title: title || 'Eve Voice Companion',
          text: subtitle || 'Check out this image from Eve!',
          url: fullUrl,
        });
        setShareFeedback('Shared successfully!');
        setTimeout(() => setShareFeedback(null), 2500);
        return;
      } catch (err) {
        // If user cancelled or share failed, fallback to copy
        if ((err as Error).name !== 'AbortError') {
          console.log('navigator.share failed, copying link instead');
        }
      }
    }

    // Fallback: Copy link to clipboard
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(fullUrl);
        setShareFeedback('Link copied to clipboard!');
      } else {
        // Older fallback
        const textArea = document.createElement('textarea');
        textArea.value = fullUrl;
        document.body.appendChild(textArea);
        textArea.select();
        document.execCommand('copy');
        document.body.removeChild(textArea);
        setShareFeedback('Link copied to clipboard!');
      }
      setTimeout(() => setShareFeedback(null), 3000);
    } catch (err) {
      console.error('Failed to copy link:', err);
      setShareFeedback('Could not copy link');
      setTimeout(() => setShareFeedback(null), 2500);
    }
  };

  const handleOpenNewTab = () => {
    window.open(imageUrl, '_blank', 'noopener,noreferrer');
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6 bg-black/85 backdrop-blur-md animate-fadeIn select-none"
      onClick={onClose}
    >
      <div
        className="relative max-w-lg w-full bg-[#0E1220] border border-[#232B42] rounded-3xl overflow-hidden shadow-2xl flex flex-col max-h-[92vh] animate-scaleUp"
        style={{
          boxShadow: `0 0 40px ${accentColor}25, 0 20px 40px rgba(0,0,0,0.8)`,
        }}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Top Modal Header */}
        <div className="flex items-center justify-between px-5 py-3.5 border-b border-[#1C2337] bg-[#0E1220]/90">
          <div className="flex items-center gap-2.5 min-w-0">
            {persona && (
              <div
                className="w-7 h-7 rounded-full overflow-hidden border shrink-0"
                style={{ borderColor: accentColor }}
              >
                <img
                  src={persona.avatarUrl}
                  alt={persona.name}
                  className="w-full h-full object-cover"
                />
              </div>
            )}
            <div className="min-w-0">
              <h3 className="text-sm sm:text-base font-bold text-[#F0F4FF] truncate flex items-center gap-2">
                <span>{title}</span>
                {persona && (
                  <span
                    className="text-xs font-semibold px-2 py-0.5 rounded-full"
                    style={{
                      backgroundColor: `${accentColor}20`,
                      color: accentColor,
                    }}
                  >
                    {persona.name}
                  </span>
                )}
              </h3>
              {subtitle && (
                <p className="text-[11px] text-[#94A3B8] truncate">{subtitle}</p>
              )}
            </div>
          </div>

          <button
            type="button"
            onClick={onClose}
            className="w-8 h-8 rounded-full bg-[#181F33] hover:bg-[#252E4A] text-[#94A3B8] hover:text-white flex items-center justify-center transition-colors shrink-0"
            title="Close"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Feedback Banner (Download / Share) */}
        {shareFeedback && (
          <div
            className="px-4 py-2 text-xs font-medium flex items-center justify-center gap-1.5 transition-all text-white"
            style={{ backgroundColor: accentColor }}
          >
            <Check className="w-4 h-4" />
            <span>{shareFeedback}</span>
          </div>
        )}

        {/* Central High-Resolution Image Display */}
        <div className="relative flex-1 min-h-0 bg-[#060810] flex items-center justify-center p-3 sm:p-5 overflow-hidden">
          <div className="relative max-h-[75vh] max-w-full rounded-2xl overflow-hidden shadow-xl border border-white/10 group flex items-center justify-center">
            <img
              src={imageUrl}
              alt={title}
              referrerPolicy="no-referrer"
              className="max-h-[75vh] w-auto max-w-full object-contain rounded-2xl"
            />

            {/* Subtle decorative watermark */}
            {persona && (
              <div
                className="absolute bottom-3 right-3 pointer-events-none text-2xl font-bold drop-shadow-[0_0_10px_rgba(0,0,0,0.8)]"
                style={{
                  color: accentColor,
                  fontFamily: "'Dancing Script', 'Caveat', cursive",
                }}
              >
                {persona.signature} {persona.signatureIcon}
              </div>
            )}
          </div>
        </div>

        {/* Bottom Actions Toolbar: Download, Share, Open External */}
        <div className="px-5 py-3.5 bg-[#0A0D18] border-t border-[#1C2337] flex items-center justify-between gap-2 sm:gap-4">
          <div className="flex items-center gap-1 text-[11px] text-[#64748B]">
            <ZoomIn className="w-3.5 h-3.5 text-[#94A3B8]" />
            <span>Full Resolution</span>
          </div>

          <div className="flex items-center gap-2">
            {/* Open in new tab button */}
            <button
              type="button"
              onClick={handleOpenNewTab}
              className="p-2 sm:px-3 sm:py-2 rounded-xl bg-[#141A2B] hover:bg-[#1E263D] text-[#94A3B8] hover:text-white border border-[#232C45] text-xs font-medium flex items-center gap-1.5 transition-all active:scale-95"
              title="Open full image in new tab"
            >
              <ExternalLink className="w-4 h-4" />
              <span className="hidden sm:inline">Open</span>
            </button>

            {/* Share Button */}
            <button
              type="button"
              onClick={handleShare}
              className="px-3 py-2 sm:px-4 sm:py-2 rounded-xl bg-[#141A2B] hover:bg-[#1E263D] text-[#F0F4FF] hover:text-white border border-[#232C45] text-xs font-semibold flex items-center gap-1.5 transition-all active:scale-95 hover:border-white/20"
              title="Share or copy image link"
            >
              <Share2 className="w-4 h-4 text-[#00F0FF]" />
              <span>Share</span>
            </button>

            {/* Download Button */}
            <button
              type="button"
              onClick={handleDownload}
              disabled={downloading}
              className="px-3.5 py-2 sm:px-4 sm:py-2 rounded-xl text-white text-xs font-bold flex items-center gap-1.5 transition-all active:scale-95 shadow-lg hover:brightness-110"
              style={{
                backgroundColor: accentColor,
                boxShadow: `0 0 15px ${accentColor}50`,
              }}
              title="Download image to device"
            >
              <Download className="w-4 h-4" />
              <span>{downloading ? 'Saving...' : 'Download'}</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
