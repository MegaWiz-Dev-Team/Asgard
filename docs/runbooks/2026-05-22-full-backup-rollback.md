# Full Backup & Rollback of the Asgard Stack to External SSD

> **Internal runbook / engineering blog** — 2026-05-22
> Status: validated on the dev Mac mini (OrbStack K8s). Tool: `Asgard/scripts/backup-full-k8s.sh`
> Audience: anyone who needs to take a complete, restorable snapshot of every datastore on a single-box Asgard deployment.

## Why

Asgard runs **one box per customer** — every database and persistent volume lives on a single Mac mini's OrbStack K8s cluster. Before risky operations (migrations, upgrades, key rotations) we want a **rollback point**: a single timestamped folder on the T7 external SSD from which any datastore can be restored.

The old `scripts/backup.sh` was written for the docker-compose era and called container names like `asgard_neo4j` that no longer exist under K8s — so **Neo4j had silently never been backed up**. This runbook documents the K8s-aware replacement and the gotchas we hit.

## What gets backed up

| Layer | Stores | Method |
|-------|--------|--------|
| SQL | MariaDB ×3 (asgard / asgard-infra / mimir-docker), PostgreSQL ×3 (Zitadel, infra, Laminar) | **online logical dump** (`mariadb-dump`, `pg_dumpall`) |
| Graph | Neo4j (PrimeKG: ~129k nodes / 8.1M edges) | **offline binary dump** (scale-to-zero + helper pod) |
| Vector | Qdrant ×2 namespaces (12 collections) | snapshot API via port-forward |
| Analytics | ClickHouse (Laminar / heimdall-trace) | raw tar (live) |
| Queue | RabbitMQ | definitions export |
| Object / file PVs | MinIO, Quickwit, eir-sites, forseti, mjolnir, mimir-medical-docs | raw tar |
| Cluster | PVC/PV defs + per-namespace manifests + Helm releases | `kubectl get -o yaml` |

Layout on disk:

```
/Volumes/T7 Shield/asgard-backup-<DATE>/
├── 01-databases/   logical dumps + neo4j.dump + clickhouse tar
├── 02-snapshots/   qdrant snapshots per collection
├── 03-pv-raw/      raw PV tars
├── 04-k8s/         manifests + PVC/PV definitions
├── 05-vault/       MANUAL.md (+ raft snapshot if available)
└── MANIFEST.md     results table + restore order
```

## The three gotchas (why a naive backup fails)

1. **Neo4j is Community edition.** `STOP DATABASE` / `START DATABASE` are Enterprise-only ("Unsupported administration command"), and `neo4j-admin database dump` refuses to run while the store is in use. The fix: scale the deployment to **0**, launch a helper pod that mounts the same (RWO) `neo4j-data` PVC, dump there, copy the file out, delete the helper, scale back to **1**. Cost: ~1.5 min of Neo4j downtime.
2. **`mysqldump` doesn't exist** in the `mariadb:11` image — the binary is `mariadb-dump` (no symlink). Calling `mysqldump` fails with exit 127 and writes an empty gzip.
3. **MinIO is a distroless image** — no `tar`, no shell. Same scale-to-zero + Alpine-helper-pod trick as Neo4j.

Bonus: ClickHouse's raw tar exits non-zero ("file changed as we read it") because it's taken live — but the gzip is still valid. Verify with `gzip -t`, not the exit code.

## Disk space

**The backup itself:** ~**6.7 GB** total (first full run). Breakdown of the big rocks:

| Artifact | Size | Share |
|----------|------|-------|
| ClickHouse tar | 4.0 GB | 60% |
| Qdrant `pubmed-abstracts` (infra) | 1.1 GB | 16% |
| Qdrant `primekg-entities` | 623 MB | 9% |
| Quickwit tar | 356 MB | 5% |
| **Neo4j dump** | **213 MB** | 3% |
| PostgreSQL (infra) | 104 MB | — |
| everything else (MariaDB, MinIO, app PVs, manifests) | < 100 MB | — |

