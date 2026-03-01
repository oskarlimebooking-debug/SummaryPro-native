// Summary Pro - AI Meeting Summary PWA
// Client-side only (BYOK)

// --- Constants ---
const SPEECH_KEY_STORE = 'sp_speech_key';
const GEMINI_KEY_STORE = 'sp_gemini_key';
const OPENAI_KEY_STORE = 'sp_openai_key';
const SONIOX_KEY_STORE = 'sp_soniox_key';
const LANG_STORE = 'sp_language';
const MODEL_STORE = 'sp_selected_model';
const STT_PROVIDER_STORE = 'sp_stt_provider';
const WHISPER_MODEL_STORE = 'sp_whisper_model';
const HISTORY_STORE = 'sp_history';
const SPEECH_API = 'https://speech.googleapis.com/v1';
const GEMINI_API = 'https://generativelanguage.googleapis.com/v1beta';
const OPENAI_STT_API = 'https://api.openai.com/v1/audio/transcriptions';
const SONIOX_API = 'https://api.soniox.com/v1';
const WHISPER_MAX_CHUNK_MB = 24; // Keep under 25MB API limit

// Fallback if API model listing fails
const FALLBACK_MODELS = [
  { id: 'gemini-2.5-flash', name: 'Gemini 2.5 Flash' },
  { id: 'gemini-2.5-pro', name: 'Gemini 2.5 Pro' },
];

// Patterns to exclude from model list (non-text models)
const EXCLUDED_PATTERNS = [
  'tts', 'image', 'embedding', 'aqa', 'native-audio', 'bisheng', 'learnlm',
];

// Dynamic model list - populated from API
let availableModels = [];

const SUMMARY_PROMPT = `Si profesionalen AI asistent za povzetke sestankov in zapiskov.

NALOGA:
Analiziraj spodnji surovi prepis govora/zapiskov in ustvari strukturirane povzetke v slovenščini.

PRAVILA:
1. Ugotovi, ali prepis vsebuje ENO ali VEČ ločenih tem/sestankov/zapiskov.
2. Za vsako ločeno temo ustvari SVOJ povzetek.
3. Vsi povzetki MORAJO biti v SLOVENŠČINI, ne glede na jezik prepisa.
4. Vsak povzetek naj vsebuje:
   - Jasen, kratek naslov
   - Ključne točke (bullet points)
   - Sklepe ali dogovorjene naloge (če obstajajo)
5. Bodi jedrnat in konkreten.

OBLIKA ODGOVORA:
Vrni IZKLJUČNO veljaven JSON brez dodatnega besedila ali markdown ograj:
{"summaries":[{"title":"Naslov","content":"Povzetek z markdown oblikovanjem (## naslovi, - alineje, **krepko**)"}]}

PREPIS:
---
`;

// --- State ---
let speechApiKey = '';
let geminiApiKey = '';
let openaiApiKey = '';
let sonioxApiKey = '';
let recorder = null;
let chunks = [];
let recStartTime = 0;
let timerInterval = null;
let audioCtx = null;
let analyser = null;
let animFrame = null;
let modelResults = {};
let currentHistoryId = null;
let currentAppTab = 'record';
let recordingSessionId = null;
let chunkIndex = 0;

// --- Recording Persistence (IndexedDB) ---

const RecordingDB = (() => {
  const DB_NAME = 'summary-pro-recordings';
  const STORE_NAME = 'chunks';
  const DB_VERSION = 1;

  function open() {
    return new Promise((resolve, reject) => {
      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = (e) => {
        const db = e.target.result;
        if (!db.objectStoreNames.contains(STORE_NAME)) {
          const store = db.createObjectStore(STORE_NAME, { keyPath: 'id', autoIncrement: true });
          store.createIndex('sessionId', 'sessionId', { unique: false });
        }
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }

  async function saveChunk(sessionId, blob, idx) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readwrite');
      tx.objectStore(STORE_NAME).add({
        sessionId,
        chunkIndex: idx,
        blob,
        timestamp: Date.now(),
      });
      tx.oncomplete = () => { db.close(); resolve(); };
      tx.onerror = () => { db.close(); reject(tx.error); };
    });
  }

  async function getSessionChunks(sessionId) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readonly');
      const index = tx.objectStore(STORE_NAME).index('sessionId');
      const req = index.getAll(sessionId);
      req.onsuccess = () => {
        db.close();
        const results = req.result.sort((a, b) => a.chunkIndex - b.chunkIndex);
        resolve(results);
      };
      req.onerror = () => { db.close(); reject(req.error); };
    });
  }

  async function deleteSession(sessionId) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readwrite');
      const store = tx.objectStore(STORE_NAME);
      const index = store.index('sessionId');
      const req = index.openCursor(sessionId);
      req.onsuccess = (e) => {
        const cursor = e.target.result;
        if (cursor) {
          cursor.delete();
          cursor.continue();
        }
      };
      tx.oncomplete = () => { db.close(); resolve(); };
      tx.onerror = () => { db.close(); reject(tx.error); };
    });
  }

  async function getOrphanedSessions() {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readonly');
      const req = tx.objectStore(STORE_NAME).getAll();
      req.onsuccess = () => {
        db.close();
        const sessions = new Map();
        for (const row of req.result) {
          if (!sessions.has(row.sessionId)) {
            sessions.set(row.sessionId, { sessionId: row.sessionId, count: 0, earliest: row.timestamp });
          }
          const s = sessions.get(row.sessionId);
          s.count++;
          if (row.timestamp < s.earliest) s.earliest = row.timestamp;
        }
        resolve([...sessions.values()]);
      };
      req.onerror = () => { db.close(); reject(req.error); };
    });
  }

  return { saveChunk, getSessionChunks, deleteSession, getOrphanedSessions };
})();

// --- Init ---
document.addEventListener('DOMContentLoaded', init);

