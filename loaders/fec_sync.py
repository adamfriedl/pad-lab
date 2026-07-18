"""Shared FEC fetch window helpers for contribution and committee loaders."""

from __future__ import annotations

import os
from datetime import date, timedelta


def default_fec_cycle(today: date | None = None) -> int:
    """Current FEC two-year transaction period (election cycle year).

    Odd calendar years map to the in-flight even-year cycle (2025 -> 2026).
    Override with FEC_CYCLE when needed.
    """
    if cycle := os.environ.get("FEC_CYCLE"):
        return int(cycle)
    today = today or date.today()
    return today.year + (today.year % 2)


def bootstrap_window_days() -> int:
    return int(os.environ.get("FEC_BOOTSTRAP_DAYS", "365"))


def bootstrap_min_date(cycle: int, today: date | None = None) -> date:
    """Earliest receipt date for a fresh fetch.

    Uses the later of cycle start and a rolling lookback (default 365d) so a
    capped sample lands on recent months, not year-end bulk filings from the
    full two-year period.
    """
    today = today or date.today()
    cycle_start = date(cycle - 1, 1, 1)
    window_start = today - timedelta(days=bootstrap_window_days())
    return max(cycle_start, window_start)
