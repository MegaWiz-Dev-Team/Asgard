"""Tests for LINE Connector — webhook verification, messaging, flex builder.

TDD Red Phase: Tests before implementation.
"""

import pytest
import hashlib
import hmac
import base64

from packages.line_connector.client import LineClient
from packages.line_connector.models import FlexMessageBuilder, WebhookEvent


class TestLineWebhook:
    """Test LINE webhook signature verification."""

    def test_verify_valid_signature(self):
        client = LineClient(channel_secret="test_secret", channel_token="test_token")
        body = b'{"events":[]}'
        # Compute correct HMAC-SHA256
        expected_sig = base64.b64encode(
            hmac.new(b"test_secret", body, hashlib.sha256).digest()
        ).decode()
        assert client.verify_webhook(expected_sig, body) is True

    def test_verify_invalid_signature(self):
        client = LineClient(channel_secret="test_secret", channel_token="test_token")
        assert client.verify_webhook("invalid_sig", b'{"events":[]}') is False


class TestLineMessaging:
    """Test LINE message sending."""

    @pytest.mark.asyncio
    async def test_reply_message_format(self):
        client = LineClient(channel_secret="secret", channel_token="token")
        payload = client.build_reply_payload("reply_token_123", [{"type": "text", "text": "สวัสดี"}])
        assert payload["replyToken"] == "reply_token_123"
        assert len(payload["messages"]) == 1


class TestFlexMessageBuilder:
    """Test Flex Message construction."""

    def test_text_card(self):
        builder = FlexMessageBuilder()
        msg = builder.text_card("ยินดีต้อนรับ", "สวัสดีครับ มีอะไรให้ช่วยไหม?")
        assert msg["type"] == "flex"
        assert "contents" in msg
        assert msg["altText"] == "ยินดีต้อนรับ"