function init() {
  speechApiKey = localStorage.getItem(SPEECH_KEY_STORE) || '';
  geminiApiKey = localStorage.getItem(GEMINI_KEY_STORE) || '';
  openaiApiKey = localStorage.getItem(OPENAI_KEY_STORE) || '';
  sonioxApiKey = localStorage.getItem(SONIOX_KEY_STORE) || '';
  const savedLang = localStorage.getItem(LANG_STORE);
  const savedSttProvider = localStorage.getItem(STT_PROVIDER_STORE);
  const savedWhisperModel = localStorage.getItem(WHISPER_MODEL_STORE);

  if (savedLang) {
    el('language').value = savedLang;
  }
  if (savedSttProvider) {
    el('sttProvider').value = savedSttProvider;
  }
  if (savedWhisperModel) {
    el('whisperModel').value = savedWhisperModel;
  }
  updateSttProviderUI();

  const hasAnySttKey = speechApiKey || openaiApiKey || sonioxApiKey;
  if (hasAnySttKey && geminiApiKey) {
    showSection('main');
    el('appTabs').classList.remove('hidden');
    fetchAvailableModels();
  }

  // Events
  el('saveKeysBtn').addEventListener('click', saveKeys);
  el('settingsBtn').addEventListener('click', showSettings);
  el('recordBtn').addEventListener('click', startRecording);
  el('stopBtn').addEventListener('click', stopRecording);
  el('copyRawBtn').addEventListener('click', () => {
    copyToClipboard(el('rawTranscript').textContent, el('copyRawBtn'));
  });
  el('newSessionBtn').addEventListener('click', newSession);
  el('refreshModels').addEventListener('click', fetchAvailableModels);
  el('language').addEventListener('change', () => {
    localStorage.setItem(LANG_STORE, el('language').value);
  });
  el('modelSelect').addEventListener('change', () => {
    localStorage.setItem(MODEL_STORE, el('modelSelect').value);
  });
  el('sttProvider').addEventListener('change', () => {
    localStorage.setItem(STT_PROVIDER_STORE, el('sttProvider').value);
    updateSttProviderUI();
  });
  el('whisperModel').addEventListener('change', () => {
    localStorage.setItem(WHISPER_MODEL_STORE, el('whisperModel').value);
  });

  // Tab navigation
  document.querySelectorAll('.app-tab').forEach((tab) => {
    tab.addEventListener('click', () => switchAppTab(tab.dataset.tab));
  });

  // History events
  el('historyBackBtn').addEventListener('click', () => switchAppTab('history'));
  el('historyDeleteBtn').addEventListener('click', deleteCurrentHistoryEntry);
  el('historyCopyTranscriptBtn').addEventListener('click', () => {
    copyToClipboard(el('historyTranscript').textContent, el('historyCopyTranscriptBtn'));
  });
  el('regenerateSummaryBtn').addEventListener('click', regenerateSummary);

  // Enter to save keys
  el('geminiKeyInput').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') saveKeys();
  });
  el('speechKeyInput').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') el('openaiKeyInput').focus();
  });
  el('openaiKeyInput').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') el('sonioxKeyInput').focus();
  });
  el('sonioxKeyInput').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') el('geminiKeyInput').focus();
  });

  // Check for orphaned recordings from a previous crash/suspension
  checkOrphanedRecordings();
}

async function checkOrphanedRecordings() {
  try {
    const sessions = await RecordingDB.getOrphanedSessions();
    if (sessions.length === 0) return;

    const banner = document.createElement('div');
    banner.className = 'card recovery-banner';
    banner.innerHTML =
      '<p><strong>Najden nedokončan posnetek</strong></p>' +
      '<p class="hint">Posnetek je bil prekinjen. Želite nadaljevati z obdelavo?</p>' +
      '<div class="recovery-actions">' +
      '<button class="btn btn-primary btn-sm" id="recoverBtn">Obnovi</button>' +
      '<button class="btn btn-secondary btn-sm" id="discardBtn">Zavrzi</button>' +
      '</div>';
    document.querySelector('.container').insertBefore(banner, el('setupSection'));

    document.getElementById('recoverBtn').addEventListener('click', async () => {
      const session = sessions[0];
      const chunkRows = await RecordingDB.getSessionChunks(session.sessionId);
      if (chunkRows.length === 0) {
        banner.remove();
        return;
      }
      const blob = new Blob(chunkRows.map((c) => c.blob), { type: 'audio/webm' });
      banner.remove();
      // Clean up all orphaned sessions
      for (const s of sessions) {
        await RecordingDB.deleteSession(s.sessionId).catch(() => {});
      }
      await processRecording(blob);
    });

    document.getElementById('discardBtn').addEventListener('click', async () => {
      for (const s of sessions) {
        await RecordingDB.deleteSession(s.sessionId).catch(() => {});
      }
      banner.remove();
    });
  } catch (err) {
    console.warn('Recovery check failed:', err);
  }
}

function updateSttProviderUI() {
  const isWhisper = el('sttProvider').value === 'whisper';
  el('whisperModelGroup').classList.toggle('hidden', !isWhisper);
}

// --- App Tab Navigation ---

function switchAppTab(tab) {
  currentAppTab = tab;
  document.querySelectorAll('.app-tab').forEach((t) => {
    t.classList.toggle('active', t.dataset.tab === tab);
  });
  if (tab === 'record') {
    el('mainSection').classList.remove('hidden');
    el('historySection').classList.add('hidden');
    el('historyDetailSection').classList.add('hidden');
    el('resultsSection').classList.add('hidden');
  } else if (tab === 'history') {
    el('mainSection').classList.add('hidden');
    el('historySection').classList.remove('hidden');
    el('historyDetailSection').classList.add('hidden');
    el('resultsSection').classList.add('hidden');
    renderHistoryList();
  }
}

// --- API Key Management ---

