import { useEffect, useRef } from 'react';
import * as Plot from '@observablehq/plot';
import type { DayPoint } from '../lib/aggregate';
import { dailyYScale } from '../lib/chartLayout';
import { formatDate, formatUsd } from '../lib/format';

type Props = { data: DayPoint[] };

export function TimeSeriesChart({ data }: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const noteRef = useRef<HTMLParagraphElement>(null);

  useEffect(() => {
    const host = ref.current;
    const note = noteRef.current;
    if (!host) return;

    host.replaceChildren();
    if (note) note.textContent = '';

    if (data.length === 0) {
      host.textContent = 'No rows in this filter window.';
      return;
    }

    const plotted = data.map((d) => ({
      ...d,
      date: new Date(d.date + 'T00:00:00'),
    }));

    const { domain, outliers } = dailyYScale(data);
    const inScale = plotted.filter((d) => d.total_amount <= domain[1]);
    const offScale = plotted
      .filter((d) => d.total_amount > domain[1])
      .map((d) => ({ ...d, plotY: domain[1] }));

    const chart = Plot.plot({
      width: Math.min(920, host.clientWidth || 640),
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
        domain,
        nice: true,
        tickFormat: (d: number) =>
          d >= 1_000_000
            ? `${(d / 1_000_000).toFixed(1)}M`
            : d >= 1000
              ? `${Math.round(d / 1000)}k`
              : String(d),
      },
      marks: [
        Plot.areaY(inScale, {
          x: 'date',
          y: 'total_amount',
          fill: 'var(--accent)',
          fillOpacity: 0.14,
          curve: 'monotone-x',
        }),
        Plot.lineY(inScale, {
          x: 'date',
          y: 'total_amount',
          stroke: 'var(--accent)',
          strokeWidth: 2.25,
          curve: 'monotone-x',
        }),
        Plot.dot(inScale, {
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
        ...(offScale.length > 0
          ? [
              Plot.dot(offScale, {
                x: 'date',
                y: 'plotY',
                fill: 'var(--party-r)',
                r: 4,
                tip: {
                  format: {
                    x: (d: Date) => d.toLocaleDateString(),
                    plotY: false,
                    total_amount: (d: number) => `${formatUsd(d, true)} (off scale)`,
                  },
                },
              }),
            ]
          : []),
        Plot.ruleY([0], { stroke: 'var(--rule)', strokeWidth: 1 }),
      ],
    });

    host.append(chart);

    if (note && outliers.length > 0) {
      const peak = outliers.reduce((a, b) => (a.total_amount >= b.total_amount ? a : b));
      note.textContent = `${formatDate(peak.date)} raised ${formatUsd(peak.total_amount, true)} — clipped from axis so daily variation is visible.`;
    }

    return () => chart.remove();
  }, [data]);

  return (
    <>
      <div className='chart-host' ref={ref} />
      <p className='chart-note' ref={noteRef} />
    </>
  );
}
