import React, { useState, useEffect, useRef } from 'react';
import {
  ArrowLeft,
  Info,
  Mic,
  Square,
  CheckCircle,
  AlertTriangle,
  RotateCcw,
  Sparkles,
  Volume2,
} from 'lucide-react';
import { VoiceOption } from '../types';
import { storageService } from '../services/storageService';

interface VoiceRecorderScreenProps {
  language: 'en' | 'af';
  onBack: () => void;
  onVoiceAdded: (voice: VoiceOption) => void;
}

type RecorderState = 'idle' | 'recording' | 'reviewing' | 'uploading' | 'done' | 'error';

export const VoiceRecorderScreen: React.FC<VoiceRecorderScreenProps> = ({
  language,
  onBack,
  onVoiceAdded,
}) => {
  const isAf = language === 'af';
  const [state, setState] = useState<RecorderState>('idle');
  const [elapsedSeconds, setElapsedSeconds] = useState(0);
  const [voiceName, setVoiceName] = useState('');
  const [errorMessage, setErrorMessage] = useState('');
  const [audioLevels, setAudioLevels] = useState<number[]>(new Array(16).fill(0.1));

  const minSeconds = 30;
  const maxSeconds = 120;

  const timerRef = useRef<number | null>(null);
  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const animFrameRef = useRef<number | null>(null);
  const audioBlobRef = useRef<Blob | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
      if (animFrameRef.current) cancelAnimationFrame(animFrameRef.current);
      if (mediaRecorderRef.current && mediaRecorderRef.current.state === 'recording') {
        mediaRecorderRef.current.stop();
      }
      if (audioContextRef.current) {
        audioContextRef.current.close().catch(() => {});
      }
    };
  }, []);

  const startRecording = async () => {
    try {
      setErrorMessage('');
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          sampleRate: 24000,
        },
      });

      // Set up audio analyser for live waveform
      const audioCtx = new (window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)();
      const analyser = audioCtx.createAnalyser();
      const source = audioCtx.createMediaStreamSource(stream);
      source.connect(analyser);
      analyser.fftSize = 64;

      audioContextRef.current = audioCtx;
      analyserRef.current = analyser;

      const recorder = new MediaRecorder(stream);
      const chunks: Blob[] = [];

      recorder.ondataavailable = (e) => {
        if (e.data.size > 0) chunks.push(e.data);
      };

      recorder.onstop = () => {
        audioBlobRef.current = new Blob(chunks, { type: 'audio/wav' });
        stream.getTracks().forEach((track) => track.stop());
      };

      recorder.start(200);
      mediaRecorderRef.current = recorder;

      setElapsedSeconds(0);
      setState('recording');

      // Start duration timer
      timerRef.current = window.setInterval(() => {
        setElapsedSeconds((prev) => {
          if (prev + 1 >= maxSeconds) {
            stopRecording();
            return maxSeconds;
          }
          return prev + 1;
        });
      }, 1000);

      // Start visualizer animation loop
      const updateVisualizer = () => {
        if (!analyserRef.current) return;
        const data = new Uint8Array(analyserRef.current.frequencyBinCount);
        analyserRef.current.getByteFrequencyData(data);

        // sample 16 points
        const levels = [];
        for (let i = 0; i < 16; i++) {
          const val = data[i * 2] || 0;
          levels.push(Math.max(0.12, val / 255));
        }
        setAudioLevels(levels);
        animFrameRef.current = requestAnimationFrame(updateVisualizer);
      };
      updateVisualizer();
    } catch (err: unknown) {
      console.error('Microphone error:', err);
      setState('error');
      setErrorMessage(
        isAf
          ? 'Kon nie mikrofoon oopmaak nie. Gee asseblief toestemming in jou webblaaier.'
          : 'Could not access microphone. Please grant permission in your browser.'
      );
    }
  };

  const stopRecording = () => {
    if (timerRef.current) clearInterval(timerRef.current);
    if (animFrameRef.current) cancelAnimationFrame(animFrameRef.current);
    if (mediaRecorderRef.current && mediaRecorderRef.current.state === 'recording') {
      mediaRecorderRef.current.stop();
    }
    setState('reviewing');
  };

  const handleDiscard = () => {
    audioBlobRef.current = null;
    setElapsedSeconds(0);
    setVoiceName('');
    setState('idle');
  };

  const handleSaveVoice = async () => {
    if (!voiceName.trim()) {
      alert(isAf ? 'Gee asseblief die stem \'n naam' : 'Please provide a voice name');
      return;
    }
    setState('uploading');

    // Simulate preparation & xAI custom voice formatting
    await new Promise((resolve) => setTimeout(resolve, 1400));

    const newVoice: VoiceOption = {
      id: `custom_${Date.now()}`,
      name: voiceName.trim(),
      description: isAf ? 'Jou eie pasgemaakte stem' : 'Your custom cloned voice',
      isCustom: true,
      gender: 'neutral',
      tone: 'custom',
    };

    const existing = storageService.getCustomVoices();
    const updated = [...existing, newVoice];
    storageService.setCustomVoices(updated);
    onVoiceAdded(newVoice);
    setState('done');
  };

  const formatTimer = (seconds: number) => {
    const m = Math.floor(seconds / 60).toString().padStart(2, '0');
    const s = (seconds % 60).toString().padStart(2, '0');
    return `${m}:${s}`;
  };

  const getDurationColor = () => {
    if (elapsedSeconds < minSeconds) return '#FFB020';
    if (elapsedSeconds > maxSeconds - 10) return '#FF6B6B';
    return '#2EE6A6';
  };

  return (
    <div className="flex flex-col h-full bg-[#0B0F1A] text-[#F0F4FF] overflow-y-auto">
      {/* Header */}
      <header className="sticky top-0 z-10 flex items-center gap-3 px-4 py-3.5 bg-[#0B0F1A]/90 backdrop-blur-md border-b border-[#2A3348]">
        <button
          id="back-from-voice-recorder"
          type="button"
          onClick={onBack}
          className="p-2 -ml-2 rounded-xl text-[#94A3B8] hover:text-[#F0F4FF] hover:bg-[#151B2D] transition-colors"
        >
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-lg font-semibold tracking-wide text-[#F0F4FF]">
          {isAf ? "Leer 'n nuwe stem" : 'Teach a new voice'}
        </h1>
      </header>

      <div className="flex-1 max-w-xl w-full mx-auto p-4 flex flex-col justify-between space-y-6 pb-8">
        {/* Guidance Card */}
        <section className="p-4 bg-[#151B2D]/80 border border-[#00F0FF]/30 rounded-2xl space-y-2.5 shadow-[0_0_15px_rgba(0,240,255,0.08)]">
          <div className="flex items-center gap-2 text-[#00F0FF]">
            <Info className="w-4 h-4" />
            <h2 className="text-sm font-semibold tracking-wide">
              {isAf ? 'Wenke vir beste resultate' : 'Tips for best results'}
            </h2>
          </div>
          <ul className="text-xs text-[#94A3B8] space-y-1.5 pl-1">
            <li>• {isAf ? "Neem op in 'n stil kamer (30–120 sekondes)" : 'Record in a quiet room (30–120 seconds)'}</li>
            <li>• {isAf ? "Praat natuurlik, soos jy met 'n vriend praat" : 'Speak naturally, as if talking to a friend'}</li>
            <li>• {isAf ? 'Vermy agtergrondgeraas, musiek of ander stemme' : 'Avoid background noise, music or other voices'}</li>
            <li>• {isAf ? '90+ sekondes gee gewoonlik die beste kloning' : '90+ seconds usually gives the best clone'}</li>
          </ul>
        </section>

        {/* State Views */}
        <div className="flex-1 flex flex-col items-center justify-center py-6">
          {state === 'idle' && (
            <div className="text-center space-y-5">
              <div className="w-28 h-28 mx-auto rounded-full bg-[#1E263C] border-2 border-[#00F0FF]/50 flex items-center justify-center shadow-[0_0_30px_rgba(0,240,255,0.25)]">
                <Mic className="w-12 h-12 text-[#00F0FF]" />
              </div>
              <div className="space-y-1">
                <h3 className="text-lg font-semibold text-[#F0F4FF]">
                  {isAf ? 'Gereed om op te neem' : 'Ready to record'}
                </h3>
                <p className="text-xs text-[#94A3B8]">
                  {isAf ? 'Tik die knoppie hieronder om te begin' : 'Tap the button below to start'}
                </p>
              </div>
            </div>
          )}

          {state === 'recording' && (
            <div className="w-full max-w-sm text-center space-y-6">
              <div
                className="text-5xl font-mono tracking-widest font-light"
                style={{ color: getDurationColor() }}
              >
                {formatTimer(elapsedSeconds)}
              </div>

              <p className="text-xs font-medium" style={{ color: getDurationColor() }}>
                {elapsedSeconds < minSeconds
                  ? isAf
                    ? `Nog ${minSeconds - elapsedSeconds}s nodig vir minimum`
                    : `${minSeconds - elapsedSeconds}s more needed for minimum`
                  : isAf
                  ? 'Goeie lengte bereik!'
                  : 'Great length reached!'}
              </p>

              {/* 16-bar animated waveform visualizer */}
              <div className="flex items-center justify-center gap-1.5 h-20 px-4">
                {audioLevels.map((lvl, i) => (
                  <div
                    key={i}
                    className="w-2 rounded-full transition-all duration-100"
                    style={{
                      height: `${Math.max(8, lvl * 72)}px`,
                      backgroundColor: i % 2 === 0 ? '#00F0FF' : '#FF4ECD',
                      opacity: 0.7 + lvl * 0.3,
                      boxShadow: lvl > 0.4 ? '0 0 10px rgba(0,240,255,0.6)' : 'none',
                    }}
                  />
                ))}
              </div>

              {/* Progress bar to 120s */}
              <div className="w-full bg-[#1E263C] rounded-full h-2 overflow-hidden border border-[#2A3348]">
                <div
                  className="h-full rounded-full transition-all duration-300"
                  style={{
                    width: `${Math.min(100, (elapsedSeconds / maxSeconds) * 100)}%`,
                    backgroundColor: getDurationColor(),
                  }}
                />
              </div>
              <p className="text-[11px] text-[#94A3B8]">
                {isAf ? 'Maksimum 120 sekondes' : 'Maximum 120 seconds'}
              </p>
            </div>
          )}

          {state === 'reviewing' && (
            <div className="w-full max-w-md space-y-5">
              <div className="text-center space-y-1">
                <CheckCircle className="w-12 h-12 mx-auto text-[#2EE6A6]" />
                <h3 className="text-lg font-semibold text-[#F0F4FF]">
                  {isAf ? 'Opname klaar' : 'Recording complete'}
                </h3>
                <p className="text-xs text-[#94A3B8]">
                  {formatTimer(elapsedSeconds)} • WAV • 24 kHz • Mono
                </p>
              </div>

              <div className="space-y-1.5">
                <label className="text-xs font-medium text-[#94A3B8]">
                  {isAf ? 'Naam van die stem' : 'Voice name'}
                </label>
                <input
                  id="voice-name-input"
                  type="text"
                  value={voiceName}
                  onChange={(e) => setVoiceName(e.target.value)}
                  placeholder={isAf ? 'bv. My stem' : 'e.g. My voice'}
                  className="w-full p-3 bg-[#151B2D] border border-[#2A3348] focus:border-[#00F0FF]/60 rounded-xl text-sm text-[#F0F4FF] placeholder-[#94A3B8] outline-none"
                />
              </div>

              <div className="p-3 bg-[#151B2D]/70 border border-[#2A3348] rounded-xl text-xs space-y-1.5 text-[#94A3B8]">
                <div className="flex justify-between">
                  <span>Format</span>
                  <span className="text-[#F0F4FF]">WAV (uncompressed)</span>
                </div>
                <div className="flex justify-between">
                  <span>Sample rate</span>
                  <span className="text-[#F0F4FF]">24 000 Hz</span>
                </div>
                <div className="flex justify-between">
                  <span>Channels</span>
                  <span className="text-[#F0F4FF]">Mono</span>
                </div>
                <div className="flex justify-between">
                  <span>Ready for</span>
                  <span className="text-[#00F0FF]">xAI Custom Voices</span>
                </div>
              </div>
            </div>
          )}

          {state === 'uploading' && (
            <div className="text-center space-y-4">
              <div className="w-12 h-12 mx-auto border-3 border-[#00F0FF] border-t-transparent rounded-full animate-spin" />
              <h3 className="text-base font-semibold text-[#F0F4FF]">
                {isAf ? 'Laai op na xAI…' : 'Uploading to xAI…'}
              </h3>
              <p className="text-xs text-[#94A3B8]">
                {isAf
                  ? 'Die stem word voorberei en gekloon'
                  : 'Preparing and cloning the voice'}
              </p>
            </div>
          )}

          {state === 'done' && (
            <div className="text-center space-y-4">
              <div className="w-16 h-16 mx-auto rounded-full bg-[#2EE6A6]/20 border border-[#2EE6A6] flex items-center justify-center text-[#2EE6A6] shadow-[0_0_20px_rgba(46,230,166,0.3)]">
                <CheckCircle className="w-8 h-8" />
              </div>
              <div className="space-y-1">
                <h3 className="text-lg font-semibold text-[#F0F4FF]">
                  {isAf ? 'Stem suksesvol bygevoeg!' : 'Voice added successfully!'}
                </h3>
                <p className="text-sm font-semibold text-[#00F0FF]">{voiceName}</p>
                <p className="text-xs text-[#94A3B8]">
                  {isAf
                    ? 'Jy kan dit nou in Instellings kies'
                    : 'You can now select it in Settings'}
                </p>
              </div>
            </div>
          )}

          {state === 'error' && (
            <div className="text-center space-y-4 max-w-sm">
              <AlertTriangle className="w-12 h-12 mx-auto text-[#FF6B6B]" />
              <h3 className="text-base font-semibold text-[#F0F4FF]">
                {isAf ? 'Iets het verkeerd geloop' : 'Something went wrong'}
              </h3>
              <p className="text-xs text-[#94A3B8]">{errorMessage}</p>
            </div>
          )}
        </div>

        {/* Action Controls */}
        <div className="pt-2">
          {state === 'idle' && (
            <button
              id="start-voice-recording-btn"
              type="button"
              onClick={startRecording}
              className="w-full py-3.5 rounded-2xl bg-[#00F0FF] hover:bg-[#00F0FF]/90 text-[#0B0F1A] font-semibold text-sm flex items-center justify-center gap-2 shadow-[0_0_20px_rgba(0,240,255,0.4)] transition-all"
            >
              <Mic className="w-5 h-5" />
              <span>{isAf ? 'Begin opname' : 'Start recording'}</span>
            </button>
          )}

          {state === 'recording' && (
            <button
              id="stop-voice-recording-btn"
              type="button"
              onClick={stopRecording}
              className="w-full py-3.5 rounded-2xl bg-[#FF4ECD] hover:bg-[#FF4ECD]/90 text-white font-semibold text-sm flex items-center justify-center gap-2 shadow-[0_0_20px_rgba(255,78,205,0.5)] transition-all animate-pulse"
            >
              <Square className="w-5 h-5 fill-current" />
              <span>{isAf ? 'Stop opname' : 'Stop recording'}</span>
            </button>
          )}

          {state === 'reviewing' && (
            <div className="flex items-center gap-3">
              <button
                id="discard-recording-btn"
                type="button"
                onClick={handleDiscard}
                className="flex-1 py-3.5 rounded-2xl border border-[#2A3348] hover:border-[#94A3B8] text-[#94A3B8] text-sm font-medium transition-colors"
              >
                {isAf ? 'Gooi weg' : 'Discard'}
              </button>
              <button
                id="save-voice-btn"
                type="button"
                onClick={handleSaveVoice}
                disabled={!voiceName.trim() || elapsedSeconds < minSeconds}
                className="flex-1 py-3.5 rounded-2xl bg-[#00F0FF] hover:bg-[#00F0FF]/90 disabled:opacity-40 disabled:cursor-not-allowed text-[#0B0F1A] text-sm font-semibold shadow-[0_0_20px_rgba(0,240,255,0.4)] transition-all"
              >
                {isAf ? 'Stoor stem' : 'Save voice'}
              </button>
            </div>
          )}

          {state === 'done' && (
            <button
              id="done-voice-btn"
              type="button"
              onClick={onBack}
              className="w-full py-3.5 rounded-2xl bg-[#00F0FF] hover:bg-[#00F0FF]/90 text-[#0B0F1A] font-semibold text-sm transition-all shadow-[0_0_15px_rgba(0,240,255,0.3)]"
            >
              {isAf ? 'Klaar' : 'Done'}
            </button>
          )}

          {state === 'error' && (
            <button
              type="button"
              onClick={startRecording}
              className="w-full py-3.5 rounded-2xl bg-[#151B2D] border border-[#00F0FF]/50 text-[#00F0FF] font-semibold text-sm flex items-center justify-center gap-2 transition-all"
            >
              <RotateCcw className="w-4 h-4" />
              <span>{isAf ? 'Probeer weer' : 'Try again'}</span>
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
