import { useEffect, useState } from 'react';
import type { CommitteeRow, DailyRow, Meta } from '../types';
import { dataUrl } from '../lib/dataUrl';

async function loadJson<T>(path: string): Promise<T> {
  const res = await fetch(dataUrl(path));
  if (!res.ok) throw new Error(`Failed to load ${path}: ${res.status}`);
  return res.json() as Promise<T>;
}

export type VizData = {
  daily: DailyRow[];
  committees: CommitteeRow[];
  meta: Meta;
};

export function useVizData() {
  const [data, setData] = useState<VizData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const [daily, committees, meta] = await Promise.all([
          loadJson<DailyRow[]>('data/daily_contributions.json'),
          loadJson<CommitteeRow[]>('data/committee_summary.json'),
          loadJson<Meta>('data/meta.json'),
        ]);
        if (!cancelled) {
          setData({ daily, committees, meta });
          setLoading(false);
        }
      } catch (e) {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : String(e));
          setLoading(false);
        }
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  return { data, error, loading };
}
