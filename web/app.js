import { clean, polishPrompt, whisperPrompt } from './cleaner.js';

const $ = (id) => document.getElementById(id);
const store = {
  get(k, d) { try { const v = localStorage.getItem('sw.' + k); return v === null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem('sw.' + k, JSON.stringify(v)); } catch {} },
};

const S = {
  lang: store.get('lang', 'auto'),
  engine: store.get('engine', 'local'),
  model: store.get('model', 'onnx-community/whisper-base'),
  polish: store.get('polish', 'rules'),
  style: store.get('style', 'natural'),
  fillers: store.get('fillers', true),
  commands: store.get('commands', true),
  autocopy: store.get('autocopy', true),
  key: store.get('key', ''),
  vocab: store.get('vocab', ''),
  reps: store.get('reps', 'chat gpt = ChatGPT\nsay what = Say What'),
  snips: store.get('snips', ''),
};
let history = store.get('history', []);

const pairs = (txt) => txt.split('\n').map((l) => l.split('=')).filter((p) => p.length >= 2 && p[0].trim())
  .map(([a, ...b]) => ({ a: a.trim(), b: b.join('=').trim() }));
const cleanerOpts = () => ({
  removeFillers: S.fillers, voiceCommands: S.commands, style: S.style,
  replacements: pairs(S.reps).map((p) => ({ from: p.a, to: p.b })),
  snippets: pairs(S.snips).map((p) => ({ trigger: p.a, text: p.b })),
});
const vocabList = () => S.vocab.split(',').map((x) => x.trim()).filter(Boolean);

// ---------- Worker (on-device Whisper) ----------
const worker = new Worker('./worker.js', { type: 'module' });
let modelReady = false;
const pending = new Map();
const files = {};
worker.onmessage = ({ data }) => {
  if (data.type === 'progress') {
    files[data.file] = data;
    const tot = Object.values(files).reduce((a, f) => a + (f.total || 0), 0);
    const got = Object.values(files).reduce((a, f) => a + (f.loaded || 0), 0);
    showLoad(tot ? got / tot : 0, `Downloading voice model… ${tot ? Math.round(tot / 1e6) + ' MB' : ''}`);
  } else if (data.type === 'ready') {
    modelReady = true;
    $('load').hidden = true;
  } else if (data.type === 'result' || data.type === 'error') {
    const p = pending.get(data.id); pending.delete(data.id);
    if (p) data.type === 'result' ? p.resolve(data.text) : p.reject(new Error(data.message));
    if (data.type === 'error') $('load').hidden = true;
  }
};
function showLoad(frac, text) {
  $('load').hidden = false;
  $('loadText').textContent = text;
  $('loadFill').style.width = Math.round(frac * 100) + '%';
}
function preload() {
  if (S.engine !== 'local') return;
  modelReady = false;
  showLoad(0, 'Preparing voice model…');
  worker.postMessage({ type: 'load', model: S.model });
}
function localTranscribe(audio) {
  const id = Math.random().toString(36).slice(2);
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    worker.postMessage({ type: 'transcribe', id, audio, model: S.model, language: S.lang }, [audio.buffer]);
  });
}

// ---------- Groq ----------
async function groqTranscribe(blob) {
  if (!S.key) throw new Error('Add your Groq API key in Settings, or switch to on-device Whisper.');
  const fd = new FormData();
  const ext = (blob.type.includes('mp4') ? 'm4a' : blob.type.includes('ogg') ? 'ogg' : 'webm');
  fd.append('file', blob, 'audio.' + ext);
  fd.append('model', 'whisper-large-v3-turbo');
  fd.append('temperature', '0');
  fd.append('response_format', 'verbose_json');
  fd.append('prompt', whisperPrompt(S.lang, vocabList()));
  if (S.lang !== 'auto') fd.append('language', S.lang);
  const r = await fetch('https://api.groq.com/openai/v1/audio/transcriptions', { method: 'POST', headers: { Authorization: 'Bearer ' + S.key }, body: fd });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(r.status === 401 ? 'Groq rejected the API key.' : 'Groq: ' + (j.error?.message || r.status));
  return { text: j.text || '', lang: S.lang !== 'auto' ? S.lang : ((j.language || '').toLowerCase().startsWith('p') ? 'pt' : 'en') };
}
async function groqPolish(text, lang) {
  if (!S.key || text.split(/\s+/).length < 4) return null;
  const r = await fetch('https://api.groq.com/openai/v1/chat/completions', {
    method: 'POST', headers: { Authorization: 'Bearer ' + S.key, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'llama-3.3-70b-versatile', temperature: 0.1, max_tokens: 2048,
      messages: [{ role: 'system', content: polishPrompt(lang, S.style) }, { role: 'user', content: text }] }),
  });
  if (!r.ok) return null;
  const out = ((await r.json()).choices?.[0]?.message?.content || '').trim().replace(/^["“«](.*)["”»]$/s, '$1');
  const ratio = out.length / Math.max(1, text.length);
  return out && ratio > 0.4 && ratio < 1.6 ? out : null;
}