function saveKeys() {
  const sKey = el('speechKeyInput').value.trim();
  const oKey = el('openaiKeyInput').value.trim();
  const soKey = el('sonioxKeyInput').value.trim();
  const gKey = el('geminiKeyInput').value.trim();

  if (!sKey && !oKey && !soKey) {
    el('speechKeyInput').focus();
    return;
  }
  if (!gKey) {
    el('geminiKeyInput').focus();
    return;
  }

  speechApiKey = sKey;
  openaiApiKey = oKey;
  sonioxApiKey = soKey;
  geminiApiKey = gKey;
  if (sKey) localStorage.setItem(SPEECH_KEY_STORE, speechApiKey);
  if (oKey) localStorage.setItem(OPENAI_KEY_STORE, openaiApiKey);
  if (soKey) localStorage.setItem(SONIOX_KEY_STORE, sonioxApiKey);
  localStorage.setItem(GEMINI_KEY_STORE, geminiApiKey);
  el('speechKeyInput').value = '';
  el('openaiKeyInput').value = '';
  el('sonioxKeyInput').value = '';
  el('geminiKeyInput').value = '';

  // Default STT provider based on available keys
  if (!sKey && oKey && !soKey) {
    el('sttProvider').value = 'whisper';
    localStorage.setItem(STT_PROVIDER_STORE, 'whisper');
    updateSttProviderUI();
  } else if (!sKey && !oKey && soKey) {
    el('sttProvider').value = 'soniox';
    localStorage.setItem(STT_PROVIDER_STORE, 'soniox');
    updateSttProviderUI();
  }

  showSection('main');
  el('appTabs').classList.remove('hidden');
  fetchAvailableModels();
}

function showSettings() {
  speechApiKey = '';
  geminiApiKey = '';
  openaiApiKey = '';
  sonioxApiKey = '';
  localStorage.removeItem(SPEECH_KEY_STORE);
  localStorage.removeItem(GEMINI_KEY_STORE);
  localStorage.removeItem(OPENAI_KEY_STORE);
  localStorage.removeItem(SONIOX_KEY_STORE);
  el('appTabs').classList.add('hidden');
  showSection('setup');
}

// --- Model Fetching ---

