const usd = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  maximumFractionDigits: 0,
});

const usdPrecise = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  maximumFractionDigits: 2,
});

const int = new Intl.NumberFormat('en-US');

export function formatUsd(n: number, precise = false): string {
  return (precise ? usdPrecise : usd).format(n);
}

export function formatInt(n: number): string {
  return int.format(n);
}

/** Local calendar date as YYYY-MM-DD (for filter caps). */
export function todayIso(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

export function formatDate(iso: string | null | undefined): string {
  if (!iso) return '—';
  const d = new Date(iso + (iso.length === 10 ? 'T00:00:00' : ''));
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
}

export function partyLabel(partyFull: string | null | undefined, party?: string | null): string {
  const full = (partyFull || '').trim();
  if (full) return full;
  const code = (party || '').trim();
  if (code) return code;
  return 'Unknown / other';
}

export function partyColor(label: string): string {
  const l = label.toLowerCase();
  if (l.includes('democrat')) return 'var(--party-d)';
  if (l.includes('republican')) return 'var(--party-r)';
  if (l.includes('independent') || l.includes('green') || l.includes('libertarian')) {
    return 'var(--party-i)';
  }
  return 'var(--party-o)';
}
