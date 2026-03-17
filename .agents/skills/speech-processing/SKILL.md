---
name: speech-processing
description: Speech-to-Text (STT) and Text-to-Speech (TTS) patterns for Sága service using Whisper and Google Cloud
---

# Speech Processing — Sága Service

## Overview
Patterns for building the Sága (🗣️) speech processing service. Covers Whisper STT, Google Cloud TTS, streaming transcription, and speaker diarization.

## STT with Whisper
```python
import whisper
import numpy as np

class WhisperSTT:
    def __init__(self, model_size: str = "large-v3"):
        self.model = whisper.load_model(model_size)
    
    def transcribe(self, audio_path: str, language: str = "th") -> dict:
        result = self.model.transcribe(
            audio_path,
            language=language,
            task="transcribe",
            fp16=False  # CPU mode
        )
        return {
            "text": result["text"],
            "language": result["language"],
            "segments": [
                {
                    "start": s["start"],
                    "end": s["end"],
                    "text": s["text"],
                    "confidence": s.get("avg_logprob", 0)
                }
                for s in result["segments"]
            ]
        }
```

## Streaming STT via WebSocket
```python
from fastapi import WebSocket
import asyncio

@app.websocket("/v1/stt/stream")
async def stt_stream(websocket: WebSocket):
    await websocket.accept()
    buffer = bytearray()
    
    try:
        while True:
            data = await websocket.receive_bytes()
            buffer.extend(data)
            
            # Process every 3 seconds of audio (48kHz * 2 bytes * 3s)
            if len(buffer) >= 288000:
                audio = np.frombuffer(buffer, dtype=np.int16).astype(np.float32) / 32768.0
                result = await asyncio.to_thread(
                    model.transcribe,
                    audio,
                    language="th"
                )
                await websocket.send_json({
                    "type": "partial",
                    "text": result["text"]
                })
                buffer.clear()
    except Exception:
        await websocket.close()
```

## Google Cloud TTS (from MegaCare)
```python
from google.cloud import texttospeech

class GoogleTTS:
    def __init__(self):
        self.client = texttospeech.TextToSpeechClient()
    
    def synthesize(self, text: str, language: str = "th-TH") -> bytes:
        synthesis_input = texttospeech.SynthesisInput(text=text)
        voice = texttospeech.VoiceSelectionParams(
            language_code=language,
            ssml_gender=texttospeech.SsmlVoiceGender.FEMALE
        )
        audio_config = texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.MP3
        )
        response = self.client.synthesize_speech(
            input=synthesis_input, voice=voice, audio_config=audio_config
        )
        return response.audio_content
```

## Audio Preprocessing
```python
import subprocess

def convert_to_wav(input_path: str, output_path: str):
    """Convert audio file to WAV (16kHz mono) for Whisper."""
    subprocess.run([
        "ffmpeg", "-i", input_path,
        "-ar", "16000",     # 16kHz sample rate
        "-ac", "1",         # Mono
        "-f", "wav",
        output_path
    ], check=True)

def noise_reduction(audio_path: str) -> str:
    """Basic noise reduction using sox."""
    output = audio_path.replace(".wav", "_clean.wav")
    subprocess.run([
        "sox", audio_path, output,
        "noisered", "noise_profile", "0.21"
    ], check=True)
    return output
```

## API Endpoints (Sága :8700)
```
POST /v1/stt/transcribe     → Upload audio file → text
WS   /v1/stt/stream         → Real-time streaming STT
POST /v1/tts/synthesize     → Text → audio file
GET  /v1/models             → Available STT/TTS models
GET  /health                → Health check
```

## Docker Considerations
- Whisper large-v3 model: ~3GB download (cache in Docker layer)
- ffmpeg required for audio conversion
- sox for noise reduction (optional)
```dockerfile
FROM python:3.12-slim
RUN apt-get update && apt-get install -y ffmpeg sox
RUN pip install openai-whisper torch --index-url https://download.pytorch.org/whl/cpu
# Pre-download model
RUN python -c "import whisper; whisper.load_model('large-v3')"
```

## Supported Languages
| Language | Whisper Code | TTS Code |
|:--|:--|:--|
| Thai | th | th-TH |
| English | en | en-US |
| Japanese | ja | ja-JP |
| Chinese | zh | cmn-CN |
| Korean | ko | ko-KR |
