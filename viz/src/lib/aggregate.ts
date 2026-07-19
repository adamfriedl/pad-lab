import type { CommitteeRow } from '../types';
import { partyLabel } from './format';

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

export type ConcentrationBand = {
  key: string;
  label: string;
  detail: string;
  amount: number;
  share: number;
  fill: string;
};

export type ConcentrationSummary = {
  total: number;
  committees: number;
  top12Share: number;
  bands: ConcentrationBand[];
  ladder: Array<{
    label: string;
    amount: number;
    share: number;
    fill: string;
  }>;
};

const BAND_FILLS = {
  top1: 'var(--accent-deep)',
  top5: 'var(--accent)',
  top12: '#5a9e94',
  rest: '#c5ced9',
} as const;

/** Exclusive bands + cumulative ladder for dollar concentration. */
export function concentrationSummary(rows: CommitteeRow[]): ConcentrationSummary {
  const ranked = [...rows].sort(
    (a, b) => (Number(b.total_raised) || 0) - (Number(a.total_raised) || 0),
  );
  const amounts = ranked.map((r) => Math.max(0, Number(r.total_raised) || 0));
  const total = amounts.reduce((s, v) => s + v, 0);
  const n = ranked.length;

  const sumTo = (k: number) => amounts.slice(0, Math.min(k, n)).reduce((s, v) => s + v, 0);
  const pct = (amount: number) => (total > 0 ? amount / total : 0);

  const top1 = sumTo(1);
  const top5 = sumTo(5);
  const top12 = sumTo(12);

  const bandTop1 = top1;
  const bandTop5 = Math.max(0, top5 - top1);
  const bandTop12 = Math.max(0, top12 - top5);
  const bandRest = Math.max(0, total - top12);

  const top1Name = ranked[0]
    ? ranked[0].committee_name || ranked[0].committee_id
    : 'Largest committee';

  const bands: ConcentrationBand[] = [
    {
      key: 'top1',
      label: '#1',
      detail: top1Name,
      amount: bandTop1,
      share: pct(bandTop1),
      fill: BAND_FILLS.top1,
    },
    {
      key: 'top5',
      label: '#2–5',
      detail: 'Next four by raised',
      amount: bandTop5,
      share: pct(bandTop5),
      fill: BAND_FILLS.top5,
    },
    {
      key: 'top12',
      label: '#6–12',
      detail: 'Rest of top 12',
      amount: bandTop12,
      share: pct(bandTop12),
      fill: BAND_FILLS.top12,
    },
    {
      key: 'rest',
      label: `Rest (${Math.max(0, n - 12)})`,
      detail: 'All other committees',
      amount: bandRest,
      share: pct(bandRest),
      fill: BAND_FILLS.rest,
    },
  ].filter((b) => b.amount > 0 || b.key === 'rest');

  const ladder = [
    { label: '#1 committee', amount: top1, share: pct(top1), fill: BAND_FILLS.top1 },
    { label: 'Top 5', amount: top5, share: pct(top5), fill: BAND_FILLS.top5 },
    { label: 'Top 12', amount: top12, share: pct(top12), fill: BAND_FILLS.top12 },
    { label: `All ${n}`, amount: total, share: 1, fill: BAND_FILLS.rest },
  ];

  return {
    total,
    committees: n,
    top12Share: pct(top12),
    bands,
    ladder,
  };
}