- **T7 external:** had ~1.1 TB free → backup uses < 1% of it. Keep ~10–15 GB headroom per run.
- **Host disk (the real constraint):** the OrbStack VM lives on the host data volume. Logical dumps stream straight to T7, but the **Neo4j dump writes a transient `neo4j.dump` (~200 MB) inside the helper pod first**, and any host-side staging eats local disk. Before this run the host was at **97% (13 GB free)** and had already triggered a `DiskPressure` eviction storm. We reclaimed **~132 GB** first:
  - Rust `target/` dirs across ~/Developer → **~75 GB** (rebuildable, never belongs in a backup)
  - A stray `Heimdall/{{HOME}}/` directory (an un-expanded template var in a launchd plist had been dumping HuggingFace models into a literal `{{HOME}}` folder) → **57 GB** (duplicate of the real `~/.cache/huggingface`)
  - Result: 13 GB → **145 GB free**. **Always check host disk before backing up.**

## Time

End-to-end on a warm, cleaned cluster: **~10–12 minutes**, almost entirely ClickHouse.

| Phase | Duration | Notes |
|-------|----------|-------|
| All SQL logical dumps | ~15 s | online, no downtime |
| Qdrant snapshots (12 collections) | ~30 s | the 1.1 GB collection dominates |
| **ClickHouse raw tar** | **~6.5 min** | the bottleneck — 4 GB |
| RabbitMQ + raw PV tars + manifests | ~20 s | |
| Neo4j (scale-0 → dump → scale-1) | ~2 min | dump itself is 3 s for 1.38 GiB; the rest is pod teardown/spin-up |
| MinIO (scale-0 → tar → scale-1) | ~2.5 min | MinIO took ~2 min to report Ready again |

**Service downtime during a backup:**
- Neo4j: **~1.5 min** (graph queries fail in this window — coordinate with anything calling `/resolve`)
- MinIO: **~2.5 min** (object storage unavailable)
- Everything else: **0** (online dumps)

## Restoring (rollback)

See `MANIFEST.md` in each backup folder for the exact order. The shape:

1. Recreate/keep the cluster, apply `04-k8s/` manifests + **fresh** PVCs (don't restore `local-path` PV node-affinity).
2. MariaDB: `gunzip -c X.sql.gz | mysql -uroot -p`
3. PostgreSQL: `gunzip -c X.sql.gz | psql -U postgres`
4. Neo4j: scale 0 → helper pod → `neo4j-admin database load neo4j --from-path=<dir> --overwrite-destination` → scale 1
5. Qdrant: snapshot upload + recovery API per collection
6. ClickHouse / Quickwit / MinIO / app PVs: scale 0 → helper pod → extract tar into fresh PVC → scale up

## Portability caveat (moving to another box)

The **data** dumps are portable across machines (same major versions: Neo4j 5.x, MariaDB 11, compatible Qdrant/ClickHouse). But this backup is **secrets-free by design**, so a target box will not have a working *auth* layer unless you also carry, out-of-band:

- **Vault** unseal keys / root token (not in the backup at all)
- **Zitadel master key** + RS256 JWT signing keys — encrypted columns won't decrypt and SSO breaks if these differ
- **App-level encryption keys** (rotated API keys, OpenEMR CryptoGen) — needed to read encrypted columns

→ For a *content* clone (RAG corpus, PrimeKG graph, vectors, documents): just import the dumps. For a *full system* clone with login intact: dumps **+** a separate secrets bundle.

## Run it

```bash
./scripts/backup-full-k8s.sh                  # → /Volumes/T7 Shield/asgard-backup-<DATE>/
DEST=/some/other/path ./scripts/backup-full-k8s.sh
```

Every step is fault-tolerant: a failed component is logged and recorded in the manifest, never aborting the rest of the run. Check host disk first; expect ~7–12 min and ~7 GB.
