---
name: notification-patterns
description: Multi-channel notification patterns for Hermóðr service (SMS, Push, Webhook, LINE, Email)
---

# Notification Patterns — Hermóðr Service

## Overview
Patterns for building the Hermóðr (📨) unified notification gateway in the Asgard platform. Handles SMS, Push notifications, Webhooks, LINE messaging, and Email.

## Channel Abstractions
```python
from abc import ABC, abstractmethod
from pydantic import BaseModel

class NotificationPayload(BaseModel):
    recipient: str          # Phone, token, URL, or user_id
    template_id: str        # Template identifier
    variables: dict = {}    # Template variables
    priority: str = "normal"  # normal, high, critical
    idempotency_key: str | None = None

class NotificationResult(BaseModel):
    channel: str
    status: str             # sent, failed, queued
    message_id: str | None
    error: str | None = None

class NotificationChannel(ABC):
    @abstractmethod
    async def send(self, payload: NotificationPayload) -> NotificationResult:
        pass
    
    @abstractmethod
    async def check_status(self, message_id: str) -> str:
        pass
```

## Channel Implementations

### SMS (ThaiBulkSMS / Twilio)
```python
class SMSChannel(NotificationChannel):
    async def send(self, payload: NotificationPayload) -> NotificationResult:
        # ThaiBulkSMS API
        resp = await self.client.post(
            "https://api.thaibulksms.com/v2/sms",
            json={
                "msisdn": payload.recipient,
                "message": self.render_template(payload),
                "sender": self.sender_name
            },
            headers={"Authorization": f"Bearer {self.api_key}"}
        )
        return NotificationResult(channel="sms", status="sent", message_id=resp.json()["id"])
```

### Push (FCM)
```python
from firebase_admin import messaging

class PushChannel(NotificationChannel):
    async def send(self, payload: NotificationPayload) -> NotificationResult:
        message = messaging.Message(
            token=payload.recipient,
            notification=messaging.Notification(
                title=payload.variables.get("title", "Asgard"),
                body=self.render_template(payload)
            )
        )
        result = messaging.send(message)
        return NotificationResult(channel="push", status="sent", message_id=result)
```

### Webhook
```python
class WebhookChannel(NotificationChannel):
    async def send(self, payload: NotificationPayload) -> NotificationResult:
        resp = await self.client.post(
            payload.recipient,  # URL
            json={"event": payload.template_id, "data": payload.variables},
            timeout=10.0
        )
        return NotificationResult(
            channel="webhook",
            status="sent" if resp.status_code < 400 else "failed",
            message_id=str(resp.status_code)
        )
```

## Retry Queue Pattern
```python
import asyncio
from collections import deque

class RetryQueue:
    def __init__(self, max_retries: int = 3, backoff_base: float = 2.0):
        self.queue: deque = deque()
        self.max_retries = max_retries
        self.backoff_base = backoff_base
    
    async def enqueue(self, channel: NotificationChannel, payload: NotificationPayload):
        self.queue.append((channel, payload, 0))
    
    async def process(self):
        while self.queue:
            channel, payload, attempt = self.queue.popleft()
            try:
                result = await channel.send(payload)
                if result.status == "failed" and attempt < self.max_retries:
                    await asyncio.sleep(self.backoff_base ** attempt)
                    self.queue.append((channel, payload, attempt + 1))
            except Exception:
                if attempt < self.max_retries:
                    self.queue.append((channel, payload, attempt + 1))
```

## Deduplication
```python
class DeduplicationStore:
    def __init__(self, ttl_seconds: int = 3600):
        self._seen: dict[str, float] = {}
        self.ttl = ttl_seconds
    
    def is_duplicate(self, idempotency_key: str) -> bool:
        if idempotency_key in self._seen:
            return True
        self._seen[idempotency_key] = time.time()
        return False
```

## API Endpoints (Hermóðr :8800)
```
POST /v1/notify/sms         → Send SMS
POST /v1/notify/push        → Send Push notification
POST /v1/notify/webhook     → Dispatch webhook
POST /v1/notify/batch       → Send to multiple channels
GET  /v1/notify/{id}/status → Check delivery status
GET  /v1/templates          → List templates
GET  /health                → Health check
```

## Template Management
```
templates/
├── insurance/
│   ├── claim_status.json     # "สถานะเคลม: {{status}}"
│   ├── policy_reminder.json
│   └── uw_result.json
└── healthcare/
    ├── appointment.json      # "นัดพบแพทย์: {{date}} {{time}}"
    ├── assessment_result.json
    └── medication_reminder.json
```
