#!/usr/bin/env python3
"""Compare a private Convex CLI snapshot directory with the legacy export.

Usage: python3 scripts/e2e/legacy-export-parity.py <snapshot-dir> <output.json>
Snapshots: npx convex data <table> --limit 10000 --format json > <table>-snapshot.json
The report contains counts and field names, never names, emails, or guest proofs.
This verifies the saved export, not the current Supabase database.
"""
import json
import sys
from collections import Counter
from pathlib import Path

snapshot_dir = Path(sys.argv[1])
export_dir = Path(__file__).resolve().parents[1] / "migration" / "exports"
tables = ["users", "player_stats", "custom_roles_configs", "player_groups"]
snapshots = {t: json.loads((snapshot_dir / f"{t}-snapshot.json").read_text()) for t in tables}
users = {r["legacy_supabase_user_id"]: r for r in snapshots["users"] if "legacy_supabase_user_id" in r}
report = {}
for table in tables:
    source = json.loads((export_dir / f"{table}.json").read_text())
    key = "legacy_supabase_user_id" if table == "users" else "legacy_supabase_id"
    live_rows = [r for r in snapshots[table] if key in r]
    ids = Counter(r[key] for r in live_rows)
    live = {r[key]: r for r in live_rows}
    mismatches = Counter()
    missing = 0
    owner_errors = 0
    changed_timestamps = 0
    for row in source:
        target = live.get(row[key])
        if not target:
            missing += 1
            continue
        for field, value in row.items():
            if field == "updated_at":
                # Ingest and legitimate account claims update this timestamp.
                changed_timestamps += target.get(field) != value
                continue
            if field == "email" and table == "users" and target.get("auth_subject"):
                # A Clerk-claimed row may have acquired a verified email.
                continue
            if target.get(field) != value:
                mismatches[field] += 1
        if table != "users":
            owner = users.get(row["legacy_supabase_user_id"])
            if not owner or target.get("user_id") != owner["id"]:
                owner_errors += 1
    report[table] = {
        "export_count": len(source), "legacy_convex_count": len(live_rows),
        "total_convex_count": len(snapshots[table]), "missing_rows": missing,
        "duplicate_legacy_ids": sum(c > 1 for c in ids.values()),
        "field_mismatches": dict(mismatches), "owner_mapping_errors": owner_errors,
        "updated_at_differences": changed_timestamps,
    }
Path(sys.argv[2]).write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
sys.exit(int(any(r["missing_rows"] or r["duplicate_legacy_ids"] or r["field_mismatches"] or r["owner_mapping_errors"] or r["export_count"] != r["legacy_convex_count"] for r in report.values())))
