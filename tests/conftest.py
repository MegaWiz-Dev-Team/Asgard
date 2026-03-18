"""Asgard E2E — pytest conftest with Forseti & Fenrir result reporting.

After all tests complete, results are:
1. Saved to Forseti's ResultsDB (SQLite)
2. Posted to Fenrir's /api/test-results endpoint
3. Printed as a summary table

Usage:
  cd /Users/mimir/Developer/Asgard
  PYTHONPATH=/Users/mimir/Developer/Bifrost:/Users/mimir/Developer/Fenrir:/Users/mimir/Developer/Forseti/src \
    python -m pytest tests/test_e2e_all_services.py -v
"""

import json
import os
import time
import logging
import subprocess
from datetime import datetime
from pathlib import Path

import pytest

# ── Env Isolation ──
# When running from Asgard dir, prevent Bifrost's pydantic Settings
# from loading the Asgard .env (which has extra fields Bifrost rejects).
# We do this by removing the .env file reference BEFORE any bifrost import.
import os
os.environ["BIFROST_ENV_FILE"] = ""  # tell settings to skip .env

# Also remove all known extra env vars that would clash
_EXTRA_VARS = [
    "FENRIR_PORT", "FENRIR_BROWSER_HEADLESS",
    "OPENEMR_PORT", "OPENEMR_MYSQL_PASSWORD", "OPENEMR_ADMIN_PASSWORD",
    "RUST_LOG", "EXTERNAL_MODEL_DIR",
    "SMTP_HOST", "SMTP_PORT", "SMTP_USER", "SMTP_PASSWORD",
    "YGGDRASIL_CLIENT_ID", "YGGDRASIL_CLIENT_SECRET",
    "BIFROST_DEFAULT_MODEL", "BIFROST_MAX_ITERATIONS", "BIFROST_MAX_EXECUTION_TIME",
]
for _var in _EXTRA_VARS:
    os.environ.pop(_var, None)

# Monkeypatch pydantic-settings to skip .env for ALL BaseSettings in this process
try:
    from pydantic_settings import BaseSettings
    _orig_init = BaseSettings.__init__

    def _patched_init(self, **kwargs):
        kwargs.setdefault("_env_file", None)
        _orig_init(self, **kwargs)

    BaseSettings.__init__ = _patched_init
except ImportError:
    pass

logger = logging.getLogger("asgard.e2e")

# ══════════════════════════════════════════
# Forseti Reporter — pytest plugin
# ══════════════════════════════════════════


