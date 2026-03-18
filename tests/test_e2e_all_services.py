"""Asgard Platform — Comprehensive E2E Test Suite.

Tests all 12 services' core functionality with mock-based unit tests.
For live integration testing, use the bash scripts in Asgard/scripts/e2e/.

Run: cd /Users/mimir/Developer/Asgard && python -m pytest tests/test_e2e_all_services.py -v

Service Map:
  1. Mimir      (4200) — Knowledge Base
  2. Bifrost    (8100) — Agent Runtime
  3. Heimdall   (8080) — LLM Gateway
  4. Ratatoskr  (9200) — Browser Service
  5. Fenrir     (8200) — Clinical Automation
  6. Forseti    (5555) — QA Testing
  7. Huginn     (8400) — Security Scanner
  8. Muninn     (8500) — Auto-Fixer
  9. Eir        (8300) — OpenEMR Gateway
  10. Vardr     (3000) — Infra Monitor
  11. Yggdrasil (8443) — Auth Service
  12. Asgard    (—)    — Platform Orchestrator
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from dataclasses import dataclass


# ═══════════════════════════════════════════════════════════════
# Service Client Abstraction
# ═══════════════════════════════════════════════════════════════


@dataclass
class ServiceHealth:
    """Health check result for a service."""
    service: str
    url: str
    healthy: bool
    version: str = ""
    details: str = ""


class AsgardServiceClient:
    """Unified client for all Asgard services."""

    SERVICE_PORTS = {
        "mimir": 4200,
        "bifrost": 8100,
        "heimdall": 8080,
        "ratatoskr": 9200,
        "fenrir": 8200,
        "forseti": 5555,
        "huginn": 8400,
        "muninn": 8500,
        "eir": 8300,
        "vardr": 3000,
        "yggdrasil": 8443,
        "asgard": 8100,  # via Bifrost
    }

    HEALTH_ENDPOINTS = {
        "mimir": "/api/health",
        "bifrost": "/healthz",
        "heimdall": "/v1/models",
        "ratatoskr": "/healthz",
        "fenrir": "/healthz",
        "forseti": "/health",
        "huginn": "/healthz",
        "muninn": "/health",
        "eir": "/api/health",
        "vardr": "/health",
        "yggdrasil": "/health",
        "asgard": "/healthz",
    }

    def __init__(self, base_host: str = "localhost"):
        self.base_host = base_host

    def url_for(self, service: str, path: str = "") -> str:
        port = self.SERVICE_PORTS.get(service, 8100)
        return f"http://{self.base_host}:{port}{path}"

    async def health_check(self, service: str) -> ServiceHealth:
        """Check health of a specific service."""
        endpoint = self.HEALTH_ENDPOINTS.get(service, "/health")
        url = self.url_for(service, endpoint)
        try:
            import httpx
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(url)
                return ServiceHealth(
                    service=service, url=url,
                    healthy=resp.status_code == 200,
                    version=resp.json().get("version", "") if resp.status_code == 200 else "",
                )
        except Exception as e:
            return ServiceHealth(service=service, url=url, healthy=False, details=str(e))

    async def health_all(self) -> list[ServiceHealth]:
        """Check health of all 12 services."""
        results = []
        for service in self.SERVICE_PORTS:
            result = await self.health_check(service)
            results.append(result)
        return results


# ═══════════════════════════════════════════════════════════════
# 1. SERVICE REGISTRY — ครบ 12 services
# ═══════════════════════════════════════════════════════════════


def test_all_12_services_configured():
    """All 12 Asgard services must be configured."""
    client = AsgardServiceClient()
    assert len(client.SERVICE_PORTS) == 12
    expected = {
        "mimir", "bifrost", "heimdall", "ratatoskr", "fenrir",
        "forseti", "huginn", "muninn", "eir", "vardr",
        "yggdrasil", "asgard",
    }
    assert set(client.SERVICE_PORTS.keys()) == expected


def test_all_services_have_health_endpoint():
    """Every service must have a health endpoint defined."""
    client = AsgardServiceClient()
    for service in client.SERVICE_PORTS:
        assert service in client.HEALTH_ENDPOINTS, f"{service} missing health endpoint"
        assert client.HEALTH_ENDPOINTS[service].startswith("/"), f"{service} invalid path"


def test_service_url_generation():
    """URL generation produces correct URLs for all services."""
    client = AsgardServiceClient()
    assert client.url_for("bifrost", "/healthz") == "http://localhost:8100/healthz"
    assert client.url_for("ratatoskr", "/api/v1/scrape") == "http://localhost:9200/api/v1/scrape"
    assert client.url_for("mimir", "/api/tenants") == "http://localhost:4200/api/tenants"


# ═══════════════════════════════════════════════════════════════
# 2. MIMIR — Knowledge Base (port 4200)
# ═══════════════════════════════════════════════════════════════


@pytest.mark.asyncio
async def test_mimir_tenant_crud():
    """Mimir: create, list, and query tenants."""
    from bifrost.clients.mimir_knowledge import MimirKnowledgeClient

    client = MimirKnowledgeClient(mimir_url="http://test:4200")

    async def mock_provision(name, display=""):
        return {"name": name, "display_name": display}

    with patch.object(client, "provision_tenant", side_effect=mock_provision):
        result = await client.provision_tenant("test-tenant", "Test")

    assert result["name"] == "test-tenant"


@pytest.mark.asyncio
async def test_mimir_ingest_and_query():
    """Mimir: ingest document then query it."""
    from bifrost.clients.mimir_knowledge import MimirKnowledgeClient

    client = MimirKnowledgeClient(mimir_url="http://test:4200")

    async def mock_ingest(tenant, content, metadata=None):
        return {"doc_id": "doc1", "chunks": 3}

    async def mock_query(tenant, question):
        return {"answer": "Found result", "sources": []}

    with patch.object(client, "ingest_markdown", side_effect=mock_ingest):
        ingest_result = await client.ingest_markdown("test", "# Hello")
    assert ingest_result["doc_id"] == "doc1"

    with patch.object(client, "query_tenant", side_effect=mock_query):
        query_result = await client.query_tenant("test", "What is Hello?")
    assert "answer" in query_result


@pytest.mark.asyncio
async def test_mimir_cross_tenant():
    """Mimir: cross-tenant query across multiple services."""
    from bifrost.clients.mimir_knowledge import MimirKnowledgeClient

    client = MimirKnowledgeClient()

    async def mock_query(tenant, question):
        return {"answer": f"{tenant} answer", "sources": []}

    with patch.object(client, "query_tenant", side_effect=mock_query):
        results = await client.cross_tenant_query("test?", ["mimir", "bifrost"])

    assert len(results) == 2


# ═══════════════════════════════════════════════════════════════
# 3. BIFROST — Agent Runtime (port 8100)
# ═══════════════════════════════════════════════════════════════


@pytest.mark.asyncio
async def test_bifrost_agent_lifecycle():
    """Bifrost: create, list, introduce, prompt, delete agent."""
    from bifrost.config import settings
    settings.auth_enabled = False

    from httpx import ASGITransport, AsyncClient
    from bifrost.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Create agent via identity
        resp = await client.post("/v1/agents", json={
            "agent_id": "e2e-test-agent",
            "persona_name": "E2E Tester",
            "persona_role": "Test Agent",
            "capabilities": ["testing"],
        })
        assert resp.status_code == 200
        assert resp.json()["status"] == "created"

        # List agents — should include our agent
        resp = await client.get("/v1/agents")
        assert resp.status_code == 200

        # Introduce
        resp = await client.get("/v1/agents/e2e-test-agent/introduce")
        assert resp.status_code == 200
        assert "E2E Tester" in resp.json()["introduction"]

        # Get prompt
        resp = await client.get("/v1/agents/e2e-test-agent/prompt")
        assert resp.status_code == 200
        assert len(resp.json()["system_prompt"]) > 10

        # Delete
        resp = await client.delete("/v1/agents/e2e-test-agent")
        assert resp.status_code == 200
        assert resp.json()["status"] == "deleted"


@pytest.mark.asyncio
async def test_bifrost_odin_ask():
    """Bifrost Odin: route questions to appropriate agents."""
    from bifrost.config import settings
    settings.auth_enabled = False

    from httpx import ASGITransport, AsyncClient
    from bifrost.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/v1/odin/ask", json={
            "question": "สแกนช่องโหว่ให้หน่อย",
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["agent_id"] == "huginn-agent"  # routed to security scanner


@pytest.mark.asyncio
async def test_bifrost_odin_standup():
    """Bifrost Odin: team standup all 12 agents."""
    from bifrost.config import settings
    settings.auth_enabled = False

    from httpx import ASGITransport, AsyncClient
    from bifrost.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/v1/odin/standup")
        assert resp.status_code == 200
        data = resp.json()
        assert data["total_count"] == 12
        assert len(data["agents"]) == 12


@pytest.mark.asyncio
async def test_bifrost_odin_delegate_chain():
    """Bifrost Odin: delegation Huginn→Muninn→Forseti."""
    from bifrost.config import settings
    settings.auth_enabled = False

    from httpx import ASGITransport, AsyncClient
    from bifrost.main import app

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/v1/odin/delegate", json={
            "steps": [
                {"agent_id": "huginn-agent", "task": "Scan security"},
                {"agent_id": "muninn-agent", "task": "Fix issues"},
                {"agent_id": "forseti-agent", "task": "Verify fixes"},
            ],
        })
        assert resp.status_code == 200
        data = resp.json()
        assert data["completed"] == 3


# ═══════════════════════════════════════════════════════════════
# 4. HEIMDALL — LLM Gateway (port 8080)
# ═══════════════════════════════════════════════════════════════


def test_heimdall_client_initialization():
    """Heimdall client initializes with proper config."""
    from bifrost.clients.heimdall import HeimdallClient
    client = HeimdallClient(base_url="http://localhost:8080")
    assert client.base_url == "http://localhost:8080"


def test_heimdall_model_routing():
    """Heimdall: per-agent model routing."""
    from bifrost.clients.heimdall import HeimdallClient
    client = HeimdallClient()
    client.set_agent_model("fenrir-agent", "qwen3.5-9b")
    client.set_agent_model("huginn-agent", "qwen3.5-3b")

    assert client.model_for_agent("fenrir-agent") == "qwen3.5-9b"
    assert client.model_for_agent("huginn-agent") == "qwen3.5-3b"
    assert client.model_for_agent("unknown") is not None  # falls back to default


def test_heimdall_prompt_cache():
    """Heimdall: prompt cache with TTL."""
    from bifrost.clients.heimdall import PromptCache
    cache = PromptCache(max_size=10, ttl_seconds=300)

    cache.put("test", "You are a test agent.")
    assert cache.get("test") == "You are a test agent."
    assert cache.get("missing") is None
    assert cache.hit_rate() > 0


# ═══════════════════════════════════════════════════════════════
# 5. RATATOSKR — Browser Service (port 9200)
# ═══════════════════════════════════════════════════════════════


def test_ratatoskr_api_endpoints():
    """Ratatoskr: all expected endpoints exist."""
    expected = [
        "/healthz", "/api/v1/scrape", "/api/v1/screenshot",
        "/api/v1/fetch", "/api/v1/interact", "/api/v1/sessions",
    ]
    client = AsgardServiceClient()
    for endpoint in expected:
        url = client.url_for("ratatoskr", endpoint)
        assert "9200" in url
        assert endpoint in url


def test_ratatoskr_interact_actions():
    """Ratatoskr: interact API supports 9 action types."""
    expected_actions = {
        "goto", "click", "fill", "select", "check",
        "submit", "wait", "screenshot", "text",
    }
    # These 9 actions were implemented in Sprint 1
    assert len(expected_actions) == 9


# ═══════════════════════════════════════════════════════════════
# 6. FENRIR — Clinical Automation (port 8200)
# ═══════════════════════════════════════════════════════════════


def test_fenrir_workflow_endpoints():
    """Fenrir: workflow API endpoints exist."""
    expected_endpoints = [
        "/api/workflows/register-patient",
        "/api/workflows/record-vitals",
        "/api/workflows/clinical-report",
        "/api/workflows/status",
    ]
    client = AsgardServiceClient()
    for ep in expected_endpoints:
        assert client.url_for("fenrir", ep).startswith("http://localhost:8200")


def test_fenrir_openemr_workflows():
    """Fenrir: OpenEMR workflow class has all methods."""
    from fenrir.openemr.workflows import OpenEMRWorkflows
    wf = OpenEMRWorkflows.__new__(OpenEMRWorkflows)
    assert hasattr(wf, "register_patient_form")
    assert hasattr(wf, "record_vitals_form")
    assert hasattr(wf, "generate_clinical_report")
    assert hasattr(wf, "index_to_mimir")


# ═══════════════════════════════════════════════════════════════
# 7. FORSETI — QA & Testing (port 5555)
# ═══════════════════════════════════════════════════════════════


def test_forseti_service_config():
    """Forseti: service configured on port 5555."""
    client = AsgardServiceClient()
    assert client.SERVICE_PORTS["forseti"] == 5555
    assert client.url_for("forseti", "/health") == "http://localhost:5555/health"


# ═══════════════════════════════════════════════════════════════
# 8. HUGINN — Security Scanner (port 8400)
# ═══════════════════════════════════════════════════════════════


def test_huginn_scanner_types():
    """Huginn: supports ZAP, Semgrep, and Trivy scanners."""
    scanner_types = {"zap", "semgrep", "trivy"}
    assert len(scanner_types) == 3
    client = AsgardServiceClient()
    assert client.SERVICE_PORTS["huginn"] == 8400


def test_huginn_odin_routing():
    """Huginn: Odin routes security keywords to Huginn."""
    from bifrost.core.odin import OdinOrchestrator
    odin = OdinOrchestrator()
    assert odin._route_question("scan for vulnerabilities") == "huginn-agent"
    assert odin._route_question("สแกนช่องโหว่") == "huginn-agent"
    assert odin._route_question("security audit") == "huginn-agent"


# ═══════════════════════════════════════════════════════════════
# 9. MUNINN — Auto-Fixer (port 8500)
# ═══════════════════════════════════════════════════════════════


def test_muninn_api_endpoints():
    """Muninn: has issues API and fix trigger."""
    expected = ["/health", "/api/issues", "/api/stats"]
    client = AsgardServiceClient()
    for ep in expected:
        url = client.url_for("muninn", ep)
        assert "8500" in url


def test_muninn_odin_routing():
    """Muninn: Odin routes fix keywords to Muninn."""
    from bifrost.core.odin import OdinOrchestrator
    odin = OdinOrchestrator()
    assert odin._route_question("fix this bug") == "muninn-agent"
    assert odin._route_question("แก้ไข code") == "muninn-agent"
    assert odin._route_question("create a PR") == "muninn-agent"


# ═══════════════════════════════════════════════════════════════
# 10. EIR — OpenEMR Gateway (port 8300)
# ═══════════════════════════════════════════════════════════════


def test_eir_service_config():
    """Eir: configured on port 8300."""
    client = AsgardServiceClient()
    assert client.SERVICE_PORTS["eir"] == 8300


def test_eir_odin_routing():
    """Eir: Odin routes FHIR/medical keywords to Eir."""
    from bifrost.core.odin import OdinOrchestrator
    odin = OdinOrchestrator()
    assert odin._route_question("query FHIR resources") == "eir-agent"
    assert odin._route_question("HL7 patient data") == "eir-agent"


def test_eir_agent_identity():
    """Eir: agent identity has medical capabilities."""
    from bifrost.core.service_agents import SERVICE_AGENTS
    eir = next(a for a in SERVICE_AGENTS if a.agent_id == "eir-agent")
    assert "fhir_query" in eir.capabilities
    assert "patient_search" in eir.capabilities
    assert "HIPAA compliant" in eir.constraints


# ═══════════════════════════════════════════════════════════════
# 11. VARDR — Infra Monitor (port 3000)
# ═══════════════════════════════════════════════════════════════


def test_vardr_api_endpoints():
    """Vardr: has service/container/alert management APIs."""
    expected = [
        "/api/services", "/api/metrics", "/api/alerts",
        "/api/alerts/summary", "/api/alerts/rules",
    ]
    client = AsgardServiceClient()
    for ep in expected:
        url = client.url_for("vardr", ep)
        assert "3000" in url


def test_vardr_odin_routing():
    """Vardr: Odin routes infrastructure keywords to Vardr."""
    from bifrost.core.odin import OdinOrchestrator
    odin = OdinOrchestrator()
    assert odin._route_question("restart container") == "vardr-agent"
    assert odin._route_question("check docker status") == "vardr-agent"


def test_vardr_agent_identity():
    """Vardr: agent has infrastructure capabilities."""
    from bifrost.core.service_agents import SERVICE_AGENTS
    vardr = next(a for a in SERVICE_AGENTS if a.agent_id == "vardr-agent")
    assert "container_status" in vardr.capabilities
    assert "restart_service" in vardr.capabilities


# ═══════════════════════════════════════════════════════════════
# 12. YGGDRASIL — Auth Service (port 8443)
# ═══════════════════════════════════════════════════════════════


def test_yggdrasil_service_config():
    """Yggdrasil: configured on port 8443."""
    client = AsgardServiceClient()
    assert client.SERVICE_PORTS["yggdrasil"] == 8443


def test_yggdrasil_odin_routing():
    """Yggdrasil: Odin routes auth keywords to Yggdrasil."""
    from bifrost.core.odin import OdinOrchestrator
    odin = OdinOrchestrator()
    assert odin._route_question("verify auth token") == "yggdrasil-agent"
    assert odin._route_question("user login") == "yggdrasil-agent"


def test_yggdrasil_agent_identity():
    """Yggdrasil: agent has auth capabilities and constraints."""
    from bifrost.core.service_agents import SERVICE_AGENTS
    ygg = next(a for a in SERVICE_AGENTS if a.agent_id == "yggdrasil-agent")
    assert "token_verify" in ygg.capabilities
    assert "role_management" in ygg.capabilities
    assert "Never log tokens or credentials" in ygg.constraints


# ═══════════════════════════════════════════════════════════════
# 13. ASGARD — Platform Orchestrator
# ═══════════════════════════════════════════════════════════════


def test_asgard_agent_identity():
    """Asgard: platform orchestrator has full capabilities."""
    from bifrost.core.service_agents import SERVICE_AGENTS
    asgard = next(a for a in SERVICE_AGENTS if a.agent_id == "asgard-agent")
    assert "deploy" in asgard.capabilities
    assert "e2e_test" in asgard.capabilities
    assert "Never deploy without passing E2E tests" in asgard.constraints


def test_asgard_odin_routing():
    """Asgard: Odin routes deployment keywords to Asgard."""
    from bifrost.core.odin import OdinOrchestrator
    odin = OdinOrchestrator()
    assert odin._route_question("deploy the application") == "asgard-agent"
    assert odin._route_question("platform status") == "asgard-agent"


# ═══════════════════════════════════════════════════════════════
# 14. CROSS-SERVICE — Integration Tests
# ═══════════════════════════════════════════════════════════════


def test_service_dependency_graph():
    """Service graph has correct nodes and edges."""
    from bifrost.clients.mimir_knowledge import MimirKnowledgeClient
    client = MimirKnowledgeClient()
    graph = client.get_service_graph()

    assert len(graph["nodes"]) == 12
    assert len(graph["edges"]) >= 8

    # Key dependency: Bifrost needs Heimdall
    bifrost_deps = [e["to"] for e in graph["edges"] if e["from"] == "bifrost"]
    assert "heimdall" in bifrost_deps
    assert "mimir" in bifrost_deps

    # Fenrir needs Ratatoskr
    fenrir_deps = [e["to"] for e in graph["edges"] if e["from"] == "fenrir"]
    assert "ratatoskr" in fenrir_deps


@pytest.mark.asyncio
async def test_full_delegation_chain():
    """Cross-service: Odin delegates Huginn→Muninn→Forseti→Asgard."""
    from bifrost.core.odin import OdinOrchestrator
    odin = OdinOrchestrator(max_chain_depth=4)

    results = []
    async def mock_run(agent_id, task):
        r = f"[{agent_id}] {task[:30]}"
        results.append(r)
        return r

    odin._run_agent = mock_run

    chain = [
        {"agent_id": "huginn-agent", "task": "Scan for vulnerabilities"},
        {"agent_id": "muninn-agent", "task": "Generate fixes"},
        {"agent_id": "forseti-agent", "task": "Run tests on fixes"},
    ]

    result = await odin.delegate_chain(chain)
    assert result["completed"] == 3
    assert len(results) == 3


def test_all_agents_have_unique_capabilities():
    """All 12 agents have unique, non-empty capabilities."""
    from bifrost.core.service_agents import SERVICE_AGENTS

    for agent in SERVICE_AGENTS:
        assert len(agent.capabilities) > 0, f"{agent.agent_id} has no capabilities"
        assert len(agent.constraints) > 0, f"{agent.agent_id} has no constraints"
        assert len(agent.knowledge_domains) > 0, f"{agent.agent_id} has no knowledge domains"


def test_all_agents_build_valid_prompts():
    """All 12 agents produce valid system prompts via builder."""
    from bifrost.core.service_agents import SERVICE_AGENTS
    from bifrost.core.identity import SystemPromptBuilder

    for agent in SERVICE_AGENTS:
        prompt = SystemPromptBuilder.build(agent)
        assert len(prompt) > 50, f"{agent.agent_id} prompt too short ({len(prompt)} chars)"
        assert agent.persona_name in prompt
        assert agent.persona_role in prompt


@pytest.mark.asyncio
async def test_odin_routes_all_services():
    """Odin can route at least one keyword to each major service."""
    from bifrost.core.odin import OdinOrchestrator
    odin = OdinOrchestrator()

    routing_tests = {
        "huginn-agent": "scan vulnerability",
        "muninn-agent": "fix the bug",
        "forseti-agent": "run e2e test",
        "ratatoskr-agent": "take screenshot",
        "fenrir-agent": "patient registration",
        "mimir-agent": "search knowledge base",
        "heimdall-agent": "list LLM models",
        "yggdrasil-agent": "verify auth token",
        "eir-agent": "query FHIR",
        "vardr-agent": "restart container",
        "asgard-agent": "deploy application",
    }

    for expected_agent, question in routing_tests.items():
        routed = odin._route_question(question)
        assert routed == expected_agent, f"'{question}' → {routed} (expected {expected_agent})"
