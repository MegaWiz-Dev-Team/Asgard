#!/usr/bin/env python3
"""asgard-chain-view — Show what the Norse gods say to each other in Odin chat.

Queries the a2a_dispatch_audit table and pretty-prints each A2A chain
(one chain = one Odin conversation that fanned out to other agents).
For every hop it shows:
  - source → target + step number + delivery status
  - Odin's request (message_summary, first 500 chars)
  - target's reply (target_response_text, requires mimir-api v2.3.53+)

Usage:
  ./asgard-chain-view.py                  # last 10 chains
  ./asgard-chain-view.py --latest 20
  ./asgard-chain-view.py --chain <chain_id>
  ./asgard-chain-view.py --since 2026-05-27
"""

import argparse, subprocess, sys
from collections import defaultdict

MARIADB_NS = "asgard-infra"
MARIADB_POD = "mariadb-585d5cd485-fwmjh"  # current pod; rotate when redeployed

# ANSI colors — fall back gracefully on dumb terminals.
class C:
    def __init__(self, isatty):
        self.HDR = "\033[1;35m" if isatty else ""
        self.SRC = "\033[1;36m" if isatty else ""
        self.TGT = "\033[1;33m" if isatty else ""
        self.OK  = "\033[1;32m" if isatty else ""
        self.ERR = "\033[1;31m" if isatty else ""
        self.DIM = "\033[2m"   if isatty else ""
        self.RST = "\033[0m"   if isatty else ""
c = C(sys.stdout.isatty())


def mariadb(sql: str) -> str:
    """Run SQL inside the MariaDB pod, return raw TSV output."""
    cmd = [
        "kubectl", "exec", "-n", MARIADB_NS, MARIADB_POD, "--",
        "sh", "-c", f"mariadb -uroot -proot mimir -B -e \"{sql}\""
    ]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"mariadb query failed: {r.stderr}")
    return r.stdout


def parse_tsv(out: str):
    lines = out.strip().split("\n")
    if len(lines) < 2:
        return []
    headers = lines[0].split("\t")
    rows = []
    for line in lines[1:]:
        parts = line.split("\t")
        if len(parts) == len(headers):
            rows.append(dict(zip(headers, parts)))
    return rows


def fetch_chains(args):
    """Return audit rows; filtered by --chain / --since / --latest."""
    where = []
    if args.chain:
        where.append(f"chain_id = '{args.chain}'")
    if args.since:
        where.append(f"timestamp >= '{args.since}'")
    where_clause = ("WHERE " + " AND ".join(where)) if where else ""

    # Pull all hops for chains that match
    sql = f"""
    SELECT id, chain_id, chain_step,
           source_agent_id, target_agent_id, status,
           IFNULL(message_summary, '') AS message_summary,
           IFNULL(target_response_text, '') AS target_response_text,
           DATE_FORMAT(timestamp, '%Y-%m-%d %H:%i:%s') AS ts,
           IFNULL(error_message, '') AS error_message,
           IFNULL(pii_redaction_applied, 0) AS pii_applied
    FROM a2a_dispatch_audit
    {where_clause}
    ORDER BY chain_id DESC, chain_step ASC
    """.strip().replace("\n", " ")
    rows = parse_tsv(mariadb(sql))

    # Group by chain_id, preserve order
    chains = defaultdict(list)
    chain_order = []
    for r in rows:
        if r["chain_id"] not in chains:
            chain_order.append(r["chain_id"])
        chains[r["chain_id"]].append(r)

    # Limit unless --chain is specific
    if not args.chain:
        chain_order = chain_order[: args.latest]
    return [(cid, chains[cid]) for cid in chain_order]


def truncate(s: str, n: int) -> str:
    s = s.replace("\\n", "\n").rstrip()
    if len(s) > n:
        return s[:n] + f"…[{len(s)-n} more chars]"
    return s


def render_chain(chain_id, hops):
    print(f"\n{c.HDR}═══ Chain {chain_id} ═══════════════════════════════════════{c.RST}")
    print(f"{c.DIM}{len(hops)} hop(s), started {hops[0]['ts']}{c.RST}")
    for h in hops:
        status_color = c.OK if h["status"] == "delivered" else c.ERR
        pii = " 🛡️ PII-redacted" if h["pii_applied"] != "0" else ""
        print()
        print(f"  {c.DIM}[{h['ts']}]{c.RST} "
              f"{c.SRC}{h['source_agent_id']}{c.RST} → "
              f"{c.TGT}{h['target_agent_id']}{c.RST} "
              f"({c.DIM}step {h['chain_step']}{c.RST}, {status_color}{h['status']}{c.RST}){pii}")

        if h["message_summary"]:
            print(f"  {c.DIM}📤 question to {h['target_agent_id']}:{c.RST}")
            for line in truncate(h["message_summary"], 1000).splitlines():
                print(f"     {line}")

        if h["target_response_text"]:
            print(f"  {c.DIM}📥 reply from {h['target_agent_id']}:{c.RST}")
            for line in truncate(h["target_response_text"], 1500).splitlines():
                print(f"     {line}")
        elif h["status"] == "delivered":
            print(f"  {c.DIM}📥 (no response_text — likely from mimir-api < v2.3.53){c.RST}")

        if h["error_message"]:
            print(f"  {c.ERR}❌ error:{c.RST} {h['error_message']}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--latest", type=int, default=10,
        help="how many most-recent chains to show (default 10)")
    ap.add_argument("--chain", type=str, default=None,
        help="show one specific chain_id")
    ap.add_argument("--since", type=str, default=None,
        help="filter to timestamps >= this (YYYY-MM-DD or YYYY-MM-DD HH:MM:SS)")
    args = ap.parse_args()

    chains = fetch_chains(args)
    if not chains:
        print(f"{c.DIM}(no chains matched){c.RST}")
        return

    for cid, hops in chains:
        render_chain(cid, hops)
    print()


if __name__ == "__main__":
    main()