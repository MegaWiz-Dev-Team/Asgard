---
description: Stop all Asgard services (Docker + Heimdall)
---

# Stop All Services

## When to use
- Shutting down the entire platform
- Before reboot or system maintenance
- When user says "ปิดทุก service" or "stop all services"

## Steps

// turbo-all

1. **Stop Heimdall** (host processes):
   ```bash
   cd /Users/mimir/Developer/Heimdall && bash ./scripts/stop.sh
   ```

2. **Stop all Docker Compose services**:
   ```bash
   cd /Users/mimir/Developer/Asgard && docker compose --profile full down
   ```

3. **Optionally stop Colima** (to free resources):
   ```bash
   colima stop
   ```

## Notes
- `docker compose down` preserves volumes (data is retained)
- To destroy all data: `docker compose --profile full down -v`
