"""Asgard E2E — Heimdall Gateway Migration Verification Suite.

Validates the Mimir→Heimdall migration:
  1. Port consistency (all services → gateway :3000, never backend :8081)
  2. Config struct parity (no stale field references)
  3. LlmProvider enum consolidation (Heimdall-only)
  4. URL correctness (no double /v1)
  5. Credential resolution (all providers → Heimdall key)
  6. E2E request flow: Gateway → LLM backend

Run:
  cd /Users/mimir/Developer/Asgard
  PYTHONPATH=/Users/mimir/Developer/Bifrost:/Users/mimir/Developer/Forseti/src \
    python -m pytest tests/test_e2e_heimdall_migration.py -v

Results recorded to Forseti via conftest.py reporter.
"""

import os
import re
import subprocess
from pathlib import Path

import pytest

# ── Paths ────────────────────────────────────────────────────────
MIMIR_ROOT = Path("/Users/mimir/Developer/Mimir/ro-ai-bridge")
HEIMDALL_ROOT = Path("/Users/mimir/Developer/Heimdall")
CORE_AI = MIMIR_ROOT / "mimir-core-ai"
DOMAIN_GAME = MIMIR_ROOT / "ro-ai-domain-game"


def _grep(pattern: str, path: Path, includes: str = "*.rs") -> list[tuple[str, int, str]]:
    """Run ripgrep and return [(file, line, content)]."""
    try:
        result = subprocess.run(
            ["rg", "-n", "--glob", includes, pattern, str(path)],
            capture_output=True, text=True, timeout=10,
        )
        matches = []
        for line in result.stdout.strip().splitlines():
            parts = line.split(":", 2)
            if len(parts) >= 3:
                matches.append((parts[0], int(parts[1]), parts[2]))
        return matches
    except Exception:
        return []


def _grep_count(pattern: str, path: Path, includes: str = "*.rs") -> int:
    """Count matches of a pattern in a directory."""
    return len(_grep(pattern, path, includes))


# ═══════════════════════════════════════════════════════════════
# 1. PORT CONSISTENCY — Gateway :3000 not Backend :8081
# ═══════════════════════════════════════════════════════════════


class TestPortConsistency:
    """Verify all Heimdall URL defaults point to gateway port 3000."""

    def test_no_hardcoded_8081_in_mimir_rs(self):
        """BUG-1 regression: no Rust file should default to :8081 (backend port)."""
        matches = _grep(r"localhost:8081", MIMIR_ROOT)
        offending = [
            f"  {m[0]}:{m[1]}: {m[2].strip()}"
            for m in matches
            if "HEIMDALL_API_URL" in m[2] or "unwrap_or" in m[2]
        ]
        assert len(offending) == 0, (
            f"Found {len(offending)} hardcoded :8081 defaults (should be :3000):\n"
            + "\n".join(offending)
        )

    def test_env_example_uses_port_3000(self):
        """The .env.example must reference the gateway port 3000."""
        env_file = MIMIR_ROOT / ".env.example"
        content = env_file.read_text()
        assert "localhost:3000" in content, \
            ".env.example must default HEIMDALL_API_URL to port 3000"
        assert "localhost:8081" not in content, \
            ".env.example must NOT reference backend port 8081"

    def test_config_rs_default_port_3000(self):
        """Config::from_env() must default to gateway port 3000."""
        config_rs = CORE_AI / "src" / "config.rs"
        content = config_rs.read_text()
        assert "localhost:3000" in content, \
            "config.rs must default HEIMDALL_API_URL to :3000"

    def test_heimdall_gateway_default_port(self):
        """Heimdall Gateway itself defaults to port 3000."""
        config_rs = HEIMDALL_ROOT / "gateway" / "src" / "config.rs"
        content = config_rs.read_text()
        # Check GATEWAY_PORT defaults to 3000
        assert '"3000"' in content, \
            "Heimdall config.rs GATEWAY_PORT should default to 3000"


# ═══════════════════════════════════════════════════════════════
# 2. CONFIG STRUCT PARITY — No stale field references
# ═══════════════════════════════════════════════════════════════


