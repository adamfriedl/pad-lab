"""FEC (Federal Election Commission) API client.

Wraps https://api.open.fec.gov/v1 with automatic pagination and
rate-limit handling.  Requires an API key — register free at
https://api.data.gov/signup/ or use DEMO_KEY for light testing.
"""

import logging
import os
import time

import requests

from .env import load_dotenv

log = logging.getLogger(__name__)

_BASE = "https://api.open.fec.gov/v1"
_DEMO_KEY = "DEMO_KEY"
_PER_PAGE = 100
_DELAY = 0.5
_MAX_RETRIES = 3


class FECClient:

    def __init__(self, api_key: str | None = None):
        load_dotenv()
        self.api_key = api_key or os.environ.get("FEC_API_KEY", _DEMO_KEY)
        self._session = requests.Session()
        if self.api_key == _DEMO_KEY:
            log.warning(
                "Using DEMO_KEY (40 req/hr). Register at "
                "https://api.data.gov/signup/ for higher limits."
            )

    def _get(self, path: str, params: dict | None = None) -> dict:
        url = f"{_BASE}/{path.lstrip('/')}"
        params = {**(params or {}), "api_key": self.api_key}

        for attempt in range(1, _MAX_RETRIES + 1):
            resp = self._session.get(url, params=params, timeout=30)
            if resp.status_code == 429:
                wait = min(2**attempt * 5, 60)
                log.warning("Rate-limited (429). Retrying in %ds…", wait)
                time.sleep(wait)
                continue
            resp.raise_for_status()
            time.sleep(_DELAY)
            return resp.json()

        raise RuntimeError(f"FEC API rate-limited after {_MAX_RETRIES} retries")

    @staticmethod
    def _is_valid_contribution(rec: dict) -> bool:
        return bool(
            rec.get("contribution_receipt_date")
            and rec.get("contribution_receipt_amount") is not None
            and rec.get("sub_id")
        )

    def fetch_contributions(
        self,
        *,
        two_year_transaction_period: int = 2024,
        contributor_state: str | None = None,
        min_amount: int | None = None,
        min_date: str | None = None,
        max_date: str | None = None,
        max_records: int = 10000,
        sort: str = "-contribution_receipt_date",
    ) -> list[dict]:
        """Paginate Schedule A individual contributions (keyset cursor).

        Paginates until *max_records* rows pass basic validation (sub_id,
        receipt date, amount). The FEC API returns many undated rows in
        default index order; sorting by receipt date avoids a false 12/31 spike.
        """
        params: dict = {
            "two_year_transaction_period": two_year_transaction_period,
            "is_individual": "true",
            "sort": sort,
            "sort_hide_null": "true",
            "sort_null_only": "false",
            "per_page": _PER_PAGE,
        }
        if contributor_state:
            params["contributor_state"] = contributor_state
        if min_amount is not None:
            params["min_amount"] = min_amount
        if min_date:
            params["min_date"] = min_date
        if max_date:
            params["max_date"] = max_date

        results: list[dict] = []
        skipped = 0
        while len(results) < max_records:
            data = self._get("schedules/schedule_a/", params)
            page = data.get("results", [])
            if not page:
                break
            for rec in page:
                if not self._is_valid_contribution(rec):
                    skipped += 1
                    continue
                results.append(rec)
                if len(results) >= max_records:
                    break
            log.info(
                "  contributions fetched: %d valid (%d API rows skipped)",
                len(results),
                skipped,
            )

            if len(results) >= max_records:
                break

            last = (data.get("pagination") or {}).get("last_indexes")
            if not last or not last.get("last_index"):
                break
            for k, v in last.items():
                if v is not None:
                    params[k] = v

        return results[:max_records]

    def fetch_committees(
        self,
        *,
        committee_ids: list[str] | None = None,
        cycle: int = 2024,
        max_records: int = 500,
    ) -> list[dict]:
        """Fetch committee records — by ID list or by cycle."""
        if committee_ids:
            results: list[dict] = []
            # /committees/ accepts repeated committee_id filters — batch to
            # stay within per_page and avoid one HTTP call per ID.
            for i in range(0, len(committee_ids), _PER_PAGE):
                batch = committee_ids[i : i + _PER_PAGE]
                params: dict = {
                    "committee_id": batch,
                    "per_page": _PER_PAGE,
                    "page": 1,
                }
                while True:
                    data = self._get("committees/", params)
                    page = data.get("results", [])
                    if not page:
                        break
                    results.extend(page)
                    log.info("  committees fetched: %d", len(results))
                    pagination = data.get("pagination", {})
                    if params["page"] >= pagination.get("pages", 1):
                        break
                    params["page"] += 1
            return results

        params: dict = {"cycle": cycle, "per_page": _PER_PAGE}
        results: list[dict] = []
        page_num = 1
        while len(results) < max_records:
            params["page"] = page_num
            data = self._get("committees/", params)
            page = data.get("results", [])
            if not page:
                break
            results.extend(page)
            log.info("  committees fetched: %d", len(results))

            pagination = data.get("pagination", {})
            if page_num >= pagination.get("pages", 1):
                break
            page_num += 1

        return results[:max_records]
