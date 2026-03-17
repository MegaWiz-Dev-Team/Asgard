# PM-02-PK: Package Extract Report — Shared Service Packages
**Project Name:** 🏰 Asgard — AI Platform
**Sprint:** Package Extract (Phase 1)
**Date:** 2026-03-16
**Standard:** ISO/IEC 29110 — PM Process
**Status:** ✅ Complete

---

## Sprint Goal
Create reusable Python packages for LINE messaging, email sending, and text-to-speech — shared across all Asgard services.

## Deliverables

| Package | Files | Status |
|:--|:--|:--|
| 📱 `line_connector` | `client.py`, `models.py` | ✅ Done |
| 📧 `email_service` | `client.py`, `templates.py` | ✅ Done |
| 🔊 `tts_service` | `client.py` | ✅ Done |

## Package Details

### 📱 line_connector
- `LineClient`: Webhook HMAC-SHA256 verify, reply/push payload builder
- `FlexMessageBuilder`: Text card, button card Flex Messages
- `WebhookEvent`: Parse LINE webhook JSON events

### 📧 email_service
- `EmailClient`: SMTP send, email validation, MIME message builder
- `render_template()`: HTML templates (alert 🔴, report 🔵, notification 🟢)

### 🔊 tts_service
- `TTSClient`: Mock provider (testing) + Google Cloud TTS stub (production)
- Thai (`th-TH`) and English (`en-US`) support

## Testing Summary (TDD)

| Package | Tests |
|:--|:--|
| `line_connector` | 4 (webhook, push, reply, flex) |
| `email_service` | 3 (validate, build, template) |
| `tts_service` | 3 (Thai, English, empty error) |
| **Total** | **10** |
| Tests failed | 0 |
| Test time | 0.03s |

## Quality Gates

- [x] `pytest packages/` — 10 pass, 0 fail
- [x] TDD cycle: Red → Green

---

*บันทึกโดย: AI Assistant (ISO/IEC 29110 PM-02)*
