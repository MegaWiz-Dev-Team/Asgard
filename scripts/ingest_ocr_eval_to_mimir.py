#!/usr/bin/env python3
"""Push OCR eval dataset + bench results into Mimir.

Usage:
    # 1) Register/refresh the dataset (idempotent on name+version):
    python ingest_to_mimir.py dataset \\
        --name medical_certs_v1 \\
        --source real_partner \\
        --csv /Users/mimir/Developer/Syn/data/TestimageRawText.csv \\
        --image-dir /Users/mimir/Developer/Syn/data/images

    # 2) Push a bench run's results (auto-creates dataset rows if missing):
    python ingest_to_mimir.py run \\
        --dataset medical_certs_v1 \\
        --prompt-label field-targeted \\
        --result-json bench-out/fielded-20260513T023600Z.json

DB connection: uses the host-port-forward MariaDB via NodePort 30306 by
default (override with MIMIR_DB_URL). Auto-falls-back to in-cluster
`mariadb.asgard-infra.svc` via `kubectl port-forward` IF you ran one.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
import uuid
from datetime import datetime
from pathlib import Path

import mysql.connector  # pip install mysql-connector-python


def db_connect() -> "mysql.connector.MySQLConnection":
    url = os.environ.get("MIMIR_DB_URL")
    if not url:
        raise SystemExit(
            "Set MIMIR_DB_URL=mysql://user:pass@host:port/db, e.g.\n"
            "  kubectl port-forward -n asgard-infra svc/mariadb 33306:3306\n"
            "  MIMIR_DB_URL=mysql://mimir:<pass>@127.0.0.1:33306/mimir python ingest_to_mimir.py ..."
        )
    m = re.match(r"mysql://([^:]+):([^@]+)@([^:/]+):(\d+)/(.+)", url)
    if not m:
        raise SystemExit(f"Bad MIMIR_DB_URL: {url}")
    user, pw, host, port, db = m.groups()
    return mysql.connector.connect(host=host, port=int(port), user=user,
                                    password=pw, database=db,
                                    charset="utf8mb4", autocommit=False)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def cmd_dataset(args: argparse.Namespace) -> int:
    csv_path = Path(args.csv)
    image_dir = Path(args.image_dir)
    if not csv_path.exists():
        raise SystemExit(f"CSV not found: {csv_path}")
    if not image_dir.exists():
        raise SystemExit(f"Image dir not found: {image_dir}")

    with csv_path.open(encoding="utf-8") as f:
        gt_rows = list(csv.DictReader(f))
    print(f"Read {len(gt_rows)} ground-truth rows from CSV")

    # Match cases to image files (case_id.{jpg,png,gif,pdf})
    image_index = {}
    for p in image_dir.iterdir():
        if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".gif", ".pdf"}:
            image_index[p.stem] = p

    cases = []
    for row in gt_rows:
        cid = row["test_id"]
        img = image_index.get(cid)
        if not img:
            continue  # silently skip GT rows without an image (10 vs 30 in this dataset)
        cases.append({
            "case_id": cid,
            "image_path": str(img.resolve()),
            "image_sha256": sha256_file(img),
            "image_format": img.suffix.lower().lstrip("."),
            "ground_truth": row.get("raw_text", "").strip(),
            "pii_types": json.dumps(
                [t.strip() for t in (row.get("pii_types") or "").split(",")
                 if t.strip() and t.strip() != "-"],
                ensure_ascii=False),
            "doc_type": "medical_cert",
        })
    print(f"Matched {len(cases)} cases to images in {image_dir.name}/")

    conn = db_connect()
    cur = conn.cursor()
    try:
        # Upsert dataset row
        cur.execute("""SELECT id, version FROM ocr_eval_datasets
                       WHERE tenant_id=%s AND name=%s
                       ORDER BY version DESC LIMIT 1""",
                    (args.tenant, args.name))
        row = cur.fetchone()
        if row and not args.bump_version:
            ds_id, version = row
            print(f"Dataset {args.name} v{version} already exists ({ds_id}); refreshing cases.")
        else:
            ds_id = str(uuid.uuid4())
            version = (row[1] + 1) if (row and args.bump_version) else 1
            cur.execute("""INSERT INTO ocr_eval_datasets
                           (id, tenant_id, name, version, source, description,
                            image_count, gt_source_path)
                           VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
                        (ds_id, args.tenant, args.name, version, args.source,
                         args.description, len(cases), str(csv_path)))
            print(f"Created dataset {args.name} v{version} ({ds_id})")

        # Refresh image_count + clear-and-reinsert cases (idempotent)
        cur.execute("""UPDATE ocr_eval_datasets
                       SET image_count=%s, gt_source_path=%s
                       WHERE id=%s""", (len(cases), str(csv_path), ds_id))
        cur.execute("DELETE FROM ocr_eval_cases WHERE dataset_id=%s", (ds_id,))
        for case in cases:
            cur.execute("""INSERT INTO ocr_eval_cases
                           (id, dataset_id, case_id, image_path, image_sha256,
                            image_format, ground_truth, gt_chars, pii_types, doc_type)
                           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                        (str(uuid.uuid4()), ds_id, case["case_id"],
                         case["image_path"], case["image_sha256"],
                         case["image_format"], case["ground_truth"],
                         len(case["ground_truth"]), case["pii_types"],
                         case["doc_type"]))
        conn.commit()
        print(f"✅ Dataset {args.name} v{version} has {len(cases)} cases.")
        print(f"   dataset_id={ds_id}")
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    json_path = Path(args.result_json)
    rows = json.loads(json_path.read_text(encoding="utf-8"))
    if not rows:
        raise SystemExit(f"{json_path} is empty")

    conn = db_connect()
    cur = conn.cursor(dictionary=True)
    try:
        # Look up dataset (latest version unless --version)
        if args.version:
            cur.execute("""SELECT id FROM ocr_eval_datasets
                           WHERE tenant_id=%s AND name=%s AND version=%s""",
                        (args.tenant, args.dataset, args.version))
        else:
            cur.execute("""SELECT id FROM ocr_eval_datasets
                           WHERE tenant_id=%s AND name=%s
                           ORDER BY version DESC LIMIT 1""",
                        (args.tenant, args.dataset))
        ds_row = cur.fetchone()
        if not ds_row:
            raise SystemExit(f"Dataset {args.dataset} not found — register it first via `dataset`")
        ds_id = ds_row["id"]

        # case_id (external) → cases.id (UUID)
        cur.execute("""SELECT id, case_id FROM ocr_eval_cases
                       WHERE dataset_id=%s""", (ds_id,))
        case_map = {r["case_id"]: r["id"] for r in cur.fetchall()}

        engines = sorted({r["engine"] for r in rows})
        run_id = str(uuid.uuid4())
        cur.execute("""INSERT INTO ocr_eval_runs
                       (id, dataset_id, tenant_id, name, prompt_label,
                        system_prompt, user_prompt, engines, metadata, notes)
                       VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (run_id, ds_id, args.tenant, args.run_name or json_path.stem,
                     args.prompt_label, args.system_prompt, args.user_prompt,
                     json.dumps(engines), json.dumps({"source_json": str(json_path)}),
                     args.notes))
        print(f"Created run {run_id} ({len(rows)} result rows, engines={engines})")

        # Insert results
        inserted = skipped = 0
        for r in rows:
            cid = case_map.get(r["id"])
            if not cid:
                skipped += 1
                continue
            cur.execute("""INSERT INTO ocr_eval_results
                           (id, run_id, case_id, engine, status, cer, wer,
                            wall_ms, prompt_tokens, completion_tokens,
                            extracted_text, extracted_chars, error)
                           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                        (str(uuid.uuid4()), run_id, cid, r["engine"],
                         r.get("status", "ok"),
                         r.get("cer"), r.get("wer"), r.get("wall_ms"),
                         r.get("prompt_tokens"), r.get("completion_tokens"),
                         r.get("extracted"), r.get("extracted_len"),
                         r.get("error")))
            inserted += 1
        cur.execute("UPDATE ocr_eval_runs SET finished_at=NOW() WHERE id=%s", (run_id,))
        conn.commit()
        print(f"✅ {inserted} results inserted, {skipped} skipped (no matching case)")
        print(f"   run_id={run_id}")
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()
    return 0


def main() -> int:
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)

    pd = sub.add_parser("dataset", help="Register or refresh an OCR eval dataset.")
    pd.add_argument("--tenant", default="default_tenant")
    pd.add_argument("--name", required=True)
    pd.add_argument("--source", default="real_partner",
                    choices=["real_partner", "synthetic", "scraped", "mixed"])
    pd.add_argument("--description", default=None)
    pd.add_argument("--csv", required=True)
    pd.add_argument("--image-dir", required=True)
    pd.add_argument("--bump-version", action="store_true",
                    help="Force-create a new version row instead of refreshing the latest")
    pd.set_defaults(func=cmd_dataset)

    pr = sub.add_parser("run", help="Ingest results from a bench JSON.")
    pr.add_argument("--tenant", default="default_tenant")
    pr.add_argument("--dataset", required=True, help="Dataset name (latest version unless --version)")
    pr.add_argument("--version", type=int)
    pr.add_argument("--prompt-label", required=True,
                    help="Tag for the prompt variant, e.g. generic-all-text | field-targeted")
    pr.add_argument("--system-prompt", default=None)
    pr.add_argument("--user-prompt", default=None)
    pr.add_argument("--run-name", default=None)
    pr.add_argument("--notes", default=None)
    pr.add_argument("--result-json", required=True)
    pr.set_defaults(func=cmd_run)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
