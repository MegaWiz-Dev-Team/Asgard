---
name: ai-guardrails
description: AI safety guardrails implementation patterns for Bifrost agent runtime (PII filter, kill switch, hallucination check)
---

# AI Guardrails — Bifrost Agent Runtime

## Overview
Patterns for implementing safety guardrails in the Bifrost agent pipeline. These are middleware that intercept agent inputs/outputs to enforce safety policies.

## Architecture
```
User Input → [PII Filter] → [Content Filter] → Agent Pipeline → [Hallucination Check] → [PII Filter] → Response
                                                                                              ↓
                                                                              [Kill Switch] (Emergency Stop)
```

## PII Filter (Thai + English)
```python
import re
from typing import NamedTuple

class PIIMatch(NamedTuple):
    type: str
    value: str
    masked: str
    start: int
    end: int

PATTERNS = {
    "thai_id": re.compile(r'\b\d{1}-\d{4}-\d{5}-\d{2}-\d{1}\b'),               # 1-2345-67890-12-3
    "thai_id_raw": re.compile(r'\b\d{13}\b'),                                    # 1234567890123
    "phone_th": re.compile(r'\b0[689]\d-?\d{3}-?\d{4}\b'),                       # 081-234-5678
    "email": re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'),
    "credit_card": re.compile(r'\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b'),
    "bank_account": re.compile(r'\b\d{3}-\d{1}-\d{5}-\d{1}\b'),                 # Thai bank account
    "passport": re.compile(r'\b[A-Z]{1,2}\d{6,7}\b'),
}

def detect_pii(text: str) -> list[PIIMatch]:
    matches = []
    for pii_type, pattern in PATTERNS.items():
        for m in pattern.finditer(text):
            masked = m.group()[:2] + '*' * (len(m.group()) - 4) + m.group()[-2:]
            matches.append(PIIMatch(pii_type, m.group(), masked, m.start(), m.end()))
    return matches

def mask_pii(text: str) -> str:
    for match in sorted(detect_pii(text), key=lambda m: m.start, reverse=True):
        text = text[:match.start] + match.masked + text[match.end:]
    return text
```

## Kill Switch
```python
from fastapi import APIRouter, HTTPException
import asyncio

router = APIRouter(prefix="/guardrails")

_kill_switch_active = False
_kill_reason = ""

@router.post("/kill")
async def activate_kill_switch(reason: str = "Emergency stop"):
    global _kill_switch_active, _kill_reason
    _kill_switch_active = True
    _kill_reason = reason
    return {"status": "killed", "reason": reason}

@router.post("/resume")
async def resume():
    global _kill_switch_active
    _kill_switch_active = False
    return {"status": "resumed"}

@router.get("/status")
async def kill_status():
    return {"active": _kill_switch_active, "reason": _kill_reason}

# Middleware
async def check_kill_switch():
    if _kill_switch_active:
        raise HTTPException(503, f"Agent killed: {_kill_reason}")
```

## Hallucination Check
```python
async def check_hallucination(response: str, sources: list[dict]) -> dict:
    """Check if agent response is grounded in source documents."""
    if not sources:
        return {"grounded": False, "reason": "No sources provided"}
    
    source_texts = " ".join([s.get("content", "") for s in sources])
    
    # Use Heimdall to check grounding
    result = await heimdall_client.generate(
        prompt=f"""Check if the following response is factually grounded in the source texts.
        
Response: {response}
Sources: {source_texts[:2000]}

Return JSON: {{"grounded": true/false, "confidence": 0.0-1.0, "ungrounded_claims": []}}""",
        max_tokens=200
    )
    return result
```

## Content Filter
```python
BLOCKED_CATEGORIES = [
    "medical_advice_without_disclaimer",
    "financial_guarantee",
    "personal_data_request",
    "discriminatory_content",
]

async def filter_content(text: str) -> dict:
    """Check content against blocked categories."""
    # Simple keyword check + LLM classification for nuanced cases
    flags = []
    
    # Quick keyword checks
    if any(w in text.lower() for w in ["guaranteed returns", "100% cure"]):
        flags.append("financial_guarantee")
    
    return {"passed": len(flags) == 0, "flags": flags}
```

## Integration as Bifrost Middleware
```python
# In bifrost/executor/react.py
class GuardedReActExecutor:
    async def execute(self, input: str) -> str:
        # Pre-check
        await check_kill_switch()
        input = mask_pii(input)
        content_check = await filter_content(input)
        if not content_check["passed"]:
            return f"Content blocked: {content_check['flags']}"
        
        # Run agent
        response = await self.agent.run(input)
        
        # Post-check
        response = mask_pii(response)
        grounding = await check_hallucination(response, self.sources)
        if not grounding["grounded"]:
            response += "\n⚠️ This response may not be fully grounded in available sources."
        
        return response
```
