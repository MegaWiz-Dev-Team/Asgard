"""Tests for TTS Service — text-to-speech synthesis.

TDD Red Phase: Tests before implementation.
"""

import pytest

from packages.tts_service.client import TTSClient


class TestTTSClient:
    """Test TTS synthesis."""

    def test_synthesize_returns_bytes(self):
        client = TTSClient(provider="mock")
        result = client.synthesize("สวัสดีครับ", lang="th-TH")
        assert isinstance(result, bytes)
        assert len(result) > 0

    def test_synthesize_english(self):
        client = TTSClient(provider="mock")
        result = client.synthesize("Hello world", lang="en-US")
        assert isinstance(result, bytes)
        assert len(result) > 0

    def test_empty_text_raises(self):
        client = TTSClient(provider="mock")
        with pytest.raises(ValueError, match="empty"):
            client.synthesize("", lang="th-TH")