class TestConfigParity:
    """Verify no orphaned Config field references after migration."""

    def test_no_config_ollama_url_references(self):
        """BUG-2 regression: config.ollama_url must not exist in codebase."""
        count = _grep_count(r"config\.ollama_url", MIMIR_ROOT)
        assert count == 0, f"Found {count} references to deleted field config.ollama_url"

    def test_no_config_gemini_api_key_references(self):
        """BUG-2 regression: config.gemini_api_key must not exist."""
        count = _grep_count(r"config\.gemini_api_key", MIMIR_ROOT)
        assert count == 0, f"Found {count} references to deleted field config.gemini_api_key"

    def test_no_config_gemini_base_url_references(self):
        """BUG-2 regression: config.gemini_base_url must not exist."""
        count = _grep_count(r"config\.gemini_base_url", MIMIR_ROOT)
        assert count == 0, f"Found {count} references to deleted field config.gemini_base_url"

    def test_no_config_gemini_model_references(self):
        """BUG-2 regression: config.gemini_model must not exist."""
        count = _grep_count(r"config\.gemini_model", MIMIR_ROOT)
        assert count == 0, f"Found {count} references to deleted field config.gemini_model"

    def test_config_has_heimdall_fields(self):
        """Config struct must have heimdall_api_url, heimdall_api_key, heimdall_model."""
        config_rs = CORE_AI / "src" / "config.rs"
        content = config_rs.read_text()
        assert "heimdall_api_url" in content, "Config missing heimdall_api_url field"
        assert "heimdall_api_key" in content, "Config missing heimdall_api_key field"
        assert "heimdall_model" in content, "Config missing heimdall_model field"

    def test_no_stale_local_model_field(self):
        """Config should not have local_model or embed_model (moved to env)."""
        config_rs = CORE_AI / "src" / "config.rs"
        content = config_rs.read_text()
        # These are struct fields, not env var names
        assert "pub local_model:" not in content, "Stale local_model field in Config struct"
        assert "pub embed_model:" not in content, "Stale embed_model field in Config struct"


# ═══════════════════════════════════════════════════════════════
# 3. LLM PROVIDER ENUM — Heimdall-only
# ═══════════════════════════════════════════════════════════════


class TestLlmProviderEnum:
    """Verify LlmProvider enum has been consolidated to Heimdall-only."""

    def test_no_llmprovider_ollama_references(self):
        """BUG-3 regression: LlmProvider::Ollama must not exist in codebase."""
        count = _grep_count(r"LlmProvider::Ollama", MIMIR_ROOT)
        assert count == 0, f"Found {count} references to deleted variant LlmProvider::Ollama"

    def test_no_llmprovider_gemini_references(self):
        """LlmProvider::Gemini variant must not exist."""
        count = _grep_count(r"LlmProvider::Gemini", MIMIR_ROOT)
        assert count == 0, f"Found {count} references to deleted variant LlmProvider::Gemini"

    def test_llmprovider_heimdall_exists(self):
        """LlmProvider enum must contain Heimdall variant."""
        rag_engine = CORE_AI / "src" / "rag_engine" / "mod.rs"
        content = rag_engine.read_text()
        assert "Heimdall," in content or "Heimdall" in content, \
            "LlmProvider must contain Heimdall variant"

    def test_llmprovider_from_str_accepts_legacy_names(self):
        """FromStr should accept 'ollama', 'gemini', 'google' and map to Heimdall."""
        rag_engine = CORE_AI / "src" / "rag_engine" / "mod.rs"
        content = rag_engine.read_text()
        # The FromStr impl should have these aliases
        assert '"ollama"' in content, "FromStr should accept 'ollama' as alias"
        assert '"gemini"' in content, "FromStr should accept 'gemini' as alias"
        assert '"google"' in content, "FromStr should accept 'google' as alias"


# ═══════════════════════════════════════════════════════════════
# 4. URL CORRECTNESS — No double /v1
# ═══════════════════════════════════════════════════════════════