async function fetchAvailableModels() {
  const dropdown = el('modelSelect');
  dropdown.innerHTML = '<option value="">Nalaganje modelov...</option>';

  try {
    const res = await fetch(`${GEMINI_API}/models?key=${geminiApiKey}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    availableModels = (data.models || [])
      .filter(shouldIncludeModel)
      .map((m) => {
        const id = m.name.replace('models/', '');
        return {
          id,
          name: m.displayName,
          generationConfig: buildGenConfig(id, m.outputTokenLimit),
        };
      })
      .sort((a, b) => modelSortKey(a) - modelSortKey(b));
  } catch (err) {
    console.error('Napaka pri nalaganju modelov:', err);
    if (availableModels.length === 0) {
      availableModels = FALLBACK_MODELS.map((m) => ({
        ...m,
        generationConfig: buildGenConfig(m.id, 8192),
      }));
    }
  }

  buildModelDropdown();
}

function shouldIncludeModel(model) {
  const id = model.name.replace('models/', '');
  if (!model.supportedGenerationMethods?.includes('generateContent')) return false;
  if (!id.startsWith('gemini-')) return false;
  for (const p of EXCLUDED_PATTERNS) {
    if (id.includes(p)) return false;
  }
  return true;
}

function buildGenConfig(modelId, outputLimit) {
  const config = {
    maxOutputTokens: Math.min(outputLimit || 8192, 8192),
    temperature: 0.3,
  };
  if (modelId.includes('2.5-pro') || modelId.includes('3-pro')) {
    config.thinkingConfig = { thinkingBudget: 8000 };
  } else if (modelId.includes('2.5-flash') && !modelId.includes('lite')) {
    config.thinkingConfig = { thinkingBudget: 4000 };
  }
  return config;
}

function modelSortKey(model) {
  const id = model.id;
  if (id === 'gemini-2.5-flash') return 1;
  if (id === 'gemini-2.5-pro') return 2;
  if (id.includes('3-pro')) return 10;
  if (id.includes('3-flash')) return 11;
  if (id.includes('2.5-pro')) return 20;
  if (id.includes('2.5-flash') && !id.includes('lite')) return 21;
  if (id.includes('lite')) return 40;
  return 50;
}

// --- Model Dropdown ---

function buildModelDropdown() {
  const dropdown = el('modelSelect');
  dropdown.innerHTML = '';

  if (availableModels.length === 0) {
    dropdown.innerHTML = '<option value="">Ni modelov</option>';
    return;
  }

  availableModels.forEach((model) => {
    const opt = document.createElement('option');
    opt.value = model.id;
    opt.textContent = model.name;
    dropdown.appendChild(opt);
  });

  // Restore saved selection
  const saved = localStorage.getItem(MODEL_STORE);
  if (saved && availableModels.some((m) => m.id === saved)) {
    dropdown.value = saved;
  } else {
    dropdown.value = availableModels[0].id;
    localStorage.setItem(MODEL_STORE, dropdown.value);
  }

  // Also populate regenerate dropdown
  populateRegenerateDropdown();
}

function populateRegenerateDropdown() {
  const dropdown = el('regenerateModelSelect');
  if (!dropdown) return;
  dropdown.innerHTML = '';
  availableModels.forEach((model) => {
    const opt = document.createElement('option');
    opt.value = model.id;
    opt.textContent = model.name;
    dropdown.appendChild(opt);
  });
  // Default to currently selected model
  const current = el('modelSelect').value;
  if (current) dropdown.value = current;
}

function getSelectedModel() {
  const modelId = el('modelSelect').value;
  return availableModels.find((m) => m.id === modelId) || availableModels[0];
}

// --- Section Management ---

function showSection(name) {
  el('setupSection').classList.toggle('hidden', name !== 'setup');
  el('mainSection').classList.toggle('hidden', name !== 'main');
  el('processingSection').classList.toggle('hidden', name !== 'processing');
  el('resultsSection').classList.toggle('hidden', name !== 'results');
  el('historySection').classList.add('hidden');
  el('historyDetailSection').classList.add('hidden');

  if (name === 'processing' || name === 'results') {
    el('appTabs').classList.add('hidden');
  } else if (name === 'main') {
    el('appTabs').classList.remove('hidden');
  }
}

// --- Recording ---

async function startRecording() {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        channelCount: 1,
        sampleRate: 16000,
        echoCancellation: true,
        noiseSuppression: true,
      },
    });

    const mimeType = getSupportedMime();
    const options = { audioBitsPerSecond: 128000 };
    if (mimeType) options.mimeType = mimeType;

    recorder = new MediaRecorder(stream, options);
    chunks = [];
    recordingSessionId = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    chunkIndex = 0;

    recorder.ondataavailable = (e) => {
      if (e.data.size > 0) {
        chunks.push(e.data);
        RecordingDB.saveChunk(recordingSessionId, e.data, chunkIndex++).catch(() => {});
      }
    };

    recorder.onstop = async () => {
      stopTimer();
      stopVisualizer();
      BackgroundKeepAlive.deactivate();
      el('bgIndicator').classList.add('hidden');
      stream.getTracks().forEach((t) => t.stop());
      const blob = new Blob(chunks, { type: recorder.mimeType || 'audio/webm' });
      if (recordingSessionId) {
        RecordingDB.deleteSession(recordingSessionId).catch(() => {});
        recordingSessionId = null;
      }
      await processRecording(blob);
    };

    recorder.start(5000); // Fire ondataavailable every 5s for incremental persistence
    startTimer();
    setupVisualizer(stream);
    await BackgroundKeepAlive.activate();
    el('bgIndicator').classList.remove('hidden');

    el('recordBtn').disabled = true;
    el('stopBtn').disabled = false;
    el('recordBtn').classList.add('recording');
    setStatus('status', 'Snemanje...');
  } catch (err) {
    console.error('Mic error:', err);
    setStatus('status', 'Napaka: ni dostopa do mikrofona');
  }
}

function stopRecording() {
  if (recorder && recorder.state !== 'inactive') {
    recorder.stop(); // triggers onstop which calls BackgroundKeepAlive.deactivate()
    el('recordBtn').disabled = false;
    el('stopBtn').disabled = true;
    el('recordBtn').classList.remove('recording');
    setStatus('status', 'Obdelava...');
  }
}

// Allow stopping from lock screen media controls
window.addEventListener('backgroundStopRequested', stopRecording);

function getSupportedMime() {
  const types = [
    'audio/webm;codecs=opus',
    'audio/webm',
    'audio/ogg;codecs=opus',
    'audio/ogg',
  ];
  for (const t of types) {
    if (MediaRecorder.isTypeSupported(t)) return t;
  }
  return '';
}

// --- Visualizer ---

function setupVisualizer(stream) {
  audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  analyser = audioCtx.createAnalyser();
  audioCtx.createMediaStreamSource(stream).connect(analyser);
  analyser.fftSize = 256;

  const canvas = el('visualizerCanvas');
  const ctx = canvas.getContext('2d');
  const bufLen = analyser.frequencyBinCount;
  const data = new Uint8Array(bufLen);

  canvas.width = canvas.parentElement.clientWidth;
  canvas.height = canvas.parentElement.clientHeight;

  function draw() {
    animFrame = requestAnimationFrame(draw);
    analyser.getByteFrequencyData(data);
    ctx.fillStyle = '#f8f9fa';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    const barW = (canvas.width / bufLen) * 2;
    let x = 0;
    for (let i = 0; i < bufLen; i++) {
      const h = (data[i] / 255) * canvas.height * 0.8;
      ctx.fillStyle = `hsla(${(i / bufLen) * 60 + 210}, 70%, 55%, 0.9)`;
      ctx.fillRect(x, canvas.height - h, barW - 1, h);
      x += barW;
    }
  }
  draw();
}

function stopVisualizer() {
  if (animFrame) { cancelAnimationFrame(animFrame); animFrame = null; }
  if (audioCtx) { audioCtx.close(); audioCtx = null; }
  const ctx = el('visualizerCanvas').getContext('2d');
  ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
}

// --- Timer ---

function startTimer() {
  recStartTime = Date.now();
  timerInterval = setInterval(() => {
    const s = Math.floor((Date.now() - recStartTime) / 1000);
    el('timer').textContent =
      String(Math.floor(s / 60)).padStart(2, '0') + ':' +
      String(s % 60).padStart(2, '0');
  }, 1000);
}

function stopTimer() {
  if (timerInterval) { clearInterval(timerInterval); timerInterval = null; }
}

// --- Audio Processing Pipeline ---

async function processRecording(audioBlob) {
  showSection('processing');
  setStepState('stepTranscribe', 'active');
  setStepState('stepSummarize', 'pending');

  const durationSec = Math.floor((Date.now() - recStartTime) / 1000);
  const durationStr = String(Math.floor(durationSec / 60)).padStart(2, '0') + ':' +
    String(durationSec % 60).padStart(2, '0');

  try {
    // Step 1: Transcribe
    setProgress(10, 'Pretvarjanje zvoka...');
    const sttProvider = el('sttProvider').value;
    let transcript;

    if (sttProvider === 'whisper') {
      setProgress(20, 'Pošiljanje na OpenAI Whisper API...');
      transcript = await transcribeWithWhisper(audioBlob);
    } else if (sttProvider === 'soniox') {
      setProgress(20, 'Pošiljanje na Soniox API...');
      transcript = await transcribeWithSoniox(audioBlob);
    } else {
      const base64 = await blobToBase64(audioBlob);
      const encoding = audioBlob.type.includes('ogg') ? 'OGG_OPUS' : 'WEBM_OPUS';

      setProgress(20, 'Pošiljanje na Google Speech API...');
      let sttResult;
      if (durationSec < 55) {
        sttResult = await recognizeSync(base64, encoding);
      } else {
        sttResult = await recognizeLong(audioBlob);
      }
      transcript = extractTranscript(sttResult);
    }
    if (!transcript) {
      setProgress(0, 'V posnetku ni bil zaznan govor.');
      setTimeout(() => newSession(), 3000);
      return;
    }

    setStepState('stepTranscribe', 'done');
    setStepState('stepSummarize', 'active');
    setProgress(60, 'Pošiljanje na Gemini AI...');

    // Step 2: Summarize with selected model
    const model = getSelectedModel();
    let summaryData = null;

    try {
      const text = await callGemini(model, transcript);
      const summaries = parseGeminiResponse(text);
      summaryData = { model: model.id, modelName: model.name, summaries };
      modelResults = { status: 'ok', summaries };
    } catch (err) {
      console.error(`${model.name} error:`, err);
      modelResults = { status: 'error', message: err.message };
    }

    // Save to history (transcript always saved, summary only if successful)
    saveToHistory({
      transcript,
      language: el('language').value,
      duration: durationStr,
      sttProvider: sttProvider === 'whisper' ? 'Whisper' : sttProvider === 'soniox' ? 'Soniox' : 'Google',
      summary: summaryData,
    });

    // Show results
    el('rawTranscript').textContent = transcript;
    renderSummaryContent(modelResults);
    showSection('results');

  } catch (err) {
    console.error('Pipeline error:', err);
    setProgress(0, 'Napaka: ' + err.message);
    setTimeout(() => newSession(), 4000);
  }
}

function extractTranscript(response) {
  const results = response.results || [];
  if (!results.length) return '';
  return results
    .map((r) => r.alternatives?.[0]?.transcript || '')
    .join(' ')
    .trim();
}

// --- Google Speech-to-Text ---

async function recognizeSync(base64, encoding) {
  const body = {
    config: {
      encoding,
      sampleRateHertz: 48000,
      languageCode: el('language').value,
      enableAutomaticPunctuation: true,
      model: 'default',
    },
    audio: { content: base64 },
  };

  const res = await fetch(`${SPEECH_API}/speech:recognize?key=${speechApiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const e = await res.json();
    throw new Error(e.error?.message || `Speech API napaka ${res.status}`);
  }
  return res.json();
}

async function recognizeLong(audioBlob) {
  // Decode audio to raw PCM using Web Audio API at 16 kHz
  setProgress(15, 'Dekodiranje zvoka...');
  const decodeCtx = new (window.AudioContext || window.webkitAudioContext)({
    sampleRate: 16000,
  });
  const arrayBuffer = await audioBlob.arrayBuffer();
  const audioBuffer = await decodeCtx.decodeAudioData(arrayBuffer);
  decodeCtx.close();

  // Get mono channel data
  const channelData = audioBuffer.getChannelData(0);
  const sampleRate = audioBuffer.sampleRate;

  // Split into ~50 second chunks (under 60s API limit)
  const chunkSeconds = 50;
  const samplesPerChunk = chunkSeconds * sampleRate;
  const totalChunks = Math.ceil(channelData.length / samplesPerChunk);

  const transcripts = [];
  for (let i = 0; i < totalChunks; i++) {
    const start = i * samplesPerChunk;
    const end = Math.min(start + samplesPerChunk, channelData.length);
    const chunk = channelData.slice(start, end);

    // Convert Float32 samples to LINEAR16 (Int16)
    const pcm16 = float32ToLinear16(chunk);
    const base64Chunk = arrayBufferToBase64(pcm16.buffer);

    const pct = 20 + Math.round(((i + 1) / totalChunks) * 35);
    setProgress(pct, `Prepisovanje dela ${i + 1}/${totalChunks}...`);

    const body = {
      config: {
        encoding: 'LINEAR16',
        sampleRateHertz: sampleRate,
        languageCode: el('language').value,
        enableAutomaticPunctuation: true,
        model: 'default',
      },
      audio: { content: base64Chunk },
    };

    const res = await fetch(
      `${SPEECH_API}/speech:recognize?key=${speechApiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      }
    );

    if (!res.ok) {
      const e = await res.json();
      throw new Error(e.error?.message || `Speech API napaka ${res.status}`);
    }

    const result = await res.json();
    const text = extractTranscript(result);
    if (text) transcripts.push(text);
  }

  // Return in standard response format
  return {
    results: [
      {
        alternatives: [{ transcript: transcripts.join(' ') }],
      },
    ],
  };
}

function float32ToLinear16(float32Array) {
  const int16Array = new Int16Array(float32Array.length);
  for (let i = 0; i < float32Array.length; i++) {
    const s = Math.max(-1, Math.min(1, float32Array[i]));
    int16Array[i] = s < 0 ? s * 0x8000 : s * 0x7FFF;
  }
  return int16Array;
}

function arrayBufferToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  const CHUNK_SIZE = 0x8000;
  let binary = '';
  for (let i = 0; i < bytes.length; i += CHUNK_SIZE) {
    binary += String.fromCharCode.apply(
      null,
      bytes.subarray(i, i + CHUNK_SIZE)
    );
  }
  return btoa(binary);
}

// --- OpenAI Whisper STT ---

function getWhisperLanguage(langCode) {
  return langCode.split('-')[0]; // sl-SI → sl, en-US → en
}

async function transcribeWithWhisper(audioBlob) {
  if (!openaiApiKey) {
    throw new Error('OpenAI API ključ ni nastavljen. Nastavite ga v nastavitvah.');
  }

  const fileSizeMB = audioBlob.size / (1024 * 1024);
  const whisperModel = el('whisperModel').value || 'whisper-1';
  const language = getWhisperLanguage(el('language').value);

  if (fileSizeMB <= WHISPER_MAX_CHUNK_MB) {
    return await whisperTranscribeSingle(audioBlob, whisperModel, language);
  } else {
    return await whisperTranscribeChunked(audioBlob, whisperModel, language);
  }
}

async function whisperTranscribeSingle(audioBlob, model, language) {
  const ext = audioBlob.type.includes('wav') ? 'wav'
    : audioBlob.type.includes('ogg') ? 'ogg' : 'webm';
  const formData = new FormData();
  formData.append('file', audioBlob, `audio.${ext}`);
  formData.append('model', model);
  formData.append('language', language);

  const res = await fetch(OPENAI_STT_API, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${openaiApiKey}` },
    body: formData,
  });

  if (!res.ok) {
    const e = await res.json();
    throw new Error(e.error?.message || `Whisper API napaka ${res.status}`);
  }

  const data = await res.json();
  return (data.text || '').trim();
}

async function whisperTranscribeChunked(audioBlob, model, language) {
  setProgress(15, 'Dekodiranje zvoka za razdelitev...');
  const decodeCtx = new (window.AudioContext || window.webkitAudioContext)({
    sampleRate: 16000,
  });
  const arrayBuffer = await audioBlob.arrayBuffer();
  const audioBuffer = await decodeCtx.decodeAudioData(arrayBuffer);
  decodeCtx.close();

  const chunks = splitAudioForWhisper(audioBuffer);
  const transcripts = [];

  for (let i = 0; i < chunks.length; i++) {
    const pct = 20 + Math.round(((i + 1) / chunks.length) * 35);
    setProgress(pct, `Prepisovanje dela ${i + 1}/${chunks.length}...`);

    const wavBlob = audioBufferToWavBlob(chunks[i]);
    const text = await whisperTranscribeSingle(wavBlob, model, language);
    if (text) transcripts.push(text);
  }

  return transcripts.join(' ');
}

function splitAudioForWhisper(audioBuffer) {
  const sampleRate = audioBuffer.sampleRate;
  const channelData = audioBuffer.getChannelData(0);
  // 10 minutes per chunk (~19MB in 16-bit mono WAV at 16kHz)
  const chunkSeconds = 600;
  const overlapSeconds = 10;
  const samplesPerChunk = chunkSeconds * sampleRate;
  const overlapSamples = overlapSeconds * sampleRate;
  const totalChunks = Math.ceil(channelData.length / samplesPerChunk);
  const chunks = [];

  for (let i = 0; i < totalChunks; i++) {
    const start = i * samplesPerChunk;
    const end = Math.min(start + samplesPerChunk + overlapSamples, channelData.length);
    chunks.push(channelData.slice(start, end));
  }

  return chunks;
}

function audioBufferToWavBlob(float32Data) {
  const sampleRate = 16000;
  const numChannels = 1;
  const bytesPerSample = 2;
  const dataLength = float32Data.length * numChannels * bytesPerSample;
  const buffer = new ArrayBuffer(44 + dataLength);
  const view = new DataView(buffer);

  // WAV header
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

  // Audio data
  let offset = 44;
  for (let i = 0; i < float32Data.length; i++) {
    const s = Math.max(-1, Math.min(1, float32Data[i]));
    view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7FFF, true);
    offset += 2;
  }

  return new Blob([buffer], { type: 'audio/wav' });
}

