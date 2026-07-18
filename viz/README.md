# pad-lab contribution desk

Static dashboard for FEC marts. Live at
[adamfriedl.github.io/pad-lab](https://adamfriedl.github.io/pad-lab/).

```bash
# from repo root — refresh JSON from BigQuery marts
python scripts/export_viz_data.py

cd viz
npm install
npm run dev      # http://localhost:5173/pad-lab/
npm run build
```

Data lives in `public/data/` (committed). The site never queries BigQuery at runtime.