// ---------- Recording ----------
let stream, rec, chunks = [], ctx, analyser, raf, phase = 'idle';
const mic = $('mic');

function setPhase(p) {
  phase = p;
  mic.classList.toggle('rec', p === 'recording');
  mic.classList.toggle('busy', p === 'busy');
  mic.setAttribute('aria-label', p === 'recording' ? 'Stop dictation' : 'Start dictation');
  $('status').textContent = { idle: 'Tap and talk — English or Português', recording: 'Listening… tap to finish', busy: 'Writing it out…' }[p];
}

async function start() {
  $('err').hidden = true;
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true } });
  } catch (e) {
    return showErr('Microphone blocked — allow it in your browser settings.');
  }
  const type = ['audio/webm;codecs=opus', 'audio/mp4', 'audio/webm', 'audio/ogg'].find((t) => window.MediaRecorder?.isTypeSupported?.(t)) || '';
  rec = new MediaRecorder(stream, type ? { mimeType: type } : undefined);
  chunks = [];
  rec.ondataavailable = (e) => e.data.size && chunks.push(e.data);
  rec.start(250);
  ctx = new (window.AudioContext || window.webkitAudioContext)();
  analyser = ctx.createAnalyser(); analyser.fftSize = 512;
  ctx.createMediaStreamSource(stream).connect(analyser);
  const buf = new Float32Array(analyser.fftSize);
  const tick = () => {
    analyser.getFloatTimeDomainData(buf);
    let s = 0; for (const x of buf) s += x * x;
    const lvl = Math.min(1, Math.sqrt(s / buf.length) * 10);
    mic.style.setProperty('--lvl', (1 + lvl * 0.35).toFixed(3));
    raf = requestAnimationFrame(tick);
  };
  tick();
  setPhase('recording');
  if (navigator.vibrate) navigator.vibrate(15);
}

async function stop() {
  if (phase !== 'recording') return;
  setPhase('busy');
  cancelAnimationFrame(raf); mic.style.setProperty('--lvl', 1);
  await new Promise((res) => { rec.onstop = res; rec.stop(); });
  stream.getTracks().forEach((t) => t.stop());
  const blob = new Blob(chunks, { type: rec.mimeType || 'audio/webm' });
  try {
    const t0 = performance.now();
    let raw, lang = S.lang;
    if (S.engine === 'groq') {
      ({ text: raw, lang } = await groqTranscribe(blob));
    } else {
      const audio = await to16k(blob);
      if (audio.length < 16000 * 0.35 || rms(audio) < 0.004) { setPhase('idle'); return; }
      raw = await localTranscribe(audio);
      if (lang === 'auto') lang = /[ãõçáéíóúâêô]|\b(não|que|está|para|uma|isso|eu)\b/i.test(raw) ? 'pt' : 'en';
    }
    let text = clean(raw, cleanerOpts());
    if (text && S.polish === 'groq') {
      const p = await groqPolish(text, lang).catch(() => null);
      if (p) text = clean(p, cleanerOpts());
    }
    setPhase('idle');
    if (!text) { $('status').textContent = "Didn't catch that — try again"; return; }
    show(text);
    history.unshift({ text, lang, at: Date.now(), secs: (performance.now() - t0) / 1000 });
    history = history.slice(0, 200); store.set('history', history); renderHist();
    if (S.autocopy) copy(true);
  } catch (e) {
    setPhase('idle');
    showErr(e.message || String(e));
  } finally {
    ctx?.close();
  }
}

