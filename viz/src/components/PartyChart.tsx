import { useEffect, useRef } from 'react';
import * as Plot from '@observablehq/plot';
import type { PartyPoint } from '../lib/aggregate';
import { formatUsd, partyColor } from '../lib/format';

type Props = { data: PartyPoint[] };

export function PartyChart({ data }: Props) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!ref.current) return;
    ref.current.replaceChildren();
    if (data.length === 0) {
      ref.current.textContent = 'No party breakdown.';
      return;
    }

    const rows = data.map((d) => ({
      ...d,
      fill: partyColor(d.party),
    }));

    const chart = Plot.plot({
      width: Math.min(480, ref.current.clientWidth || 360),
      height: Math.max(200, rows.length * 36 + 40),
      marginLeft: 140,
      marginRight: 56,
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
          y: 'party',
          x: 'total_raised',
          fill: 'fill',
          sort: { y: '-x' },
          tip: true,
        }),
        Plot.text(rows, {
          y: 'party',
          x: 'total_raised',
          text: (d: PartyPoint) => formatUsd(d.total_raised),
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
