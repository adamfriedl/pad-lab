# pad-lab contribution desk

Static dashboard for FEC marts. Live at
[adamfriedl.net/pad-lab](https://adamfriedl.net/pad-lab/).

```bash
# from repo root — refresh JSON from BigQuery marts
python scripts/export_viz_data.py          # local public/data/
python scripts/export_viz_data.py --upload # also push to GCS viz bucket

cd viz
npm install
npm run dev      # http://localhost:5173/pad-lab/
npm run build
```

- **Dev:** data in `public/data/` (committed snapshots).
- **Prod:** Pages build sets `VITE_DATA_BASE_URL` to the public GCS viz bucket.

The site never queries BigQuery at runtime.

## Data

Exports come from `pad_lab_mart` via `scripts/export_viz_data.py`:

| File                       | Mart                  | Used by                                 |
| -------------------------- | --------------------- | --------------------------------------- |
| `committee_summary.json`   | `committee_summary`   | KPIs, all charts                        |
| `meta.json`                | export metadata       | header snapshot, date span KPI          |
| `daily_contributions.json` | `daily_contributions` | exported for the lab; not charted today |

All panels reflect the **current export snapshot** — reload after a pipeline run to pick up new JSON.

## Filter

**Party** — limits every panel to committees whose affiliation matches. `All parties` shows the full export.

There is no date filter on committee charts; the date span KPI describes receipt dates present in the ingest, not a live slice of committee totals.

## What the charts show

### KPI strip

Rollups over filtered `committee_summary` rows:

- **Total raised** — sum of `total_raised`
- **Contributions** — sum of `total_contributions` (receipt count)
- **Committees** — row count after the party filter
- **Date span** — min/max receipt dates from `meta.json` for this export

### Dollar concentration (hero)

How **dollars** (not committee count) split across the fundraising tail.

- **Stacked bar** — exclusive bands: `#1`, `#2–5`, `#6–12`, and the rest of committees. Each band’s width is that slice’s share of total raised.
- **Ladder** — cumulative view: share held by the top 1, top 5, top 12, and all committees. Bars show dollars and percent of the filtered total.

The subtitle calls out the top-12 share (e.g. “Top 12 committees account for 35.9%…”). That same top 12 is the ranking in the panel below.

### Top committees

Horizontal bars for the **12 highest `total_raised`** values in the current filter. Bar color follows party affiliation (Democrat / Republican / other). Tooltip shows exact dollars.

### By party

Committee-level rollup: for each party label, **total raised** across all committees in that party and how many committees contributed. Sorted by dollars, not headcount.

## Caveats

- **Sample, not universe** — only committees that appear in this FEC pull are shown (~10k receipts in the lab sample).
- **Party gaps** — many rows lack a clean `party_full`; they roll into Unknown / other.
- **Not SketchPAD monitoring** — sparse receipt dates in the sample make a daily time series misleading; concentration + rankings fit the mart better.