async function to16k(blob) {
  const ab = await blob.arrayBuffer();
  const ac = new (window.AudioContext || window.webkitAudioContext)();
  const decoded = await ac.decodeAudioData(ab);
  ac.close();
  const len = Math.ceil(decoded.duration * 16000);
  const off = new OfflineAudioContext(1, len, 16000);
  const src = off.createBufferSource(); src.buffer = decoded; src.connect(off.destination); src.start();
  const out = await off.startRendering();
  return out.getChannelData(0).slice();
}
const rms = (a) => { let s = 0; for (const x of a) s += x * x; return Math.sqrt(s / a.length); };

// ---------- UI ----------
function show(text) { $('result').hidden = false; $('text').value = text; }
function showErr(m) { $('err').textContent = m; $('err').hidden = false; }
async function copy(silent) {
  try { await navigator.clipboard.writeText($('text').value); $('copy').textContent = 'Copied ✓'; }
  catch { if (!silent) { $('text').select(); document.execCommand?.('copy'); } }
  setTimeout(() => ($('copy').textContent = 'Copy'), 1500);
}
function renderHist() {
  $('histEmpty').hidden = history.length > 0;
  $('hist').innerHTML = history.slice(0, 50).map((h, i) =>
    `<li data-i="${i}"><div>${h.text.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c])).replace(/\n/g, '<br>')}</div><small>${(h.lang || '').toUpperCase()} · ${new Date(h.at).toLocaleString()} · tap to reuse</small></li>`).join('');
}

mic.addEventListener('click', () => (phase === 'idle' ? start() : phase === 'recording' ? stop() : null));
$('copy').onclick = () => copy(false);
$('share').onclick = () => navigator.share ? navigator.share({ text: $('text').value }).catch(() => {}) : copy(false);
$('clear').onclick = () => { $('text').value = ''; $('result').hidden = true; };
$('hist').onclick = (e) => { const li = e.target.closest('li'); if (li) { show(history[+li.dataset.i].text); copy(true); scrollTo({ top: 0, behavior: 'smooth' }); } };

// Hold Space to talk (desktop)
let spaceDown = false;
addEventListener('keydown', (e) => {
  if (e.code !== 'Space' || e.repeat || ['TEXTAREA', 'INPUT', 'SELECT'].includes(document.activeElement?.tagName) || $('settings').open) return;
  e.preventDefault(); spaceDown = true; if (phase === 'idle') start();
});
addEventListener('keyup', (e) => { if (e.code === 'Space' && spaceDown) { spaceDown = false; e.preventDefault(); stop(); } });

// Language
const segBtns = document.querySelectorAll('.seg button');
const paintLang = () => segBtns.forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.lang === S.lang)));
segBtns.forEach((b) => (b.onclick = () => { S.lang = b.dataset.lang; store.set('lang', S.lang); paintLang(); }));
paintLang();

// Settings
const bind = (id, key, prop = 'value', after) => {
  const el = $(id); el[prop] = S[key];
  el.addEventListener('change', () => { S[key] = el[prop]; store.set(key, S[key]); after?.(); });
};
const syncModelField = () => ($('modelField').hidden = S.engine !== 'local');
bind('engine', 'engine', 'value', () => { syncModelField(); preload(); });
bind('model', 'model', 'value', preload);
bind('polish', 'polish'); bind('style', 'style');
bind('fillers', 'fillers', 'checked'); bind('commands', 'commands', 'checked'); bind('autocopy', 'autocopy', 'checked');
bind('key', 'key'); bind('vocab', 'vocab'); bind('reps', 'reps'); bind('snips', 'snips');
syncModelField();
$('openSettings').onclick = () => $('settings').showModal();
$('closeSettings').onclick = () => $('settings').close();
$('settings').addEventListener('click', (e) => { if (e.target === $('settings')) $('settings').close(); });
$('clearHist').onclick = () => { history = []; store.set('history', history); renderHist(); };

const standalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone;
$('installTip').hidden = !!standalone;
renderHist();
preload();
if ('serviceWorker' in navigator) navigator.serviceWorker.register('./sw.js').catch(() => {});
