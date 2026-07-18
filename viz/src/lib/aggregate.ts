import type { CommitteeRow } from '../types';
import { partyColor, partyLabel } from './format';

export function uniqueParties(rows: CommitteeRow[]): string[] {
  const set = new Set<string>();
  for (const r of rows) {
    set.add(partyLabel(r.party_full, r.party));
  }
  return [...set].sort((a, b) => a.localeCompare(b));
}

export function filterCommittees(rows: CommitteeRow[], party: string): CommitteeRow[] {
  if (party === 'all') return rows;
  return rows.filter((r) => partyLabel(r.party_full, r.party) === party);
}

export type PartyPoint = { party: string; total_raised: number; committees: number };

export function rollupParty(rows: CommitteeRow[]): PartyPoint[] {
  const map = new Map<string, PartyPoint>();
  for (const r of rows) {
    const party = partyLabel(r.party_full, r.party);
    const cur = map.get(party) || { party, total_raised: 0, committees: 0 };
    cur.total_raised += Number(r.total_raised) || 0;
    cur.committees += 1;
    map.set(party, cur);
  }
  return [...map.values()].sort((a, b) => b.total_raised - a.total_raised);
}

export function topCommittees(rows: CommitteeRow[], n = 12): CommitteeRow[] {
  return [...rows]
    .sort((a, b) => (Number(b.total_raised) || 0) - (Number(a.total_raised) || 0))
    .slice(0, n);
}

export type CommitteeScatterPoint = {
  committee_id: string;
  name: string;
  receipts: number;
  raised: number;
  avg: number;
  min: number;
  max: number;
  party: string;
  fill: string;
  fillOpacity: number;
  r: number;
  isTop: boolean;
};

/** Map committee_summary rows to log-scatter points (receipts vs raised). */
export function prepareCommitteeScatter(
  rows: CommitteeRow[],
  topN = 12,
): CommitteeScatterPoint[] {
  const ranked = [...rows].sort(
    (a, b) => (Number(b.total_raised) || 0) - (Number(a.total_raised) || 0),
  );
  const topIds = new Set(ranked.slice(0, topN).map((r) => r.committee_id));

  return rows
    .map((row) => {
      const receipts = Number(row.total_contributions) || 0;
      const raised = Number(row.total_raised) || 0;
      const avg = Number(row.avg_contribution) || 0;
      if (receipts < 1 || raised <= 0) return null;

      const isTop = topIds.has(row.committee_id);
      const isTiny = receipts <= 1 && raised < 500;
      const fillOpacity = isTop ? 0.92 : isTiny ? 0.14 : 0.38;
      const r = Math.min(16, Math.max(3.5, 3 + Math.sqrt(Math.max(avg, 1)) / 6));

      return {
        committee_id: row.committee_id,
        name: row.committee_name || row.committee_id,
        receipts,
        raised,
        avg,
        min: Number(row.min_contribution) || 0,
        max: Number(row.max_contribution) || 0,
        party: partyLabel(row.party_full, row.party),
        fill: partyColor(partyLabel(row.party_full, row.party)),
        fillOpacity,
        r: isTop ? r * 1.15 : r,
        isTop,
      };
    })
    .filter((p): p is CommitteeScatterPoint => p !== null);
}
