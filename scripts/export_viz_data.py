#!/usr/bin/env python3
"""Export pad_lab_mart tables to viz/public/data for the static dashboard.

Queries BigQuery marts only (never raw/staging). Writes JSON snapshots
committed with the site so GitHub Pages needs no BQ credentials.

Usage:
    python scripts/export_viz_data.py
    python scripts/export_viz_data.py --project my-gcp-project
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date, datetime, timezone
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from loaders.env import load_dotenv  # noqa: E402

OUT_DIR = ROOT / "viz" / "public" / "data"
MART_DATASET = "pad_lab_mart"


def _project(cli: str | None) -> str:
    if cli:
        return cli
    load_dotenv()
    return os.environ.get("GCP_PROJECT") or (
        os.popen("gcloud config get-value project 2>/dev/null").read().strip()
    )


def _json_default(obj: object) -> str | float:
    if isinstance(obj, datetime):
        return obj.isoformat()
    if isinstance(obj, date):
        return obj.isoformat()
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Not JSON serializable: {type(obj)!r}")


def _rows(client, sql: str) -> list[dict]:
    result = client.query(sql).result()
    return [dict(row.items()) for row in result]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", help="GCP project id")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=OUT_DIR,
        help=f"Output directory (default: {OUT_DIR})",
    )
    args = parser.parse_args()

    project = _project(args.project)
    if not project:
        print("ERROR: set GCP_PROJECT or pass --project", file=sys.stderr)
        return 1

    from google.cloud import bigquery

    client = bigquery.Client(project=project)
    out = args.out_dir
    out.mkdir(parents=True, exist_ok=True)

    # Join committee_summary for name/party so export works before or after
    # the enriched daily_contributions columns land via dbt.
    daily_sql = f"""
        SELECT
          CAST(d.contribution_receipt_date AS STRING) AS contribution_receipt_date,
          d.committee_id,
          coalesce(s.committee_name, 'Unknown Committee') AS committee_name,
          s.party,
          s.party_full,
          d.contribution_count,
          d.total_amount,
          d.avg_amount,
          d.unique_states
        FROM `{project}.{MART_DATASET}.daily_contributions` d
        LEFT JOIN `{project}.{MART_DATASET}.committee_summary` s
          USING (committee_id)
        ORDER BY contribution_receipt_date, committee_id
    """
    summary_sql = f"""
        SELECT
          committee_id,
          committee_name,
          party,
          party_full,
          committee_type_full,
          designation_full,
          committee_state,
          total_contributions,
          total_raised,
          avg_contribution,
          min_contribution,
          max_contribution,
          donor_states,
          unique_donors,
          CAST(first_contribution_date AS STRING) AS first_contribution_date,
          CAST(last_contribution_date AS STRING) AS last_contribution_date
        FROM `{project}.{MART_DATASET}.committee_summary`
        ORDER BY total_raised DESC
    """

    print(f"Exporting marts from {project}.{MART_DATASET} …")
    daily = _rows(client, daily_sql)
    summary = _rows(client, summary_sql)

    daily_path = out / "daily_contributions.json"
    summary_path = out / "committee_summary.json"
    meta_path = out / "meta.json"

    daily_path.write_text(
        json.dumps(daily, default=_json_default, indent=2) + "\n"
    )
    summary_path.write_text(
        json.dumps(summary, default=_json_default, indent=2) + "\n"
    )

    dates = [r["contribution_receipt_date"] for r in daily if r.get("contribution_receipt_date")]
    meta = {
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "project": project,
        "dataset": MART_DATASET,
        "daily_contributions_rows": len(daily),
        "committee_summary_rows": len(summary),
        "date_min": min(dates) if dates else None,
        "date_max": max(dates) if dates else None,
        "total_raised": sum(float(r.get("total_raised") or 0) for r in summary),
        "total_contributions": sum(int(r.get("total_contributions") or 0) for r in summary),
    }
    meta_path.write_text(json.dumps(meta, indent=2) + "\n")

    print(f"  wrote {daily_path.relative_to(ROOT)} ({len(daily)} rows)")
    print(f"  wrote {summary_path.relative_to(ROOT)} ({len(summary)} rows)")
    print(f"  wrote {meta_path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
