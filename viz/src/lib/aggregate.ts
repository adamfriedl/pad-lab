import type { CommitteeRow, DailyRow } from '../types';
import { partyLabel } from './format';

export type Filters = {
  party: string;
  dateFrom: string;
  dateTo: string;
};

export function uniqueParties(rows: CommitteeRow[]): string[] {
  const set = new Set<string>();
  for (const r of rows) {
    set.add(partyLabel(r.party_full, r.party));
  }
  return [...set].sort((a, b) => a.localeCompare(b));
}

export function filterDaily(rows: DailyRow[], f: Filters): DailyRow[] {
  return rows.filter((r) => {
    if (f.party !== 'all' && partyLabel(r.party_full, r.party) !== f.party) return false;
    if (f.dateFrom && r.contribution_receipt_date < f.dateFrom) return false;
    if (f.dateTo && r.contribution_receipt_date > f.dateTo) return false;
    return true;
  });
}

export function filterCommittees(rows: CommitteeRow[], f: Filters): CommitteeRow[] {
  return rows.filter((r) => {
    if (f.party !== 'all' && partyLabel(r.party_full, r.party) !== f.party) return false;
    return true;
  });
}

export type DayPoint = { date: string; total_amount: number; contribution_count: number };

export function rollupDaily(rows: DailyRow[]): DayPoint[] {
  const map = new Map<string, DayPoint>();
  for (const r of rows) {
    const cur = map.get(r.contribution_receipt_date) || {
      date: r.contribution_receipt_date,
      total_amount: 0,
      contribution_count: 0,
    };
    cur.total_amount += Number(r.total_amount) || 0;
    cur.contribution_count += Number(r.contribution_count) || 0;
    map.set(r.contribution_receipt_date, cur);
  }
  return [...map.values()].sort((a, b) => a.date.localeCompare(b.date));
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
