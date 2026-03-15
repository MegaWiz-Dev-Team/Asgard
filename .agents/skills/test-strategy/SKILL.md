---
name: test-strategy
description: "Define test pyramid, coverage targets, and testing patterns for Rust/Python/TypeScript. Unit, integration, E2E, and browser automation testing."
---

# Test Strategy

> "455+ tests and counting — every line of test code is an investment in sleep."

## Purpose

Guide test creation decisions: what to test, how to test, and when each test type is appropriate across Asgard's multi-language stack.

---

## Prerequisites — Read First

| File | Why |
|------|-----|
| `docs/architecture.md` | Component boundaries and interfaces |
| Each repo's `tests/` directory | Existing test patterns |

---

## Process

### 1️⃣ Test Pyramid

```
        /  E2E  \          ← Few, slow, high confidence
       / Browser  \
      / Integration \      ← Medium count, test boundaries
     /  API / Service \
    /    Unit Tests     \  ← Many, fast, test logic
   /_____________________\
```

| Level | Count | Speed | Scope |
|-------|-------|-------|-------|
| Unit | 70% of tests | < 1s each | Single function/module |
| Integration | 20% of tests | < 10s each | Service + dependencies |
| E2E | 10% of tests | < 60s each | Full user journey |

### 2️⃣ Rust Testing (Heimdall, Mimir API, Eir, Vardr)

```rust
// Unit test — test business logic in isolation
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_chunk_text_respects_max_tokens() {
        let result = chunk_text("hello world", 5);
        assert!(result.len() <= 5);
    }

    // Async test with tokio
    #[tokio::test]
    async fn test_health_endpoint_returns_ok() {
        let app = create_app().await;
        let response = app.oneshot(
            Request::get("/health").body(Body::empty()).unwrap()
        ).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }
}
```

**When to use each:**
- `#[test]` — Pure logic, no I/O
- `#[tokio::test]` — Async logic, HTTP handlers
- Integration tests in `tests/` — Full service with test DB
- `mockall` — Mock external dependencies

### 3️⃣ Python Testing (Bifrost, Fenrir, Yggdrasil)

```python
# Unit test — test logic in isolation
def test_build_react_prompt():
    prompt = build_react_prompt("What is 2+2?", tools=[])
    assert "Thought:" in prompt

# Async test with httpx
@pytest.mark.asyncio
async def test_health_endpoint():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        response = await ac.get("/health")
    assert response.status_code == 200

# Fixture for shared setup
@pytest.fixture
def sample_agent():
    return Agent(name="test", model="qwen3.5:9b")
```

**When to use each:**
- `pytest` — Standard unit tests
- `pytest.mark.asyncio` — Async endpoints
- `httpx.AsyncClient` — FastAPI integration tests
- `unittest.mock.patch` — Mock external services

### 4️⃣ Browser/E2E Testing (Fenrir, Dashboard)

```python
# Playwright for browser automation testing
async def test_dashboard_login_flow(page):
    await page.goto("http://localhost:3000")
    await page.fill("#email", "admin@test.com")
    await page.fill("#password", "test1234")
    await page.click("#login-btn")
    await expect(page.locator("#dashboard-title")).to_be_visible()
```

**When to use E2E:**
- Critical user journeys (login, RAG query, agent execution)
- Cross-service flows (Bifrost → Heimdall → LLM)
- UI regression (Dashboard critical paths)

### 5️⃣ Test Naming Convention

```
test_[unit]_[action]_[expected_result]

Examples:
test_chunk_text_returns_empty_for_empty_input
test_health_endpoint_returns_200
test_auth_rejects_expired_token
test_rag_pipeline_returns_relevant_chunks
```

### 6️⃣ CI-Friendly Execution

```bash
# Rust — run all tests with output
cargo test -- --nocapture

# Python — run with coverage
pytest --cov=. --cov-report=term-missing -v

# Specific test file
cargo test --test integration_tests
pytest tests/test_health.py -v
```

### 7️⃣ Coverage Targets

| Component | Current | Target |
|-----------|---------|--------|
| Mimir API | Track | 80%+ |
| Heimdall | Track | 70%+ |
| Bifrost | Track | 80%+ |
| Eir | Track | 70%+ |
| Dashboard | Track | 60%+ |

---

## Key Principles
- Test behavior, not implementation
- Flaky tests are worse than no tests — fix or delete
- Every bug fix gets a regression test
- Fast test suite = more frequent runs = fewer bugs

## When to Use
When adding new features, fixing bugs, planning sprint testing scope, or reviewing test coverage.
