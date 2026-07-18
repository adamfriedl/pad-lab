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

      const { domain, inScale, outliers, negativeDays } = dailyYScale(data);
      const plotted = inScale.map((d) => ({
        ...d,
        date: new Date(d.date + 'T00:00:00'),
        plotAmount: Math.max(0, d.total_amount),
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
          labelArrow: false,
          grid: true,
          domain,
          nice: true,
          tickFormat: (d: number) => formatCompactUsd(d),
        },
        marks: [
          Plot.areaY(plotted, {
            x: 'date',
            y: 'plotAmount',
            fill: 'var(--accent)',
            fillOpacity: 0.14,
            curve: 'monotone-x',
          }),
          Plot.lineY(plotted, {
            x: 'date',
            y: 'plotAmount',
            stroke: 'var(--accent)',
            strokeWidth: 2.25,
            curve: 'monotone-x',
          }),
          Plot.dot(plotted, {
            x: 'date',
            y: 'plotAmount',
            fill: 'var(--accent)',
            r: 2.5,
            tip: {
              format: {
                x: (d: Date) => d.toLocaleDateString(),
                y: false,
                plotAmount: false,
                total_amount: (d: number) =>
                  d < 0 ? `${formatUsd(d, true)} (net negative; shown at $0)` : formatUsd(d, true),
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

      if (note) {
        const noteParts: string[] = [];
        if (outliers.length > 0) {
          const clipped = [...outliers].sort((a, b) => b.total_amount - a.total_amount);
          const parts = clipped.map(
            (d) => `${formatDate(d.date)} (${formatUsd(d.total_amount, true)})`,
          );
          noteParts.push(`Spike days clipped from axis — ${parts.join(', ')}.`);
        }
        if (negativeDays.length > 0) {
          const parts = negativeDays.map(
            (d) => `${formatDate(d.date)} (${formatUsd(d.total_amount, true)})`,
          );
          noteParts.push(`Net negative day(s) shown at $0 on chart — ${parts.join(', ')}.`);
        }
        if (noteParts.length > 0) {
          noteParts.push(
            `${plotted.length} receipt date${plotted.length === 1 ? '' : 's'} on the line; calendar gaps mean no rows that day in the sample.`,
          );
          note.textContent = noteParts.join(' ');
        } else if (plotted.length < data.length) {
          note.textContent = `${data.length - plotted.length} day(s) with no rows in the mart for this filter.`;
        }
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
