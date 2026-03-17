"""LINE Models — Webhook events and Flex Message builder."""

from dataclasses import dataclass, field
from typing import Any, Optional


@dataclass
class WebhookEvent:
    """Parsed LINE webhook event."""

    type: str  # "message", "follow", "unfollow", "postback"
    reply_token: Optional[str] = None
    user_id: str = ""
    message_type: str = ""  # "text", "image", "sticker"
    message_text: str = ""
    timestamp: int = 0

    @classmethod
    def from_dict(cls, data: dict) -> "WebhookEvent":
        """Parse from LINE webhook JSON."""
        source = data.get("source", {})
        message = data.get("message", {})
        return cls(
            type=data.get("type", ""),
            reply_token=data.get("replyToken"),
            user_id=source.get("userId", ""),
            message_type=message.get("type", ""),
            message_text=message.get("text", ""),
            timestamp=data.get("timestamp", 0),
        )


class FlexMessageBuilder:
    """Build LINE Flex Messages.

    Generates Flex Message JSON for rich card-style messages.
    """

    def text_card(self, title: str, body: str) -> dict:
        """Build a simple text card Flex Message.

        Args:
            title: Card title.
            body: Card body text.

        Returns:
            LINE Flex Message dict.
        """
        return {
            "type": "flex",
            "altText": title,
            "contents": {
                "type": "bubble",
                "body": {
                    "type": "box",
                    "layout": "vertical",
                    "contents": [
                        {
                            "type": "text",
                            "text": title,
                            "weight": "bold",
                            "size": "xl",
                        },
                        {
                            "type": "text",
                            "text": body,
                            "wrap": True,
                            "margin": "md",
                        },
                    ],
                },
            },
        }

    def button_card(self, title: str, actions: list[dict]) -> dict:
        """Build a button card Flex Message.

        Args:
            title: Card title.
            actions: List of action dicts with 'label' and 'data' keys.

        Returns:
            LINE Flex Message dict with buttons.
        """
        buttons = [
            {
                "type": "button",
                "action": {
                    "type": "postback",
                    "label": a.get("label", ""),
                    "data": a.get("data", ""),
                },
            }
            for a in actions
        ]

        return {
            "type": "flex",
            "altText": title,
            "contents": {
                "type": "bubble",
                "body": {
                    "type": "box",
                    "layout": "vertical",
                    "contents": [
                        {
                            "type": "text",
                            "text": title,
                            "weight": "bold",
                            "size": "xl",
                        },
                    ],
                },
                "footer": {
                    "type": "box",
                    "layout": "vertical",
                    "contents": buttons,
                },
            },
        }