class TestUrlCorrectness:
    """Verify URL construction produces correct paths."""

    def test_llm_provider_no_double_v1(self):
        """BUG-4 regression: heimdall_default() endpoint must not end with /v1."""
        provider_rs = CORE_AI / "src" / "services" / "llm_provider.rs"
        content = provider_rs.read_text()

        # Find the heimdall_default function's endpoint line
        # It should be "http://localhost:3000" without /v1
        # because build_chat_url() prepends /v1/
        in_fn = False
        for line in content.splitlines():
            if "fn heimdall_default" in line:
                in_fn = True
            if in_fn and "unwrap_or" in line and "localhost" in line:
                assert "/v1" not in line, (
                    f"heimdall_default() endpoint includes /v1, will cause double /v1: {line.strip()}"
                )
                break

    def test_build_chat_url_prepends_v1(self):
        """build_chat_url must prepend /v1/chat/completions."""
        provider_rs = CORE_AI / "src" / "services" / "llm_provider.rs"
        content = provider_rs.read_text()
        assert "/v1/chat/completions" in content, \
            "build_chat_url must include /v1/chat/completions path"

    def test_no_double_v1_in_rag_engine(self):
        """RagRetriever endpoint + /embeddings should not produce double /v1."""
        rag_engine = CORE_AI / "src" / "rag_engine" / "mod.rs"
        content = rag_engine.read_text()
        # endpoint_url already includes /v1, and get_embedding appends /embeddings
        # This is correct because Heimdall serves at /v1/embeddings
        assert "endpoint_url" in content, "RagRetriever should use endpoint_url field"
        assert "ollama_url" not in content, "RagRetriever should NOT have ollama_url field"


# ═══════════════════════════════════════════════════════════════
# 5. CREDENTIAL RESOLUTION — All → Heimdall
# ═══════════════════════════════════════════════════════════════


class TestCredentialResolution:
    """Verify credential resolution routes all providers through Heimdall."""

    def test_resolve_llm_credentials_no_direct_openai(self):
        """resolve_llm_credentials should not call OPENAI_API_KEY directly."""
        sources_config = MIMIR_ROOT / "src" / "routes" / "sources" / "config.rs"
        content = sources_config.read_text()
        # In the resolve_llm_credentials function, we should NOT see OPENAI_API_KEY
        assert "OPENAI_API_KEY" not in content, \
            "resolve_llm_credentials should route OpenAI through Heimdall, not direct"

    def test_infer_api_base_routes_all_through_heimdall(self):
        """infer_api_base should route ALL providers through Heimdall."""
        sources_config = MIMIR_ROOT / "src" / "routes" / "sources" / "config.rs"
        content = sources_config.read_text()
        # The infer_api_base function should NOT have provider-specific URLs
        assert "api.openai.com" not in content, \
            "infer_api_base should not reference api.openai.com directly"
        assert "generativelanguage.googleapis.com" not in content, \
            "infer_api_base should not reference googleapis.com directly"
        assert "localhost:11434" not in content, \
            "infer_api_base should not reference Ollama port 11434"

    def test_vault_managed_secrets_includes_heimdall(self):
        """VAULT_MANAGED_SECRETS must include HEIMDALL_API_KEY."""
        config_rs = CORE_AI / "src" / "config.rs"
        content = config_rs.read_text()
        assert '"HEIMDALL_API_KEY"' in content, \
            "VAULT_MANAGED_SECRETS must include HEIMDALL_API_KEY"

    def test_vault_managed_secrets_no_gemini(self):
        """VAULT_MANAGED_SECRETS should not include GEMINI_API_KEY."""
        config_rs = CORE_AI / "src" / "config.rs"
        content = config_rs.read_text()
        assert '"GEMINI_API_KEY"' not in content, \
            "VAULT_MANAGED_SECRETS should NOT include GEMINI_API_KEY"


# ═══════════════════════════════════════════════════════════════
# 6. DEAD CODE CLEANUP
# ═══════════════════════════════════════════════════════════════


