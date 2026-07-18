import { useEffect, useRef } from 'react';
import * as Plot from '@observablehq/plot';
import type { CommitteeRow } from '../types';
import { formatUsd, partyColor, partyLabel } from '../lib/format';

type Props = { data: CommitteeRow[] };

export function TopCommitteesChart({ data }: Props) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!ref.current) return;
    ref.current.replaceChildren();
    if (data.length === 0) {
      ref.current.textContent = 'No committees in this filter.';
      return;
    }

    const rows = data.map((d) => ({
      name: truncate(d.committee_name || d.committee_id, 42),
      total_raised: Number(d.total_raised) || 0,
      party: partyLabel(d.party_full, d.party),
      fill: partyColor(partyLabel(d.party_full, d.party)),
    }));

    const chart = Plot.plot({
      width: Math.min(920, ref.current.clientWidth || 640),
      height: Math.max(220, rows.length * 28 + 40),
      marginLeft: 180,
      marginRight: 48,
      marginTop: 8,
      marginBottom: 28,
      style: {
        background: 'transparent',
        color: 'var(--ink-muted)',
        fontFamily: 'var(--font-body)',
        fontSize: '12px',
      },
      x: {
        label: 'Total raised',
        grid: true,
        tickFormat: (d: number) =>
          d >= 1_000_000 ? `${(d / 1_000_000).toFixed(1)}M` : `${Math.round(d / 1000)}k`,
      },
      y: { label: null },
      marks: [
        Plot.barX(rows, {
          y: 'name',
          x: 'total_raised',
          fill: 'fill',
          sort: { y: '-x' },
          tip: {
            format: {
              x: (d: number) => formatUsd(d, true),
            },
          },
        }),
        Plot.text(rows, {
          y: 'name',
          x: 'total_raised',
          text: (d: { total_raised: number }) => formatUsd(d.total_raised),
          dx: 6,
          textAnchor: 'start',
          fill: 'var(--ink)',
          fontSize: 11,
        }),
      ],
    });

    ref.current.append(chart);
    return () => chart.remove();
  }, [data]);

  return <div className='chart-host' ref={ref} />;
}

function truncate(s: string, n: number): string {
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}
