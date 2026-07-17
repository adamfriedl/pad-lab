#!/usr/bin/env python3
"""Fetch FEC committee records -> BigQuery raw (direct load).

Committees are a dimension table — small, loaded directly to BQ without
a GCS landing step.  In production this might be a dbt seed or a
lightweight API sync rather than a full Airbyte pipeline.

Usage:
    python -m loaders.load_committees --from-contributions
    python -m loaders.load_committees --cycle 2024 --max-records 200
    python -m loaders.load_committees --input-file data/samples/committees.ndjson
"""

import argparse
import json
import logging
import os
import sys
from datetime import datetime, timedelta, timezone

from google.cloud import bigquery
from google.cloud.exceptions import NotFound

from .fec import FECClient

log = logging.getLogger(__name__)

_PROJECT = ""
_RAW_DATASET = "pad_lab_raw"
_TABLE = "fec_committees"
_CONTRIB_TABLE = "fec_contributions"
_REFRESH_AFTER = timedelta(days=7)

SCHEMA = [
    bigquery.SchemaField("committee_id", "STRING"),
    bigquery.SchemaField("name", "STRING"),
    bigquery.SchemaField("party", "STRING"),
    bigquery.SchemaField("party_full", "STRING"),
    bigquery.SchemaField("state", "STRING"),
    bigquery.SchemaField("designation", "STRING"),
    bigquery.SchemaField("designation_full", "STRING"),
    bigquery.SchemaField("committee_type", "STRING"),
    bigquery.SchemaField("committee_type_full", "STRING"),
    bigquery.SchemaField("treasurer_name", "STRING"),
    bigquery.SchemaField("first_file_date", "DATE"),
    bigquery.SchemaField("_loaded_at", "TIMESTAMP"),
]


def _project() -> str:
    global _PROJECT
    if not _PROJECT:
        _PROJECT = os.environ.get("GCP_PROJECT") or (
            os.popen("gcloud config get-value project 2>/dev/null").read().strip()
        )
    return _PROJECT


def normalize(rec: dict) -> dict | None:
    """Flatten an FEC API committee record to BQ schema."""
    cid = rec.get("committee_id")
    if not cid:
        return None
    return {
        "committee_id": cid,
        "name": rec.get("name") or "",
        "party": rec.get("party") or "",
        "party_full": rec.get("party_full") or "",
        "state": rec.get("state") or "",
        "designation": rec.get("designation") or "",
        "designation_full": rec.get("designation_full") or "",
        "committee_type": rec.get("committee_type") or "",
        "committee_type_full": rec.get("committee_type_full") or "",
        "treasurer_name": rec.get("treasurer_name") or "",
        "first_file_date": rec.get("first_file_date") or None,
        "_loaded_at": datetime.now(timezone.utc).isoformat(),
    }


def _committee_ids_from_bq() -> list[str]:
    """Read distinct committee_ids referenced in the contributions table."""
    client = bigquery.Client(project=_project())
    query = f"""
        SELECT DISTINCT committee_id
        FROM `{_project()}.{_RAW_DATASET}.{_CONTRIB_TABLE}`
        WHERE committee_id IS NOT NULL AND committee_id != ''
    """
    return [row.committee_id for row in client.query(query).result()]


def _as_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _existing_committees() -> tuple[set[str], datetime | None]:
    """Return committee IDs already in raw and the most recent load time."""
    client = bigquery.Client(project=_project())
    table_ref = f"{_project()}.{_RAW_DATASET}.{_TABLE}"
    try:
        client.get_table(table_ref)
    except NotFound:
        return set(), None

    query = f"""
        SELECT committee_id, MAX(_loaded_at) AS loaded_at
        FROM `{table_ref}`
        WHERE committee_id IS NOT NULL AND committee_id != ''
        GROUP BY committee_id
    """
    rows = list(client.query(query).result())
    if not rows:
        return set(), None
    existing = {row.committee_id for row in rows}
    max_loaded_at = max(_as_utc(row.loaded_at) for row in rows)
    return existing, max_loaded_at