// --- Soniox STT ---

function getSonioxLanguage(langCode) {
  return langCode.split('-')[0]; // sl-SI → sl, en-US → en
}

async function sonioxFetch(path, options = {}) {
  const res = await fetch(`${SONIOX_API}${path}`, {
    ...options,
    headers: {
      'Authorization': `Bearer ${sonioxApiKey}`,
      ...options.headers,
    },
  });
  if (!res.ok) {
    const e = await res.json().catch(() => ({}));
    throw new Error(e.message || `Soniox napaka ${res.status}`);
  }
  if (res.status === 204) return null;
  return res.json();
}

async function transcribeWithSoniox(audioBlob) {
  if (!sonioxApiKey) {
    throw new Error('Soniox API ključ ni nastavljen. Nastavite ga v nastavitvah.');
  }

  const language = getSonioxLanguage(el('language').value);

  // Convert to WAV for universal format compatibility
  // (iOS Safari records mp4/aac which Soniox rejects when mislabelled)
  setProgress(15, 'Pretvarjanje zvoka...');
  const decodeCtx = new (window.AudioContext || window.webkitAudioContext)({
    sampleRate: 16000,
  });
  const rawBuffer = await audioBlob.arrayBuffer();
  const audioBuffer = await decodeCtx.decodeAudioData(rawBuffer);
  decodeCtx.close();
  const wavBlob = audioBufferToWavBlob(audioBuffer.getChannelData(0));

  // Step 1: Upload audio file
  setProgress(20, 'Nalaganje zvoka na Soniox...');
  const uploadForm = new FormData();
  uploadForm.append('file', wavBlob, 'audio.wav');
  const fileData = await sonioxFetch('/files', {
    method: 'POST',
    body: uploadForm,
  });
  const fileId = fileData.id;

  try {
    // Step 2: Create async transcription
    setProgress(25, 'Ustvarjanje transkripcije...');
    const job = await sonioxFetch('/transcriptions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'stt-async-preview',
        file_id: fileId,
        language_hints: [language],
      }),
    });

    // Step 3: Poll until completed
    let status = job.status;
    while (status === 'queued' || status === 'processing') {
      await sleep(1500);
      setProgress(35, 'Čakanje na transkripcijo...');
      const poll = await sonioxFetch(`/transcriptions/${job.id}`);
      status = poll.status;
      if (status === 'error') {
        throw new Error(poll.error_message || 'Soniox transkripcija ni uspela');
      }
    }

    // Step 4: Get transcript text
    setProgress(50, 'Pridobivanje prepisa...');
    const result = await sonioxFetch(`/transcriptions/${job.id}/transcript`);

    // Cleanup (fire-and-forget)
    sonioxFetch(`/transcriptions/${job.id}`, { method: 'DELETE' }).catch(() => {});
    sonioxFetch(`/files/${fileId}`, { method: 'DELETE' }).catch(() => {});

    return (result.text || '').trim();
  } catch (err) {
    // Cleanup file on error (fire-and-forget)
    sonioxFetch(`/files/${fileId}`, { method: 'DELETE' }).catch(() => {});
    throw err;
  }
}