class ForsetiReporter:
    """Collect per-test results and report to Forseti + Fenrir."""

    def __init__(self):
        self.results: list[dict] = []
        self.start_time = 0.0
        self.passed = 0
        self.failed = 0
        self.errors = 0
        self.skipped = 0

    def pytest_sessionstart(self, session):
        self.start_time = time.time()

    def pytest_runtest_logreport(self, report):
        if report.when == "call":
            entry = {
                "test_id": report.nodeid,
                "name": report.nodeid.split("::")[-1],
                "status": "pass" if report.passed else "fail",
                "duration_ms": int(report.duration * 1000),
            }
            if report.failed:
                entry["error"] = str(report.longrepr)[:500]
                self.failed += 1
            elif report.passed:
                self.passed += 1
            elif report.skipped:
                self.skipped += 1
                entry["status"] = "skip"
            self.results.append(entry)
        elif report.when == "setup" and report.failed:
            self.errors += 1
            self.results.append({
                "test_id": report.nodeid,
                "name": report.nodeid.split("::")[-1],
                "status": "error",
                "error": str(report.longrepr)[:500],
                "duration_ms": 0,
            })

    def pytest_sessionfinish(self, session, exitstatus):
        duration_ms = int((time.time() - self.start_time) * 1000)
        total = self.passed + self.failed + self.errors + self.skipped

        # Get git info
        git_commit = _git_info("rev-parse --short HEAD")
        git_branch = _git_info("rev-parse --abbrev-ref HEAD")

        report = {
            "service": "asgard",
            "test_type": "e2e",
            "suite_name": "E2E All Services",
            "total": total,
            "passed": self.passed,
            "failed": self.failed,
            "errors": self.errors,
            "skipped": self.skipped,
            "duration_ms": duration_ms,
            "git_commit": git_commit,
            "git_branch": git_branch,
            "test_cases": self.results,
            "raw_output": json.dumps(self.results, ensure_ascii=False),
        }

        # 1. Save to Forseti ResultsDB (local SQLite)
        self._save_to_forseti_db(report)

        # 2. Post to Fenrir /api/test-results
        self._post_to_fenrir(report)

        # 3. Save JSON artifact
        self._save_json_artifact(report)

        # 4. Print summary
        self._print_summary(report)

    def _save_to_forseti_db(self, report: dict):
        """Save results to Forseti's SQLite database."""
        try:
            from forseti.db.results_db import ResultsDB
            db = ResultsDB(db_path="/Users/mimir/Developer/Forseti/forseti_results.db")
            run_id = db.save_run(
                suite_name=report["suite_name"],
                phase="e2e",
                base_url="http://localhost",
                total=report["total"],
                passed=report["passed"],
                failed=report["failed"],
                errors=report["errors"],
                skipped=report["skipped"],
                duration_ms=report["duration_ms"],
                project_version="Q2-2026",
                project_commit=report.get("git_commit", "unknown"),
            )
            # Save individual scenarios
            for tc in report["test_cases"]:
                db.save_scenario(
                    run_id=run_id,
                    name=tc["name"],
                    status=tc["status"],
                    duration_ms=tc.get("duration_ms", 0),
                    error_message=tc.get("error", None),
                )
            logger.info(f"📊 Forseti DB: run #{run_id} saved ({report['total']} tests)")
        except Exception as e:
            logger.warning(f"⚠️ Forseti DB save failed (non-fatal): {e}")

    def _post_to_fenrir(self, report: dict):
        """POST results to Fenrir /api/test-results."""
        try:
            import httpx
            fenrir_url = "http://localhost:8200/api/test-results"
            payload = {
                "service": report["service"],
                "test_type": report["test_type"],
                "suite_name": report["suite_name"],
                "total": report["total"],
                "passed": report["passed"],
                "failed": report["failed"],
                "errors": report["errors"],
                "skipped": report["skipped"],
                "duration_ms": report["duration_ms"],
                "git_commit": report.get("git_commit"),
                "git_branch": report.get("git_branch"),
                "test_cases": report["test_cases"],
            }
            resp = httpx.post(fenrir_url, json=payload, timeout=5.0)
            if resp.status_code == 201:
                result_id = resp.json().get("id", "?")
                logger.info(f"📡 Fenrir API: result #{result_id} posted")
            else:
                logger.warning(f"⚠️ Fenrir API: {resp.status_code} {resp.text[:200]}")
        except Exception as e:
            logger.warning(f"⚠️ Fenrir API post failed (non-fatal): {e}")

    def _save_json_artifact(self, report: dict):
        """Save JSON result file to Forseti results directory."""
        try:
            results_dir = Path("/Users/mimir/Developer/Forseti/results")
            results_dir.mkdir(parents=True, exist_ok=True)
            ts = datetime.now().strftime("%Y%m%d_%H%M%S")
            path = results_dir / f"e2e_all_services_{ts}.json"
            with open(path, "w", encoding="utf-8") as f:
                json.dump(report, f, indent=2, ensure_ascii=False)
            logger.info(f"📄 JSON: {path}")
        except Exception as e:
            logger.warning(f"⚠️ JSON save failed: {e}")

    def _print_summary(self, report: dict):
        """Print a nice summary table."""
        total = report["total"]
        passed = report["passed"]
        failed = report["failed"]
        dur = report["duration_ms"]
        rate = (passed / max(total, 1)) * 100

        print("\n" + "═" * 60)
        print("  🏰 ASGARD E2E — All Services Summary")
        print("═" * 60)
        print(f"  Total:   {total}")
        print(f"  Passed:  {passed} ✅")
        print(f"  Failed:  {failed} {'❌' if failed else ''}")
        print(f"  Errors:  {report['errors']}")
        print(f"  Rate:    {rate:.1f}%")
        print(f"  Time:    {dur}ms")
        print(f"  Commit:  {report.get('git_commit', 'N/A')}")
        print("═" * 60)

        # Per-service breakdown
        services_tested = set()
        for tc in report["test_cases"]:
            name = tc["name"]
            for svc in ["mimir", "bifrost", "heimdall", "ratatoskr", "fenrir",
                        "forseti", "huginn", "muninn", "eir", "vardr",
                        "yggdrasil", "asgard", "odin", "service", "cross", "delegation"]:
                if svc in name.lower():
                    services_tested.add(svc)
                    break

        print(f"  Services covered: {len(services_tested)}")
        print("  " + ", ".join(sorted(services_tested)))
        print("═" * 60)

        # Recording destinations
        print("  📊 Results recorded to:")
        print("     • Forseti SQLite DB")
        print("     • Fenrir /api/test-results")
        print("     • Forseti results/ JSON")
        print("═" * 60 + "\n")


def _git_info(cmd: str) -> str:
    """Get git info safely."""
    try:
        return subprocess.check_output(
            f"git {cmd}",
            shell=True,
            cwd="/Users/mimir/Developer/Asgard",
            text=True,
        ).strip()
    except Exception:
        return "unknown"


def pytest_configure(config):
    """Register the ForsetiReporter plugin."""
    reporter = ForsetiReporter()
    config.pluginmanager.register(reporter, "forseti-reporter")
