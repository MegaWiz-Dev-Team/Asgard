# Asgard health preflight + watchdog

Host-side health tooling, built after **INC-2026-06-12** (MariaDB PVC stuck
Terminating → cluster-wide outage, undetected for days). It closes the two worst
gaps from that incident: **no detection of infra-invariant violations**, and an
**in-cluster observability path that died with the cluster**.

## Pieces

| File | What it does |
|---|---|
| `asgard-preflight.sh` | Read-only check of the invariants the incident exposed (below). Exit 0/1/2 = OK/WARN/FAIL. `--json` for machines. |
| `asgard-watchdog.sh` | Runs preflight, raises a **debounced** alert into OpenSearch on degradation. Host-side → survives a cluster outage. |
| `launchd/com.asgard.watchdog.plist` | Runs the watchdog every 5 min (staged; not auto-loaded). |

`health.sh` (pre-existing) checks **HTTP liveness** of services; this checks the
**infra invariants** underneath. They are complementary — run both.

## What preflight checks

- **PVC stuck `Terminating`** — the exact root-cause signal of INC-2026-06-12.
- **Pods wedged** — `Pending` / `ImagePullBackOff` / `ErrImageNeverPull` / `CrashLoopBackOff` across `asgard`, `asgard-infra`, `wazuh`.
- **Stateful workloads have a Running pod** (MariaDB) — it had none.
- **Host memory headroom** (`MIN_FREE_GB`, default 8) — kernel-panic guard.
- **Host services** — Heimdall gateway `:8080`, MLX `:8081`.
- **Backup freshness** — newest `*.sql.gz` on T7 within `BACKUP_MAX_AGE_DAYS` (default 3).

## Usage

```bash
./asgard-preflight.sh            # human, before any heavy op
./asgard-preflight.sh --json     # machine
./asgard-watchdog.sh             # one tick (used by launchd)
```

## Enable the watchdog (5-min timer)

```bash
cp /Users/mimir/Developer/Asgard/scripts/launchd/com.asgard.watchdog.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.asgard.watchdog.plist
```

Disable: `launchctl unload ~/Library/LaunchAgents/com.asgard.watchdog.plist`.

## Alerts

Indexed to OpenSearch (`asgard-alerts`, on the Wazuh/Tyr indexer — the component
that survived the outage). Debounced: one alert on **OK→DEGRADED**, a reminder
every `REPEAT_EVERY` ticks (~1h) while degraded, one on **DEGRADED→RECOVERED**.
Local trail in `~/.asgard-watchdog.log`.

```bash
curl -sk -u admin:admin "https://localhost:30920/asgard-alerts/_search?sort=@timestamp:desc&size=5"
```

Tunables (env): `ALERT_THRESHOLD` (2=FAIL only, 1=also WARN), `REPEAT_EVERY`,
`INDEXER_URL/USER/PASS`, `MIN_FREE_GB`, `BACKUP_MAX_AGE_DAYS`.

## Deferred — cluster-side prevention (apply once the cluster is healthy)

These mutate the cluster, so they wait until it recovers:

1. **Kyverno deny-policy** on `DELETE` of PVC/PV labelled `asgard.io/stateful=true`
   — stops the root cause (accidental delete of a live DB's claim) at the door.
2. **Fix `imagePullPolicy: Never`** across the stack — INC-2026-06-12's stack-wide
   `ErrImageNeverPull` came from a lost local image cache that could not be
   re-pulled. Use a local registry or `IfNotPresent` + rebuild-on-boot.
3. **Verify all stateful PVs use `reclaimPolicy: Retain`** (this one did, which is
   why data survived).
