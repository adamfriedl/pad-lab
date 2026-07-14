#!/usr/bin/env python3
"""Fetch FEC individual contributions -> GCS landing -> BigQuery raw.

Maps to the PAD pipeline: Airbyte syncs vendor data (ActBlue, VAN, etc.)
to GCS, then loads append-only into a partitioned raw table.  dbt handles
cleaning and deduplication downstream.

Usage:
    python -m loaders.load_contributions --max-records 1000 --state OR
    python -m loaders.load_contributions --input-file data/samples/contributions.ndjson
    python -m loaders.load_contributions --dry-run --save-sample
"""

import argparse
import json
import logging
import os
import sys
from datetime import datetime, timezone

from google.cloud import bigquery, storage

from .fec import FECClient

log = logging.getLogger(__name__)

_PROJECT = ""
_BUCKET = ""
_RAW_DATASET = "pad_lab_raw"
_TABLE = "fec_contributions"
_GCS_PREFIX = "landing/contributions"

SCHEMA = [
    bigquery.SchemaField("sub_id", "STRING"),
    bigquery.SchemaField("committee_id", "STRING"),
    bigquery.SchemaField("contributor_name", "STRING"),
    bigquery.SchemaField("contributor_city", "STRING"),
    bigquery.SchemaField("contributor_state", "STRING"),
    bigquery.SchemaField("contributor_zip", "STRING"),
    bigquery.SchemaField("contributor_employer", "STRING"),
    bigquery.SchemaField("contributor_occupation", "STRING"),
    bigquery.SchemaField("contribution_receipt_amount", "FLOAT64"),
    bigquery.SchemaField("contribution_receipt_date", "DATE"),
    bigquery.SchemaField("receipt_type", "STRING"),
    bigquery.SchemaField("memo_text", "STRING"),
    bigquery.SchemaField("is_individual", "BOOLEAN"),
    bigquery.SchemaField("two_year_transaction_period", "INT64"),
    bigquery.SchemaField("entity_type", "STRING"),
    bigquery.SchemaField("_loaded_at", "TIMESTAMP"),
]


def _project() -> str:
    global _PROJECT
    if not _PROJECT:
        _PROJECT = os.environ.get("GCP_PROJECT") or (
            os.popen("gcloud config get-value project 2>/dev/null").read().strip()
        )
    return _PROJECT


def _bucket() -> str:
    global _BUCKET
    if not _BUCKET:
        _BUCKET = f"pad-lab-{_project()}"
    return _BUCKET


def normalize(rec: dict) -> dict | None:
    """Flatten an FEC API record to the raw-table schema.

    Returns None for records missing required fields.
    """
    date_str = rec.get("contribution_receipt_date")
    amount = rec.get("contribution_receipt_amount")
    sub_id = rec.get("sub_id")
    if not date_str or amount is None or not sub_id:
        return None

    return {
        "sub_id": str(sub_id),
        "committee_id": rec.get("committee_id") or "",
        "contributor_name": rec.get("contributor_name") or "",
        "contributor_city": rec.get("contributor_city") or "",
        "contributor_state": rec.get("contributor_state") or "",
        "contributor_zip": rec.get("contributor_zip") or "",
        "contributor_employer": rec.get("contributor_employer") or "",
        "contributor_occupation": rec.get("contributor_occupation") or "",
        "contribution_receipt_amount": float(amount),
        "contribution_receipt_date": date_str,
        "receipt_type": rec.get("receipt_type") or "",
        "memo_text": (rec.get("memo_text") or "")[:1024],
        "is_individual": bool(rec.get("is_individual", True)),
        "two_year_transaction_period": int(
            rec.get("two_year_transaction_period") or 0
        ),
        "entity_type": rec.get("entity_type") or "",
        "_loaded_at": datetime.now(timezone.utc).isoformat(),
    }


