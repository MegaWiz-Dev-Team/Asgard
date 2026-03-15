---
name: api-design
description: "Design RESTful APIs with OpenAPI 3.1 specs, consistent error formats, JWT auth patterns, and cross-service conventions for the Asgard platform."
---

# API Design

> "A good API is like a good joke — it needs no explanation."

## Purpose

Maintain consistent API design across Asgard's 6 API services (Mimir, Heimdall, Bifrost, Fenrir, Eir, Yggdrasil). Standardize contracts, error formats, and authentication flows.

---

## Prerequisites — Read First

| File | Why |
|------|-----|
| `docs/architecture.md` | Service boundaries and data flows |
| Each service's OpenAPI spec | Current API surface |

---

## Process

### 1️⃣ URL Conventions

```
# Pattern: /{api-prefix}/{version}/{resource}/{id}/{sub-resource}

# Examples:
GET    /api/v1/sources              # List sources
POST   /api/v1/sources              # Create source
GET    /api/v1/sources/:id          # Get source
PUT    /api/v1/sources/:id          # Update source
DELETE /api/v1/sources/:id          # Delete source
GET    /api/v1/sources/:id/chunks   # List chunks for source
POST   /api/v1/pipeline/run         # Trigger action (verb for non-CRUD)
```

**Rules:**
- Plural nouns for resources (`/sources`, not `/source`)
- Lowercase with hyphens (`/api-spec`, not `/apiSpec`)
- Max 3 levels deep
- Use query params for filtering: `?status=active&limit=20`

### 2️⃣ Standard Response Format

```json
// Success
{
  "data": { ... },
  "meta": {
    "total": 100,
    "page": 1,
    "per_page": 20
  }
}

// Error
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid source ID format",
    "details": [
      { "field": "source_id", "reason": "Must be a positive integer" }
    ]
  }
}
```

### 3️⃣ HTTP Status Codes

| Code | When to Use |
|------|-------------|
| 200 | Successful GET, PUT, PATCH |
| 201 | Successful POST (created) |
| 204 | Successful DELETE |
| 400 | Bad request / validation error |
| 401 | Missing or invalid auth token |
| 403 | Valid token but insufficient permissions |
| 404 | Resource not found |
| 409 | Conflict (duplicate, state mismatch) |
| 422 | Unprocessable entity (semantic error) |
| 429 | Rate limited |
| 500 | Internal server error |
| 503 | Service unavailable |

### 4️⃣ Authentication Pattern

```
Client → Yggdrasil (login) → JWT tokens
Client → Service (with Bearer token) → Service validates JWT

# Header
Authorization: Bearer eyJhbGciOiJSUzI1NiIs...

# JWT Claims
{
  "sub": "user-123",
  "org_id": "org-456",
  "roles": ["admin"],
  "exp": 1710000000
}
```

**Rules:**
- All services validate JWT from Yggdrasil
- Service-to-service uses internal API keys
- Sensitive endpoints require specific roles
- Token refresh handled by client

### 5️⃣ Pagination

```
GET /api/v1/sources?page=2&per_page=20

Response:
{
  "data": [...],
  "meta": {
    "total": 150,
    "page": 2,
    "per_page": 20,
    "total_pages": 8
  }
}
```

### 6️⃣ OpenAPI Specification

Every service must expose:
- `GET /api-spec` — OpenAPI 3.1 JSON
- `GET /docs` — Interactive documentation (Scalar UI)

```yaml
openapi: "3.1.0"
info:
  title: "Asgard [Service] API"
  version: "1.0.0"
  description: "..."
servers:
  - url: "http://localhost:{port}"
paths:
  /health:
    get:
      summary: "Health check"
      responses:
        "200":
          description: "Service is healthy"
```

### 7️⃣ Versioning Strategy

- URL-based versioning: `/api/v1/`, `/api/v2/`
- v1 remains stable until v2 is deployed
- Breaking changes = new version
- Additive changes (new fields, endpoints) = same version

---

## Key Principles
- Consistency > creativity — all services use the same patterns
- Error messages should help the developer fix the problem
- Design the API from the consumer's perspective
- Document-first: write the OpenAPI spec before the code

## When to Use
When creating new endpoints, refactoring existing APIs, reviewing cross-service integration, or onboarding contributors.
