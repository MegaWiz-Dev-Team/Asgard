"""TTS Client — Text-to-Speech synthesis.

Supports mock provider for testing and Google Cloud TTS for production.
"""

import struct
from dataclasses import dataclass


@dataclass
class TTSClient:
    """Text-to-Speech client.

    Args:
        provider: TTS provider ('mock' for testing, 'google' for production).
        api_key: API key for cloud TTS (optional for mock).
    """

    provider: str = "mock"
    api_key: str = ""

    def synthesize(self, text: str, lang: str = "th-TH") -> bytes:
        """Synthesize text to speech (MP3 bytes).

        Args:
            text: Text to synthesize.
            lang: Language code (e.g., 'th-TH', 'en-US').

        Returns:
            MP3 audio bytes.

        Raises:
            ValueError: If text is empty.
        """
        if not text or not text.strip():
            raise ValueError("Text cannot be empty")

        if self.provider == "mock":
            return self._mock_synthesize(text, lang)
        elif self.provider == "google":
            return self._google_synthesize(text, lang)
        else:
            raise ValueError(f"Unknown provider: {self.provider}")

    def _mock_synthesize(self, text: str, lang: str) -> bytes:
        """Generate mock MP3 bytes for testing.

        Creates a minimal valid byte sequence that represents
        the text content (not actual audio).
        """
        # Create deterministic mock audio based on input
        header = b"MOCK_MP3"
        content = f"{lang}:{text}".encode("utf-8")
        size = struct.pack(">I", len(content))
        return header + size + content

    def _google_synthesize(self, text: str, lang: str) -> bytes:
        """Synthesize using Google Cloud TTS.

        Requires google-cloud-texttospeech package and valid API key.
        Stub for future implementation.
        """
        raise NotImplementedError(
            "Google Cloud TTS not yet configured. "
            "Install google-cloud-texttospeech and set API key."
        )
