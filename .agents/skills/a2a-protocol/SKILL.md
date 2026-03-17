---
name: a2a-protocol
description: Google A2A (Agent-to-Agent) protocol implementation patterns for Asgard inter-service communication
---

# A2A Protocol Implementation — Asgard Platform

## Overview
The A2A (Agent-to-Agent) protocol enables structured task delegation between Asgard services. Eir implements the server side; Bifrost implements the client side.

## Protocol Flow
```
Bifrost (Client)                    Eir (Server)
    │                                    │
    │  POST /a2a/tasks/send              │
    │  { skill, message, metadata }      │
    ├───────────────────────────────────→ │
    │                                    │
    │  { task: { id, state, messages } } │
    │ ←──────────────────────────────────┤
    │                                    │
    │  GET /a2a/tasks/{id}               │
    ├───────────────────────────────────→ │
    │  { task: { state: "completed" } }  │
    │ ←──────────────────────────────────┤
```

## Agent Card (`/.well-known/agent.json`)
Every A2A-capable service must expose an Agent Card:
```json
{
  "name": "Service Name",
  "description": "What this agent does",
  "url": "http://service:port",
  "version": "0.1.0",
  "protocol": "a2a",
  "capabilities": {
    "streaming": false,
    "pushNotifications": false,
    "stateTransitionHistory": true
  },
  "skills": [
    {
      "id": "skill-id",
      "name": "Skill Name",
      "description": "What this skill does",
      "tags": ["tag1", "tag2"]
    }
  ],
  "authentication": { "schemes": ["bearer"] }
}
```

## Task States (Lifecycle)
```
submitted → working → completed
                   → failed
                   → input-required → working
         → canceled
```

## Task Send Request
```python
import httpx

async def send_a2a_task(target_url: str, skill: str, text: str):
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            f"{target_url}/a2a/tasks/send",
            json={
                "skill": skill,
                "message": {
                    "role": "user",
                    "parts": [{"type": "text", "text": text}]
                },
                "metadata": {"source": "bifrost"}
            }
        )
        return resp.json()["task"]
```

## Task Send in Rust
```rust
#[derive(Serialize)]
struct SendTaskRequest {
    skill: String,
    message: A2AMessage,
    metadata: serde_json::Value,
}

let resp = client
    .post(&format!("{}/a2a/tasks/send", target_url))
    .json(&SendTaskRequest {
        skill: "fhir-query".into(),
        message: A2AMessage {
            role: "user".into(),
            parts: vec![json!({"type": "text", "text": query})],
        },
        metadata: json!({"source": "bifrost"}),
    })
    .send()
    .await?;
```

## Adding A2A to a New Service
1. Define skills in the Agent Card
2. Implement `POST /a2a/tasks/send` handler
3. Create in-memory or persistent task store
4. Expose `GET /.well-known/agent.json`
5. Add `GET /a2a/tasks/{id}` for status polling
6. Register in Bifrost's agent registry