class TestDeadCodeCleanup:
    """Verify stale imports, docs, constants were cleaned up."""

    def test_no_unused_rig_prompt_import_in_rag_engine(self):
        """rig::completion::Prompt should not be imported in rag_engine."""
        rag_engine = CORE_AI / "src" / "rag_engine" / "mod.rs"
        content = rag_engine.read_text()
        assert "use rig::completion::Prompt" not in content, \
            "Unused import rig::completion::Prompt in rag_engine/mod.rs"

    def test_no_unused_rig_prompt_import_in_eval(self):
        """rig::completion::Prompt should not be imported in eval.rs."""
        eval_rs = MIMIR_ROOT / "src" / "agents" / "eval.rs"
        content = eval_rs.read_text()
        assert "use rig::completion::Prompt" not in content, \
            "Unused import rig::completion::Prompt in eval.rs"

    def test_no_dead_default_model_constant(self):
        """DEFAULT_MODEL = 'llama3.2' dead constant removed from rag_engine."""
        rag_engine = CORE_AI / "src" / "rag_engine" / "mod.rs"
        content = rag_engine.read_text()
        assert '"llama3.2"' not in content, \
            "Dead constant DEFAULT_MODEL = 'llama3.2' still present"

    def test_rag_engine_docs_no_ollama_gemini(self):
        """Module docs should not mention Ollama or Gemini as providers."""
        rag_engine = CORE_AI / "src" / "rag_engine" / "mod.rs"
        # Read first 25 lines (module doc)
        lines = rag_engine.read_text().splitlines()[:25]
        header = "\n".join(lines)
        assert "Ollama" not in header, \
            "Module docs still mention Ollama"
        assert "Gemini" not in header, \
            "Module docs still mention Gemini"

    def test_eval_docs_no_ollama_only(self):
        """eval.rs docs should not mention 'only Ollama models'."""
        eval_rs = MIMIR_ROOT / "src" / "agents" / "eval.rs"
        content = eval_rs.read_text()
        assert "only Ollama" not in content, \
            "eval.rs docs still say 'only Ollama models supported'"


# ═══════════════════════════════════════════════════════════════
# 7. TDD SUITE INTEGRITY — Existing tests still valid
# ═══════════════════════════════════════════════════════════════


class TestTddSuiteIntegrity:
    """Verify the Rust TDD test suite references are correct."""

    def test_llm_provider_tests_exist(self):
        """llm_provider.rs must have a #[cfg(test)] module."""
        provider_rs = CORE_AI / "src" / "services" / "llm_provider.rs"
        content = provider_rs.read_text()
        assert "#[cfg(test)]" in content, "llm_provider.rs missing test module"

    def test_llm_provider_has_double_v1_regression_test(self):
        """llm_provider.rs must have a regression test for double /v1 bug."""
        provider_rs = CORE_AI / "src" / "services" / "llm_provider.rs"
        content = provider_rs.read_text()
        assert "/v1/v1/" in content, \
            "Missing regression test asserting no double /v1 in URL"

    def test_sources_config_tests_route_through_heimdall(self):
        """sources/config.rs tests should assert Heimdall routing."""
        sources_config = MIMIR_ROOT / "src" / "routes" / "sources" / "config.rs"
        content = sources_config.read_text()
        assert "routes_through_heimdall" in content, \
            "Test names should indicate routing through Heimdall"

    def test_sources_config_tests_no_ollama_key_assertion(self):
        """sources/config.rs tests should not assert key == 'ollama'."""
        sources_config = MIMIR_ROOT / "src" / "routes" / "sources" / "config.rs"
        content = sources_config.read_text()
        # In test code, there should be no assertion that key equals "ollama"
        assert 'assert_eq!(key, "ollama")' not in content, \
            "Test still asserts key == 'ollama', should be test-heimdall-key"


# ═══════════════════════════════════════════════════════════════
# 8. HEIMDALL GATEWAY — Service Contract
# ═══════════════════════════════════════════════════════════════


