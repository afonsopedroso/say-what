// Say What — on-device Whisper in a Web Worker (transformers.js, WebGPU when available, else WASM).
import { pipeline, env } from 'https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.3.1';

env.allowLocalModels = false;
let asr = null;
let loadedId = null;

async function hasWebGPU() {
  try { return !!(navigator.gpu && (await navigator.gpu.requestAdapter())); } catch { return false; }
}

async function load(model) {
  if (asr && loadedId === model) return;
  asr = null;
  const gpu = await hasWebGPU();
  const opts = {
    device: gpu ? 'webgpu' : 'wasm',
    dtype: gpu ? { encoder_model: 'fp32', decoder_model_merged: 'q4' } : 'q8',
    progress_callback: (p) => {
      if (p.status === 'progress') self.postMessage({ type: 'progress', file: p.file, progress: p.progress, loaded: p.loaded, total: p.total });
    },
  };
  try {
    asr = await pipeline('automatic-speech-recognition', model, opts);
  } catch (e) {
    if (!gpu) throw e;
    opts.device = 'wasm'; opts.dtype = 'q8';
    asr = await pipeline('automatic-speech-recognition', model, opts);
  }
  loadedId = model;
  self.postMessage({ type: 'ready', device: opts.device });
}

self.onmessage = async ({ data }) => {
  try {
    if (data.type === 'load') {
      await load(data.model);
    } else if (data.type === 'transcribe') {
      await load(data.model);
      const language = data.language === 'pt' ? 'portuguese' : data.language === 'en' ? 'english' : null;
      const out = await asr(data.audio, {
        language, task: 'transcribe',
        chunk_length_s: 30, stride_length_s: 5,
      });
      self.postMessage({ type: 'result', id: data.id, text: (out.text || '').trim() });
    }
  } catch (e) {
    self.postMessage({ type: 'error', id: data.id, message: String(e && e.message || e) });
  }
};
