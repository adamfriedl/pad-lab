import { useEffect, useRef } from 'react';
import * as Plot from '@observablehq/plot';
import type { DayPoint } from '../lib/aggregate';
import { formatUsd } from '../lib/format';

type Props = { data: DayPoint[] };

export function TimeSeriesChart({ data }: Props) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!ref.current) return;
    ref.current.replaceChildren();
    if (data.length === 0) {
      ref.current.textContent = 'No rows in this filter window.';
      return;
    }

    const plotted = data.map((d) => ({
      ...d,
      date: new Date(d.date + 'T00:00:00'),
    }));

    const chart = Plot.plot({
      width: Math.min(920, ref.current.clientWidth || 640),
      height: 280,
      marginLeft: 56,
      marginBottom: 36,
      marginTop: 16,
      marginRight: 16,
      style: {
        background: 'transparent',
        color: 'var(--ink-muted)',
        fontFamily: 'var(--font-body)',
        fontSize: '12px',
      },
      x: { label: null, ticks: 6 },
      y: {
        label: 'Raised ($)',
        grid: true,
        tickFormat: (d: number) =>
          d >= 1_000_000
            ? `${(d / 1_000_000).toFixed(1)}M`
            : d >= 1000
              ? `${Math.round(d / 1000)}k`
              : String(d),
      },
      marks: [
        Plot.areaY(plotted, {
          x: 'date',
          y: 'total_amount',
          fill: 'var(--accent)',
          fillOpacity: 0.14,
          curve: 'monotone-x',
        }),
        Plot.lineY(plotted, {
          x: 'date',
          y: 'total_amount',
          stroke: 'var(--accent)',
          strokeWidth: 2.25,
          curve: 'monotone-x',
        }),
        Plot.dot(plotted, {
          x: 'date',
          y: 'total_amount',
          fill: 'var(--accent)',
          r: 2.5,
          tip: {
            format: {
              x: (d: Date) => d.toLocaleDateString(),
              y: (d: number) => formatUsd(d, true),
            },
          },
        }),
        Plot.ruleY([0], { stroke: 'var(--rule)', strokeWidth: 1 }),
      ],
    });

    ref.current.append(chart);
    return () => chart.remove();
  }, [data]);

  return <div className='chart-host' ref={ref} />;
}