def _ids_to_fetch(needed: set[str]) -> tuple[list[str], str]:
    """Choose delta vs full refresh based on what's loaded and how stale it is."""
    existing, max_loaded_at = _existing_committees()
    now = datetime.now(timezone.utc)

    if max_loaded_at is None:
        return sorted(needed), "full refresh (no existing data)"

    age = now - max_loaded_at
    if age > _REFRESH_AFTER:
        return sorted(needed), f"full refresh (last load {age.days}d ago)"

    delta = needed - existing
    if not delta:
        return [], "up to date"
    return sorted(delta), f"delta ({len(delta)} new of {len(needed)} needed)"


def load_to_bigquery(records: list[dict], *, append: bool = False) -> int:
    """Load committee records directly to BigQuery."""
    client = bigquery.Client(project=_project())
    table_ref = f"{_project()}.{_RAW_DATASET}.{_TABLE}"

    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        schema=SCHEMA,
        write_disposition=(
            bigquery.WriteDisposition.WRITE_APPEND
            if append
            else bigquery.WriteDisposition.WRITE_TRUNCATE
        ),
    )

    job = client.load_table_from_json(records, table_ref, job_config=job_config)
    job.result()
    log.info("Loaded %d rows -> %s", job.output_rows, table_ref)
    return job.output_rows or 0


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Fetch FEC committees and load to BigQuery"
    )
    parser.add_argument("--cycle", type=int, default=2024)
    parser.add_argument("--max-records", type=int, default=500)
    parser.add_argument(
        "--from-contributions",
        action="store_true",
        help="Fetch only committees present in the loaded contributions table",
    )
    parser.add_argument(
        "--input-file",
        help="Load from cached NDJSON instead of FEC API",
    )
    parser.add_argument("--save-sample", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s  %(message)s")

    # ---- fetch or load from cache ----------------------------------------
    append_to_bq = False
    if args.input_file:
        log.info("Loading cached data from %s", args.input_file)
        with open(args.input_file) as f:
            records = [json.loads(line) for line in f if line.strip()]
    elif args.from_contributions:
        needed = set(_committee_ids_from_bq())
        log.info("Found %d committee IDs in contributions table", len(needed))
        if not needed:
            log.error("No committees found — load contributions first")
            sys.exit(1)

        ids, mode = _ids_to_fetch(needed)
        log.info("Committee sync: %s", mode)
        if not ids:
            log.info("Skipping FEC fetch and BQ load")
            return

        fec = FECClient()
        raw = fec.fetch_committees(committee_ids=ids)
        records = [r for r in (normalize(rec) for rec in raw) if r is not None]
        append_to_bq = True
    else:
        fec = FECClient()
        log.info(
            "Fetching committees (cycle=%d, max=%d)…",
            args.cycle,
            args.max_records,
        )
        raw = fec.fetch_committees(cycle=args.cycle, max_records=args.max_records)
        records = [r for r in (normalize(rec) for rec in raw) if r is not None]

    log.info("Normalized %d committee records", len(records))
    if not records:
        log.error("No records to load")
        sys.exit(1)

    # ---- optional sample cache -------------------------------------------
    if args.save_sample:
        os.makedirs("data/samples", exist_ok=True)
        path = "data/samples/committees.ndjson"
        with open(path, "w") as f:
            for r in records:
                f.write(json.dumps(r) + "\n")
        log.info("Saved %d records -> %s", len(records), path)

    # ---- summary ---------------------------------------------------------
    parties: dict[str, int] = {}
    for r in records:
        p = r.get("party") or "Unknown"
        parties[p] = parties.get(p, 0) + 1
    print(f"  Committees: {len(records):,}")
    for party, count in sorted(parties.items(), key=lambda x: -x[1])[:5]:
        print(f"    {party}: {count}")

    if args.dry_run:
        log.info("Dry run complete")
        return

    # ---- load to BQ (direct, no GCS — dimension tables are small) --------
    rows = load_to_bigquery(records, append=append_to_bq)
    print(
        f"\n  loaded {rows:,} committees to "
        f"{_project()}.{_RAW_DATASET}.{_TABLE}"
    )


if __name__ == "__main__":
    main()
