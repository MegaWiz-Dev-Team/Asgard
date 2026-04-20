import requests

base_url = "http://localhost:30000/api/v1/agents"
headers = {"X-Tenant-ID": "a25c0e42-f8a0-430f-93c6-adee5e981981", "Content-Type": "application/json"}

services = [
    {"name": "mimir_agent", "display": "Mimir (App Backend)"},
    {"name": "bifrost_agent", "display": "Bifrost (Swarm Engine)"},
    {"name": "fenrir_agent", "display": "Fenrir (CI/CD Automator)"},
    {"name": "vardr_agent", "display": "Vardr (Observability)"},
    {"name": "forseti_agent", "display": "Forseti (Testing & QA)"},
    {"name": "huginn_agent", "display": "Huginn (Security Scanner)"},
    {"name": "muninn_agent", "display": "Muninn (Auto-Fixer)"},
    {"name": "ratatoskr_agent", "display": "Ratatoskr (Headless Browser)"},
    {"name": "mjolnir_agent", "display": "Mjolnir (Load Tester)"},
    {"name": "heimdall_agent", "display": "Heimdall (LLM Gateway)"},
    {"name": "yggdrasil_agent", "display": "Yggdrasil (Identity & Access)"},
    {"name": "wazuh_agent", "display": "Wazuh (SIEM & Defense)"},
    {"name": "eir_agent", "display": "Eir (Medical System)"}
]

sub_agent_names = []

for s in services:
    svc_key = s["name"].replace("_agent", "")
    mcp_url = f"http://hermodr-{svc_key}.asgard.svc:8090/mcp"
    
    payload = {
        "name": s["name"],
        "display_name": s["display"],
        "system_prompt": f"You are the {s['display']} sub-agent. Utilize your specific MCP tools to fulfill requests delegated to you by Odin.",
        "model_id": "gemini-3-flash-preview",
        "provider": "google",
        "mcp_servers": [mcp_url],
        "is_published": True
    }
    resp = requests.post(base_url, headers=headers, json=payload)
    print(f"Created {s['name']}: {resp.status_code}")
    sub_agent_names.append(s["name"])

odin_payload = {
    "name": "odin_orchestrator",
    "display_name": "Odin (Global Orchestrator)",
    "system_prompt": "You are Odin, the Allfather and Chief Orchestrator of the Asgard AI Platform. You govern a full swarm of specialized sub-agents. Delegate sub-agent tools effectively to accomplish the overarching user goal.",
    "model_id": "gemini-3-flash-preview",
    "provider": "google",
    "tools": sub_agent_names,
    "is_published": True
}
resp_odin = requests.post(base_url, headers=headers, json=odin_payload)
print(f"Created Odin orchestrator: {resp_odin.status_code}")