def upload_to_gcs(records: list[dict]) -> str:
    """Write NDJSON to the GCS landing zone. Returns gs:// URI."""
    client = storage.Client(project=_project())
    bucket = client.bucket(_bucket())
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")
    blob_path = f"{_GCS_PREFIX}/{ts}.ndjson"
    blob = bucket.blob(blob_path)

    payload = "\n".join(json.dumps(r) for r in records)
    blob.upload_from_string(payload, content_type="application/json")

    uri = f"gs://{_bucket()}/{blob_path}"
    log.info("Uploaded %d records -> %s", len(records), uri)
    return uri


def load_to_bigquery(gcs_uri: str) -> int:
    """Load NDJSON from GCS into the partitioned raw table."""
    client = bigquery.Client(project=_project())
    table_ref = f"{_project()}.{_RAW_DATASET}.{_TABLE}"

    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        schema=SCHEMA,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        time_partitioning=bigquery.TimePartitioning(
            field="contribution_receipt_date",
            type_=bigquery.TimePartitioningType.DAY,
        ),
    )

    job = client.load_table_from_uri(gcs_uri, table_ref, job_config=job_config)
    job.result()
    log.info("Loaded %d rows -> %s", job.output_rows, table_ref)
    return job.output_rows or 0


def _print_summary(records: list[dict]) -> None:
    amounts = [r["contribution_receipt_amount"] for r in records]
    states = {r["contributor_state"] for r in records if r["contributor_state"]}
    committees = {r["committee_id"] for r in records if r["committee_id"]}
    print(f"  Records:      {len(records):,}")
    print(f"  Committees:   {len(committees):,}")
    print(f"  States:       {len(states):,}")
    print(f"  Total:        ${sum(amounts):,.2f}")
    if amounts:
        print(f"  Avg:          ${sum(amounts) / len(amounts):,.2f}")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Fetch FEC contributions and load to BigQuery"
    )
    parser.add_argument("--max-records", type=int, default=1000)
    parser.add_argument("--state", help="Contributor state filter (e.g. OR)")
    parser.add_argument(
        "--cycle",
        type=int,
        default=2024,
        help="FEC two-year transaction period",
    )
    parser.add_argument(
        "--min-amount",
        type=int,
        help="Minimum contribution amount in dollars",
    )
    parser.add_argument(
        "--input-file",
        help="Load from cached NDJSON instead of FEC API",
    )
    parser.add_argument(
        "--save-sample",
        action="store_true",
        help="Save fetched data to data/samples/",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate only — skip GCS/BQ load",
    )
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(levelname)s  %(message)s")

    # ---- fetch or load from cache ----------------------------------------
    if args.input_file:
        log.info("Loading cached data from %s", args.input_file)
        with open(args.input_file) as f:
            records = [json.loads(line) for line in f if line.strip()]
    else:
        fec = FECClient()
        log.info(
            "Fetching contributions (cycle=%d, max=%d)…",
            args.cycle,
            args.max_records,
        )
        raw = fec.fetch_contributions(
            two_year_transaction_period=args.cycle,
            contributor_state=args.state,
            min_amount=args.min_amount,
            max_records=args.max_records,
        )
        log.info("API returned %d records", len(raw))
        records = [r for r in (normalize(rec) for rec in raw) if r is not None]
        log.info("Normalized to %d valid records", len(records))

    if not records:
        log.error("No records to load")
        sys.exit(1)

    # ---- optional sample cache -------------------------------------------
    if args.save_sample:
        os.makedirs("data/samples", exist_ok=True)
        path = "data/samples/contributions.ndjson"
        with open(path, "w") as f:
            for r in records:
                f.write(json.dumps(r) + "\n")
        log.info("Saved %d records -> %s", len(records), path)

    # ---- summary ---------------------------------------------------------
    _print_summary(records)

    if args.dry_run:
        log.info("Dry run complete — skipped GCS/BQ load")
        return

    # ---- load pipeline: local -> GCS -> BQ --------------------------------
    gcs_uri = upload_to_gcs(records)
    rows = load_to_bigquery(gcs_uri)
    print(f"\n  loaded {rows:,} rows to {_project()}.{_RAW_DATASET}.{_TABLE}")


if __name__ == "__main__":
    main()
