# pad-lab contribution desk

Static dashboard for FEC marts. Live at
[adamfriedl.github.io/pad-lab](https://adamfriedl.github.io/pad-lab/).

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