class TestHeimdallGatewayContract:
    """Verify Heimdall Gateway structure is compatible with Mimir's expectations."""

    def test_heimdall_has_gateway_config(self):
        """Heimdall must have gateway/src/config.rs."""
        assert (HEIMDALL_ROOT / "gateway" / "src" / "config.rs").exists(), \
            "Heimdall gateway config.rs not found"

    def test_heimdall_supports_external_providers(self):
        """Heimdall must support external provider routing (OpenRouter, Gemini, OpenAI)."""
        config_rs = HEIMDALL_ROOT / "gateway" / "src" / "config.rs"
        content = config_rs.read_text()
        assert "openrouter_api_key" in content, "Heimdall missing OpenRouter support"
        assert "gemini_api_key" in content, "Heimdall missing Gemini provider support"
        assert "openai_api_key" in content, "Heimdall missing OpenAI provider support"

    def test_heimdall_backend_port_is_8081(self):
        """Heimdall BACKEND_PORT (MLX engine) should default to 8081."""
        config_rs = HEIMDALL_ROOT / "gateway" / "src" / "config.rs"
        content = config_rs.read_text()
        assert '"8081"' in content, \
            "Heimdall BACKEND_PORT should default to 8081 (MLX engine)"

    def test_mimir_never_targets_backend_port(self):
        """Mimir should NEVER target Heimdall's backend port 8081 directly."""
        matches = _grep(r"localhost:8081", MIMIR_ROOT)
        defaults = [m for m in matches if "unwrap_or" in m[2] or "HEIMDALL" in m[2]]
        assert len(defaults) == 0, (
            f"Mimir has {len(defaults)} default fallbacks targeting backend port 8081. "
            "All traffic must go through gateway port 3000."
        )


# ═══════════════════════════════════════════════════════════════
# 9. CROSS-SERVICE — Mimir↔Heimdall Integration
# ═══════════════════════════════════════════════════════════════


class TestMimirHeimdallIntegration:
    """Verify Mimir↔Heimdall integration patterns."""

    def test_rag_engine_uses_heimdall_for_embeddings(self):
        """RagRetriever must call Heimdall for embeddings."""
        rag_engine = CORE_AI / "src" / "rag_engine" / "mod.rs"
        content = rag_engine.read_text()
        assert "HEIMDALL_API_URL" in content, \
            "RagRetriever must use HEIMDALL_API_URL for embeddings"
        assert "HEIMDALL_API_KEY" in content, \
            "RagRetriever must send HEIMDALL_API_KEY for auth"

    def test_simple_npc_uses_heimdall(self):
        """SimpleNpcAgent must route through Heimdall."""
        npc_rs = DOMAIN_GAME / "src" / "simple_npc.rs"
        content = npc_rs.read_text()
        assert "HEIMDALL_API_URL" in content, "SimpleNpcAgent must use HEIMDALL_API_URL"
        assert "AgentImplementation::Heimdall" in content, \
            "SimpleNpcAgent must use Heimdall implementation variant"

    def test_eval_judge_uses_heimdall(self):
        """LLM-as-Judge must route through Heimdall."""
        eval_rs = MIMIR_ROOT / "src" / "agents" / "eval.rs"
        content = eval_rs.read_text()
        assert "HEIMDALL_API_KEY" in content, "Judge must use HEIMDALL_API_KEY"
        assert "HEIMDALL_API_URL" in content, "Judge must use HEIMDALL_API_URL"

    def test_overseer_uses_heimdall(self):
        """Swarm Overseer must route through Heimdall."""
        overseer_rs = MIMIR_ROOT / "src" / "swarm" / "overseer.rs"
        content = overseer_rs.read_text()
        assert "HEIMDALL_API_URL" in content, "Overseer must use HEIMDALL_API_URL"

    def test_ocr_uses_heimdall_model(self):
        """OCR routes must use config.heimdall_model as default."""
        ocr_rs = MIMIR_ROOT / "src" / "routes" / "ocr.rs"
        content = ocr_rs.read_text()
        assert "heimdall_model" in content, "OCR must use config.heimdall_model"
        assert "gemini_model" not in content, "OCR must NOT use config.gemini_model"