// --- Gemini Summarization ---

async function callGemini(model, transcript) {
  const prompt = SUMMARY_PROMPT + transcript + '\n---';

  const body = {
    contents: [{ parts: [{ text: prompt }] }],
    generationConfig: { ...model.generationConfig },
  };

  const res = await fetch(
    `${GEMINI_API}/models/${model.id}:generateContent?key=${geminiApiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }
  );

  if (!res.ok) {
    const e = await res.json();
    throw new Error(e.error?.message || `Gemini napaka ${res.status}`);
  }

  const data = await res.json();
  // Extract text from response, skip thought parts
  const parts = data.candidates?.[0]?.content?.parts || [];
  return parts
    .filter((p) => p.text && !p.thought)
    .map((p) => p.text)
    .join('');
}

function parseGeminiResponse(text) {
  // Try to parse as JSON directly
  let json = tryParseJSON(text);
  if (json?.summaries) return json.summaries;

  // Try to extract JSON from markdown code block
  const codeBlock = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (codeBlock) {
    json = tryParseJSON(codeBlock[1].trim());
    if (json?.summaries) return json.summaries;
  }

  // Try to find JSON object in text
  const jsonMatch = text.match(/\{[\s\S]*"summaries"[\s\S]*\}/);
  if (jsonMatch) {
    json = tryParseJSON(jsonMatch[0]);
    if (json?.summaries) return json.summaries;
  }

  // Fallback: treat entire response as single summary
  return [{ title: 'Povzetek', content: text }];
}

function tryParseJSON(str) {
  try { return JSON.parse(str); } catch { return null; }
}

// --- Render Summary Content ---

function renderSummaryContent(result) {
  const container = el('modelContent');

  if (!result) {
    container.innerHTML = '<div class="model-loading"><div class="spinner"></div><p>Generiranje povzetka...</p></div>';
    return;
  }

  if (result.status === 'error') {
    container.innerHTML = `<div class="model-error"><p>Napaka pri povzemanju: ${escapeHtml(result.message)}</p><p class="hint">Prepis je bil shranjen v zgodovino.</p></div>`;
    return;
  }

  let html = '';
  result.summaries.forEach((summary, i) => {
    const contentHtml = renderMarkdown(summary.content);
    const copyId = `copy-result-${i}`;
    html += `
      <div class="summary-card">
        <div class="summary-header">
          <h3>${escapeHtml(summary.title)}</h3>
          <button class="btn btn-secondary btn-sm" id="${copyId}"
            onclick="copyResultSummary(${i}, '${copyId}')">Kopiraj</button>
        </div>
        <div class="summary-content">${contentHtml}</div>
      </div>
    `;
  });

  container.innerHTML = html;
}

window.copyResultSummary = function (index, btnId) {
  if (!modelResults?.summaries?.[index]) return;
  const s = modelResults.summaries[index];
  const text = s.title + '\n\n' + stripMarkdown(s.content);
  copyToClipboard(text, document.getElementById(btnId));
};

// --- History Management ---

function getHistory() {
  const raw = localStorage.getItem(HISTORY_STORE);
  if (!raw) return [];
  return tryParseJSON(raw) || [];
}

function saveHistory(history) {
  localStorage.setItem(HISTORY_STORE, JSON.stringify(history));
}

function saveToHistory(entry) {
  const history = getHistory();
  const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
  history.unshift({
    id,
    date: new Date().toISOString(),
    ...entry,
  });
  // Keep max 50 entries
  if (history.length > 50) history.length = 50;
  saveHistory(history);
}

function updateHistoryEntry(id, updates) {
  const history = getHistory();
  const idx = history.findIndex((h) => h.id === id);
  if (idx === -1) return;
  Object.assign(history[idx], updates);
  saveHistory(history);
}

function deleteHistoryEntry(id) {
  const history = getHistory().filter((h) => h.id !== id);
  saveHistory(history);
}

// --- History UI ---

function renderHistoryList() {
  const history = getHistory();
  const list = el('historyList');
  const empty = el('historyEmpty');

  if (history.length === 0) {
    list.innerHTML = '';
    empty.classList.remove('hidden');
    return;
  }

  empty.classList.add('hidden');
  list.innerHTML = history.map((entry) => {
    const date = new Date(entry.date);
    const dateStr = date.toLocaleDateString('sl-SI', {
      day: 'numeric', month: 'short', year: 'numeric',
    });
    const timeStr = date.toLocaleTimeString('sl-SI', {
      hour: '2-digit', minute: '2-digit',
    });
    const hasSummary = !!entry.summary;
    const title = hasSummary && entry.summary.summaries?.[0]?.title
      ? entry.summary.summaries[0].title
      : 'Brez povzetka';
    const preview = entry.transcript.slice(0, 100) + (entry.transcript.length > 100 ? '...' : '');

    return `
      <div class="card history-card" onclick="openHistoryDetail('${entry.id}')">
        <div class="history-card-header">
          <span class="history-card-title">${escapeHtml(title)}</span>
          <span class="history-card-badge ${hasSummary ? 'badge-ok' : 'badge-warn'}">
            ${hasSummary ? 'Povzetek' : 'Samo prepis'}
          </span>
        </div>
        <div class="history-card-meta">
          ${dateStr} ob ${timeStr} &middot; ${entry.duration || '??:??'} &middot; ${entry.language || 'sl-SI'}
          ${hasSummary ? ' &middot; ' + escapeHtml(entry.summary.modelName || entry.summary.model) : ''}
        </div>
        <div class="history-card-preview">${escapeHtml(preview)}</div>
      </div>
    `;
  }).join('');
}

window.openHistoryDetail = function (id) {
  const history = getHistory();
  const entry = history.find((h) => h.id === id);
  if (!entry) return;

  currentHistoryId = id;

  const date = new Date(entry.date);
  const dateStr = date.toLocaleDateString('sl-SI', {
    day: 'numeric', month: 'long', year: 'numeric',
  });
  const timeStr = date.toLocaleTimeString('sl-SI', {
    hour: '2-digit', minute: '2-digit',
  });

  const title = entry.summary?.summaries?.[0]?.title || 'Posnetek';
  el('historyDetailTitle').textContent = title;
  el('historyDetailMeta').textContent =
    `${dateStr} ob ${timeStr} · Trajanje: ${entry.duration || '??:??'} · Jezik: ${entry.language || 'sl-SI'}`;

  el('historyTranscript').textContent = entry.transcript;

  // Render summary or "no summary" message
  renderHistorySummary(entry);

  // Set regenerate dropdown to the model used (if available)
  if (entry.summary?.model) {
    const regen = el('regenerateModelSelect');
    if (regen.querySelector(`option[value="${entry.summary.model}"]`)) {
      regen.value = entry.summary.model;
    }
  }

  el('historySection').classList.add('hidden');
  el('historyDetailSection').classList.remove('hidden');
};

function renderHistorySummary(entry) {
  const container = el('historyDetailSummary');

  if (!entry.summary) {
    container.innerHTML = `
      <div class="no-summary-notice">
        <p>Povzetek ni na voljo. Uporabite gumb spodaj za generiranje.</p>
      </div>
    `;
    return;
  }

  let html = `<div class="history-summary-model">Model: ${escapeHtml(entry.summary.modelName || entry.summary.model)}</div>`;
  entry.summary.summaries.forEach((summary, i) => {
    const contentHtml = renderMarkdown(summary.content);
    const copyId = `copy-hist-${entry.id}-${i}`;
    html += `
      <div class="summary-card">
        <div class="summary-header">
          <h3>${escapeHtml(summary.title)}</h3>
          <button class="btn btn-secondary btn-sm" id="${copyId}"
            onclick="copyHistorySummary('${entry.id}', ${i}, '${copyId}')">Kopiraj</button>
        </div>
        <div class="summary-content">${contentHtml}</div>
      </div>
    `;
  });

  container.innerHTML = html;
}

window.copyHistorySummary = function (entryId, index, btnId) {
  const history = getHistory();
  const entry = history.find((h) => h.id === entryId);
  if (!entry?.summary?.summaries?.[index]) return;
  const s = entry.summary.summaries[index];
  const text = s.title + '\n\n' + stripMarkdown(s.content);
  copyToClipboard(text, document.getElementById(btnId));
};

function deleteCurrentHistoryEntry() {
  if (!currentHistoryId) return;
  if (!confirm('Izbrisati ta posnetek?')) return;
  deleteHistoryEntry(currentHistoryId);
  currentHistoryId = null;
  switchAppTab('history');
}

async function regenerateSummary() {
  if (!currentHistoryId) return;
  const history = getHistory();
  const entry = history.find((h) => h.id === currentHistoryId);
  if (!entry) return;

  const modelId = el('regenerateModelSelect').value;
  const model = availableModels.find((m) => m.id === modelId);
  if (!model) return;

  const btn = el('regenerateSummaryBtn');
  const origText = btn.textContent;
  btn.disabled = true;
  btn.textContent = 'Generiranje...';

  const summaryContainer = el('historyDetailSummary');
  summaryContainer.innerHTML = '<div class="model-loading"><div class="spinner"></div><p>Generiranje povzetka...</p></div>';

  try {
    const text = await callGemini(model, entry.transcript);
    const summaries = parseGeminiResponse(text);
    const summaryData = { model: model.id, modelName: model.name, summaries };

    updateHistoryEntry(currentHistoryId, { summary: summaryData });

    // Re-render
    const updatedEntry = { ...entry, summary: summaryData };
    renderHistorySummary(updatedEntry);
  } catch (err) {
    console.error('Regenerate error:', err);
    summaryContainer.innerHTML = `<div class="model-error"><p>Napaka: ${escapeHtml(err.message)}</p></div>`;
  } finally {
    btn.disabled = false;
    btn.textContent = origText;
  }
}

// --- Copy ---

function stripMarkdown(text) {
  if (!text) return '';
  text = text.replace(/^###\s+/gm, '');
  text = text.replace(/^##\s+/gm, '');
  text = text.replace(/^#\s+/gm, '');
  text = text.replace(/\*\*(.+?)\*\*/g, '$1');
  text = text.replace(/\*(.+?)\*/g, '$1');
  return text;
}

function copyToClipboard(text, btn) {
  navigator.clipboard.writeText(text).then(() => {
    if (btn) {
      const orig = btn.textContent;
      btn.textContent = 'Kopirano!';
      setTimeout(() => (btn.textContent = orig), 2000);
    }
  });
}

// --- Markdown Renderer (minimal) ---

function renderMarkdown(md) {
  if (!md) return '';
  let html = escapeHtml(md);

  // Headers
  html = html.replace(/^### (.+)$/gm, '<h4>$1</h4>');
  html = html.replace(/^## (.+)$/gm, '<h3 class="md-h3">$1</h3>');
  html = html.replace(/^# (.+)$/gm, '<h2>$1</h2>');

  // Bold
  html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

  // Italic
  html = html.replace(/\*(.+?)\*/g, '<em>$1</em>');

  // Bullet points - collect consecutive lines starting with -
  html = html.replace(/^- (.+)$/gm, '<li>$1</li>');
  html = html.replace(/((?:<li>.*<\/li>\n?)+)/g, '<ul>$1</ul>');

  // Numbered lists
  html = html.replace(/^\d+\. (.+)$/gm, '<li>$1</li>');

  // Line breaks
  html = html.replace(/\n\n/g, '</p><p>');
  html = html.replace(/\n/g, '<br>');

  return '<p>' + html + '</p>';
}

// --- New Session ---

function newSession() {
  el('timer').textContent = '00:00';
  setStatus('status', 'Pripravljeno');
  el('recordBtn').disabled = false;
  el('stopBtn').disabled = true;
  el('recordBtn').classList.remove('recording');
  modelResults = {};
  showSection('main');
}

// --- UI Helpers ---

function el(id) {
  return document.getElementById(id);
}

function setStatus(id, msg) {
  const e = document.getElementById(id);
  if (e) e.textContent = msg;
}

function setProgress(pct, msg) {
  el('progressFill').style.width = pct + '%';
  el('processingStatus').textContent = msg;
}

function setStepState(stepId, state) {
  const step = el(stepId);
  if (!step) return;
  step.className = 'step ' + state;
}

function escapeHtml(str) {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

// --- Utilities ---

function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => resolve(reader.result.split(',')[1]);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}
