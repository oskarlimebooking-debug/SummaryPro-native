// Background Keep-Alive Module
// Keeps the page alive during recording via Wake Lock, silent audio, and Media Session API.

const BackgroundKeepAlive = (() => {
  let wakeLockSentinel = null;
  let silentAudioElement = null;
  let active = false;

  // --- Wake Lock ---

  async function acquireWakeLock() {
    if (!('wakeLock' in navigator)) return;
    try {
      wakeLockSentinel = await navigator.wakeLock.request('screen');
      wakeLockSentinel.addEventListener('release', () => {
        wakeLockSentinel = null;
      });
    } catch (err) {
      console.warn('Wake Lock failed:', err);
    }
  }

  function releaseWakeLock() {
    if (wakeLockSentinel) {
      wakeLockSentinel.release();
      wakeLockSentinel = null;
    }
  }

  // --- Silent Audio Playback ---
  // Playing near-silent audio signals the OS that the page is active media,
  // preventing background suspension (especially effective on Android).

  function createSilentWavBlob() {
    const sampleRate = 8000;
    const numSamples = sampleRate; // 1 second
    const numChannels = 1;
    const bytesPerSample = 2;
    const dataLength = numSamples * numChannels * bytesPerSample;
    const buffer = new ArrayBuffer(44 + dataLength);
    const view = new DataView(buffer);

    const writeStr = (offset, str) => {
      for (let i = 0; i < str.length; i++) view.setUint8(offset + i, str.charCodeAt(i));
    };
    writeStr(0, 'RIFF');
    view.setUint32(4, 36 + dataLength, true);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, numChannels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, sampleRate * numChannels * bytesPerSample, true);
    view.setUint16(32, numChannels * bytesPerSample, true);
    view.setUint16(34, 16, true);
    writeStr(36, 'data');
    view.setUint32(40, dataLength, true);
    // All samples are 0 (silence) — ArrayBuffer is zero-initialized
    return new Blob([buffer], { type: 'audio/wav' });
  }

  function startSilentAudio() {
    if (silentAudioElement) return;
    const blob = createSilentWavBlob();
    const url = URL.createObjectURL(blob);
    silentAudioElement = new Audio(url);
    silentAudioElement.loop = true;
    silentAudioElement.volume = 0.01; // Near-silent (0 may be optimized away by the OS)
    silentAudioElement.play().catch(() => {});
  }

  function stopSilentAudio() {
    if (!silentAudioElement) return;
    silentAudioElement.pause();
    const src = silentAudioElement.src;
    silentAudioElement.src = '';
    silentAudioElement = null;
    URL.revokeObjectURL(src);
  }

  // --- Media Session ---
  // Registers the app as an active media session so the OS shows recording status
  // on the lock screen and doesn't treat the page as idle.

  function registerMediaSession() {
    if (!('mediaSession' in navigator)) return;
    navigator.mediaSession.metadata = new MediaMetadata({
      title: 'Summary Pro – Snemanje',
      artist: 'Summary Pro',
    });
    navigator.mediaSession.playbackState = 'playing';

    navigator.mediaSession.setActionHandler('pause', () => {
      window.dispatchEvent(new CustomEvent('backgroundStopRequested'));
    });
    navigator.mediaSession.setActionHandler('play', () => {
      navigator.mediaSession.playbackState = 'playing';
    });
  }

  function unregisterMediaSession() {
    if (!('mediaSession' in navigator)) return;
    navigator.mediaSession.metadata = null;
    navigator.mediaSession.playbackState = 'none';
    try {
      navigator.mediaSession.setActionHandler('pause', null);
      navigator.mediaSession.setActionHandler('play', null);
    } catch (_) {}
  }

  // --- Visibility Change ---
  // Re-acquire wake lock when coming back to foreground (browsers release it on hide).

  function handleVisibilityChange() {
    if (document.visibilityState === 'visible' && active) {
      acquireWakeLock();
    }
  }

  document.addEventListener('visibilitychange', handleVisibilityChange);

  // --- Public API ---

  async function activate() {
    active = true;
    await acquireWakeLock();
    startSilentAudio();
    registerMediaSession();
  }

  function deactivate() {
    active = false;
    releaseWakeLock();
    stopSilentAudio();
    unregisterMediaSession();
  }

  function isActive() {
    return active;
  }

  return { activate, deactivate, isActive };
})();
