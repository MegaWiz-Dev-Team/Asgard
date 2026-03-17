---
name: fastapi-service-pattern
description: How to scaffold and build FastAPI microservices for Asgard platform (Python services like Syn, Sága, Hermóðr)
---

# FastAPI Service Pattern — Asgard Platform

## Overview
This skill guides the creation of Python FastAPI microservices that integrate into the Asgard AI Platform ecosystem.

## Standard Service Structure
```
ServiceName/
├── src/
│   ├── main.py              # FastAPI app entry point
│   ├── config.py             # Pydantic Settings from env vars
│   ├── health.py             # GET /health, GET /readyz
│   ├── models.py             # Pydantic request/response models
│   ├── routes/               # API route modules
│   └── services/             # Business logic
├── tests/
│   ├── conftest.py           # Shared fixtures (test client, mock config)
│   ├── test_health.py
│   └── test_*.py
├── Dockerfile                # Multi-stage (python:3.12-slim)
├── requirements.txt
└── README.md
```

## Core Patterns

### 1. Config (Pydantic Settings)
```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    service_name: str = "service-name"
    port: int = 8600
    log_level: str = "info"
    heimdall_url: str = "http://heimdall:8080"
    bifrost_url: str = "http://bifrost:8100"
    auth_enabled: bool = False

    class Config:
        env_prefix = "SERVICE_"
        env_file = ".env"

settings = Settings()
```

### 2. Health Endpoints (Várðr compatible)
```python
from fastapi import APIRouter
router = APIRouter()

@router.get("/health")
async def health():
    return {"status": "healthy", "service": settings.service_name, "version": "0.1.0"}

@router.get("/readyz")
async def readyz():
    # Check downstream dependencies
    return {"status": "ready", "checks": {"heimdall": "ok"}}
```

### 3. Main App Assembly
```python
from fastapi import FastAPI
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    # startup logic
    yield
    # shutdown logic

app = FastAPI(
    title=f"Asgard — {settings.service_name}",
    version="0.1.0",
    lifespan=lifespan
)
app.include_router(health_router)
app.include_router(api_router, prefix="/v1")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=settings.port)
```

### 4. Dockerfile
```dockerfile
FROM python:3.12-slim AS base
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY src/ ./src/
EXPOSE 8600
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8600"]
```

### 5. Docker Compose Integration
Add to Asgard's `docker-compose.yml`:
```yaml
service-name:
  build: ../ServiceName
  container_name: asgard_service_name
  ports: ["8600:8600"]
  environment:
    - SERVICE_HEIMDALL_URL=http://heimdall:8080
    - SERVICE_BIFROST_URL=http://bifrost:8100
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8600/health"]
    interval: 30s
    retries: 3
  networks: [asgard]
```

### 6. Testing (pytest + httpx)
```python
import pytest
from httpx import AsyncClient, ASGITransport
from src.main import app

@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c

@pytest.mark.asyncio
async def test_health(client):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "healthy"
```

## Asgard Integration Ports
| Service | Port | Purpose |
|:--|:--|:--|
| Syn | :8600 | OCR + eKYC |
| Sága | :8700 | STT (Speech-to-Text) |
| Hermóðr | :8800 | Notification Gateway |

## Key Dependencies
- `fastapi>=0.115.0`
- `uvicorn[standard]>=0.32.0`
- `pydantic-settings>=2.0`
- `httpx>=0.27.0` (for calling other Asgard services)
- `pytest>=8.0`, `pytest-asyncio>=0.24.0`

## ISO Documentation
Every sprint must produce:
1. `docs/iso_29110/SI_01_Implementation_Report.md`
2. Test count in PM_01_Project_Plan.md
