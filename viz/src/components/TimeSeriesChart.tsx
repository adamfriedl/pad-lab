import { useEffect, useRef } from 'react';
import * as Plot from '@observablehq/plot';
import type { DayPoint } from '../lib/aggregate';
import {
  chartWidth,
  dailyYScale,
  formatCompactUsd,
  marginLeftForTimeSeriesY,
  whenFontsReady,
} from '../lib/chartLayout';
import { formatDate, formatUsd } from '../lib/format';

type Props = { data: DayPoint[] };

export function TimeSeriesChart({ data }: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const noteRef = useRef<HTMLParagraphElement>(null);

  useEffect(() => {
    const host = ref.current;
    const note = noteRef.current;
    if (!host) return;

    let chart: ReturnType<typeof Plot.plot> | undefined;
    let generation = 0;
    let cancelled = false;

    const render = async () => {
      const gen = ++generation;
      await whenFontsReady();
      if (cancelled || gen !== generation || !host) return;

      chart?.remove();
      host.replaceChildren();
      if (note) note.textContent = '';

      if (data.length === 0) {
        host.textContent = 'No rows in this filter window.';
        return;
      }

      const { domain, inScale, outliers } = dailyYScale(data);
      const plotted = inScale.map((d) => ({
        ...d,
        date: new Date(d.date + 'T00:00:00'),
      }));
      const offScale = outliers.map((d) => ({
        ...d,
        date: new Date(d.date + 'T00:00:00'),
        plotY: domain[1],
      }));

      const marginLeft = marginLeftForTimeSeriesY(domain);

      chart = Plot.plot({
        width: chartWidth(host.clientWidth),
        height: 280,
        marginLeft,
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
          labelAnchor: 'top',
          labelArrow: false,
          grid: true,
          domain,
          nice: true,
          tickFormat: (d: number) => formatCompactUsd(d),
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
        const clipped = [...outliers].sort((a, b) => b.total_amount - a.total_amount);
        const parts = clipped.map(
          (d) => `${formatDate(d.date)} (${formatUsd(d.total_amount, true)})`,
        );
        note.textContent = `Clipped from axis — ${parts.join(', ')} — so smaller daily totals stay visible. Only ${plotted.length} receipt date${plotted.length === 1 ? '' : 's'} in this window; gaps mean no contributions that day in the sample.`;
      } else if (note && plotted.length < data.length) {
        note.textContent = `${data.length - plotted.length} day(s) with no rows in the mart for this filter.`;
      }
    };

    render();
    const ro = new ResizeObserver(render);
    ro.observe(host);
    return () => {
      cancelled = true;
      ro.disconnect();
      chart?.remove();
    };
  }, [data]);

  return (
    <>
      <div className='chart-host' ref={ref} />
      <p className='chart-note' ref={noteRef} />
    </>
  );
}
