/**
 * Synthesizer Music Service: Plays an ambient chill/happy tune
 * via Web Audio API for the music card previews!
 */

let audioCtx: AudioContext | null = null;
let currentOscillators: OscillatorNode[] = [];
let isMusicPlaying = false;
let musicStopCallback: (() => void) | null = null;

export const synthMusicService = {
  isPlaying(): boolean {
    return isMusicPlaying;
  },

  stop(): void {
    if (currentOscillators.length > 0) {
      currentOscillators.forEach((osc) => {
        try {
          osc.stop();
          osc.disconnect();
        } catch {
          // ignore
        }
      });
      currentOscillators = [];
    }
    isMusicPlaying = false;
    musicStopCallback?.();
    musicStopCallback = null;
  },

  playTrack(onEnd?: () => void): void {
    this.stop();

    const AudioContextClass =
      window.AudioContext ||
      (window as unknown as { webkitAudioContext: typeof AudioContext })
        .webkitAudioContext;
    if (!AudioContextClass) return;

    if (!audioCtx) {
      audioCtx = new AudioContextClass();
    }
    if (audioCtx.state === 'suspended') {
      audioCtx.resume();
    }

    isMusicPlaying = true;
    musicStopCallback = onEnd || null;

    // Chord progression notes (Pentatonic / happy chill progression)
    // C major / A minor upbeat chords: C4, E4, G4, B4, C5, D5, E5, G5
    const notes = [
      261.63, 329.63, 392.0, 523.25, 440.0, 329.63, 392.0, 587.33,
      349.23, 440.0, 523.25, 659.25, 392.0, 493.88, 587.33, 783.99,
    ];

    const now = audioCtx.currentTime;
    const noteDuration = 0.45;
    const totalLoops = 10;

    for (let loop = 0; loop < totalLoops; loop++) {
      notes.forEach((freq, idx) => {
        if (!audioCtx) return;
        const startTime = now + (loop * notes.length + idx) * noteDuration;

        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();

        // Warm sine wave + soft square wave for synth vibe
        osc.type = idx % 2 === 0 ? 'sine' : 'triangle';
        osc.frequency.setValueAtTime(freq, startTime);

        gain.gain.setValueAtTime(0.001, startTime);
        gain.gain.exponentialRampToValueAtTime(0.12, startTime + 0.05);
        gain.gain.exponentialRampToValueAtTime(0.001, startTime + noteDuration - 0.05);

        osc.connect(gain);
        gain.connect(audioCtx.destination);

        osc.start(startTime);
        osc.stop(startTime + noteDuration);
        currentOscillators.push(osc);
      });
    }

    // Auto stop when finished
    const totalDuration = notes.length * totalLoops * noteDuration;
    setTimeout(() => {
      if (isMusicPlaying) {
        this.stop();
      }
    }, totalDuration * 1000);
  },
};
