#!/usr/bin/env python3
"""Fetch FEC individual contributions -> GCS landing -> BigQuery raw.

Maps to the PAD pipeline: Airbyte syncs vendor data (ActBlue, VAN, etc.)
to GCS, then loads append-only into a partitioned raw table.  dbt handles
cleaning and deduplication downstream.

Usage:
    python -m loaders.load_contributions --max-records 10000 --state OR
    python -m loaders.load_contributions --since-watermark --lookback-days 7
    python -m loaders.load_contributions --min-date 2024-06-01 --max-date 2024-06-30
    python -m loaders.load_contributions --input-file data/samples/contributions.ndjson
    python -m loaders.load_contributions --dry-run --save-sample
"""

import argparse
import json
import logging
import os
import sys
from collections import Counter
from datetime import date, datetime, timedelta, timezone

from google.cloud import bigquery, storage
from google.cloud.exceptions import NotFound

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


def _parse_date(value: str) -> date:
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            f"invalid date {value!r} — use YYYY-MM-DD"
        ) from exc


def _max_receipt_date_from_bq() -> date | None:
    """Latest contribution_receipt_date in raw, or None if table missing/empty."""
    client = bigquery.Client(project=_project())
    table_ref = f"{_project()}.{_RAW_DATASET}.{_TABLE}"
    try:
        client.get_table(table_ref)
    except NotFound:
        return None

    query = f"""
        SELECT MAX(contribution_receipt_date) AS max_date
        FROM `{table_ref}`
    """
    rows = list(client.query(query).result())
    if not rows or rows[0].max_date is None:
        return None
    max_date = rows[0].max_date
    if isinstance(max_date, datetime):
        return max_date.date()
    return max_date


def _bootstrap_min_date(cycle: int) -> date:
    """First day of the FEC two-year transaction period (e.g. 2023-01-01 for cycle 2024)."""
    return date(cycle - 1, 1, 1)


def _watermark_min_date(lookback_days: int) -> tuple[date | None, str]:
    """Compute min_date from raw high-water mark minus lookback overlap."""
    max_date = _max_receipt_date_from_bq()
    if max_date is None:
        return None, "bootstrap (no existing raw data)"

    min_date = max_date - timedelta(days=lookback_days)
    return (
        min_date,
        f"watermark max={max_date} lookback={lookback_days}d -> min={min_date}",
    )


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


def _warn_date_concentration(records: list[dict]) -> None:
    if not records:
        return
    by_date = Counter(r["contribution_receipt_date"] for r in records)
    peak_date, peak_count = by_date.most_common(1)[0]
    share = peak_count / len(records)
    if share < 0.5:
        return
    peak_amount = sum(
        r["contribution_receipt_amount"]
        for r in records
        if r["contribution_receipt_date"] == peak_date
    )
    log.warning(
        "%d%% of records (%d/%d, $%s) share receipt date %s. "
        "FEC year-end filings often use 12/31; if this dominates the time "
        "series, re-bootstrap with a fresh fetch (sort=-contribution_receipt_date).",
        round(share * 100),
        peak_count,
        len(records),
        f"{peak_amount:,.0f}",
        peak_date,
    )


def _print_summary(records: list[dict]) -> None:
    amounts = [r["contribution_receipt_amount"] for r in records]
    states = {r["contributor_state"] for r in records if r["contributor_state"]}
    committees = {r["committee_id"] for r in records if r["committee_id"]}
    dates = sorted({r["contribution_receipt_date"] for r in records})
    print(f"  Records:      {len(records):,}")
    print(f"  Committees:   {len(committees):,}")
    print(f"  States:       {len(states):,}")
    if dates:
        print(f"  Date span:    {dates[0]} – {dates[-1]} ({len(dates)} days)")
    print(f"  Total:        ${sum(amounts):,.2f}")
    if amounts:
        print(f"  Avg:          ${sum(amounts) / len(amounts):,.2f}")
    _warn_date_concentration(records)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        description="Fetch FEC contributions and load to BigQuery"
    )
    parser.add_argument("--max-records", type=int, default=10000)
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
        "--min-date",
        type=_parse_date,
        help="Earliest contribution_receipt_date (YYYY-MM-DD)",
    )
    parser.add_argument(
        "--max-date",
        type=_parse_date,
        help="Latest contribution_receipt_date (YYYY-MM-DD)",
    )
    parser.add_argument(
        "--since-watermark",
        action="store_true",
        help="Fetch since MAX(contribution_receipt_date) in raw minus lookback",
    )
    parser.add_argument(
        "--lookback-days",
        type=int,
        default=int(os.environ.get("LOOKBACK_DAYS", "7")),
        help="Overlap days when using --since-watermark (default: 7)",
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

    min_date = args.min_date
    max_date = args.max_date
    allow_empty = False
    if args.since_watermark:
        if args.min_date is not None:
            parser.error("use either --since-watermark or --min-date, not both")
        min_date, mode = _watermark_min_date(args.lookback_days)
        allow_empty = True
        log.info("Contribution sync: %s", mode)
        if min_date is None:
            min_date = _bootstrap_min_date(args.cycle)
            log.info(
                "Bootstrap fetch: min_date=%s (start of FEC %d cycle)",
                min_date.isoformat(),
                args.cycle,
            )
    elif min_date is None and not args.input_file:
        min_date = _bootstrap_min_date(args.cycle)
        log.info(
            "Default min_date=%s (start of FEC %d cycle)",
            min_date.isoformat(),
            args.cycle,
        )

    # ---- fetch or load from cache ----------------------------------------
    if args.input_file:
        log.info("Loading cached data from %s", args.input_file)
        with open(args.input_file) as f:
            records = [json.loads(line) for line in f if line.strip()]
    else:
        fec = FECClient()
        log.info(
            "Fetching contributions (cycle=%d, max=%d, min_date=%s, max_date=%s)…",
            args.cycle,
            args.max_records,
            min_date.isoformat() if min_date else None,
            max_date.isoformat() if max_date else None,
        )
        raw = fec.fetch_contributions(
            two_year_transaction_period=args.cycle,
            contributor_state=args.state,
            min_amount=args.min_amount,
            min_date=min_date.isoformat() if min_date else None,
            max_date=max_date.isoformat() if max_date else None,
            max_records=args.max_records,
        )
        log.info("API returned %d records", len(raw))
        records = [r for r in (normalize(rec) for rec in raw) if r is not None]
        log.info("Normalized to %d valid records", len(records))

    if not records:
        if allow_empty:
            log.info("No new contributions in window — skipping GCS/BQ load")
            return
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
