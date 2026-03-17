"""LINE Messaging API Client.

Handles webhook verification, message sending (reply + push),
and LINE Messaging API communication.
"""

import hashlib
import hmac
import base64
from dataclasses import dataclass


@dataclass
class LineClient:
    """LINE Messaging API client.

    Args:
        channel_secret: LINE Channel Secret for webhook verification.
        channel_token: LINE Channel Access Token for API calls.
    """

    channel_secret: str
    channel_token: str

    # LINE API base URL
    API_BASE = "https://api.line.me/v2/bot"

    def verify_webhook(self, signature: str, body: bytes) -> bool:
        """Verify LINE webhook signature using HMAC-SHA256.

        Args:
            signature: X-Line-Signature header value.
            body: Raw request body bytes.

        Returns:
            True if signature is valid.
        """
        try:
            expected = base64.b64encode(
                hmac.new(
                    self.channel_secret.encode("utf-8"),
                    body,
                    hashlib.sha256,
                ).digest()
            ).decode("utf-8")
            return hmac.compare_digest(signature, expected)
        except Exception:
            return False

    def build_reply_payload(self, reply_token: str, messages: list[dict]) -> dict:
        """Build reply message payload.

        Args:
            reply_token: Token from the webhook event.
            messages: List of message objects.

        Returns:
            Payload dict for LINE reply API.
        """
        return {
            "replyToken": reply_token,
            "messages": messages,
        }

    def build_push_payload(self, user_id: str, messages: list[dict]) -> dict:
        """Build push message payload.

        Args:
            user_id: Target user's LINE user ID.
            messages: List of message objects.

        Returns:
            Payload dict for LINE push API.
        """
        return {
            "to": user_id,
            "messages": messages,
        }

    def get_headers(self) -> dict:
        """Get authorization headers for LINE API."""
        return {
            "Authorization": f"Bearer {self.channel_token}",
            "Content-Type": "application/json",
        }
