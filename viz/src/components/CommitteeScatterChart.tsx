import { useEffect, useRef } from 'react';
import * as Plot from '@observablehq/plot';
import type { CommitteeScatterPoint } from '../lib/aggregate';
import { chartWidth, formatCompactUsd, whenFontsReady } from '../lib/chartLayout';
import { formatUsd } from '../lib/format';

type Props = { data: CommitteeScatterPoint[] };

function truncate(s: string, n: number): string {
  return s.length > n ? `${s.slice(0, n - 1)}…` : s;
}

export function CommitteeScatterChart({ data }: Props) {
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
        host.textContent = 'No committees match this filter.';
        return;
      }

      const background = data.filter((d) => !d.isTop);
      const foreground = data.filter((d) => d.isTop);
      const labelTop = [...foreground]
        .sort((a, b) => b.raised - a.raised)
        .slice(0, 4);

      chart = Plot.plot({
        width: chartWidth(host.clientWidth),
        height: 320,
        marginLeft: 72,
        marginBottom: 48,
        marginTop: 12,
        marginRight: 20,
        style: {
          background: 'transparent',
          color: 'var(--ink-muted)',
          fontFamily: 'var(--font-body)',
          fontSize: '12px',
        },
        x: {
          type: 'log',
          label: 'Receipts (log scale)',
          labelArrow: false,
          grid: true,
          tickFormat: (d: number) => (d >= 1000 ? `${Math.round(d / 1000)}k` : String(Math.round(d))),
        },
        y: {
          type: 'log',
          label: 'Raised ($, log scale)',
          labelArrow: false,
          grid: true,
          tickFormat: (d: number) => formatCompactUsd(d),
        },
        marks: [
          Plot.dot(background, {
            x: 'receipts',
            y: 'raised',
            r: 'r',
            fill: 'fill',
            fillOpacity: 'fillOpacity',
            stroke: 'var(--panel)',
            strokeWidth: 0.75,
            tip: {
              format: {
                x: false,
                y: false,
                r: false,
                fill: false,
                fillOpacity: false,
                isTop: false,
                committee_id: false,
                party: (d: string) => d,
                name: (d: string) => d,
                receipts: (d: number) => d.toLocaleString(),
                raised: (d: number) => formatUsd(d, true),
                avg: (d: number) => formatUsd(d, true),
                min: (d: number) => formatUsd(d, true),
                max: (d: number) => formatUsd(d, true),
              },
            },
          }),
          Plot.dot(foreground, {
            x: 'receipts',
            y: 'raised',
            r: 'r',
            fill: 'fill',
            fillOpacity: 'fillOpacity',
            stroke: 'var(--ink)',
            strokeWidth: 1,
            tip: {
              format: {
                x: false,
                y: false,
                r: false,
                fill: false,
                fillOpacity: false,
                isTop: false,
                committee_id: false,
                party: (d: string) => d,
                name: (d: string) => d,
                receipts: (d: number) => `${d.toLocaleString()} (top by raised)`,
                raised: (d: number) => formatUsd(d, true),
                avg: (d: number) => formatUsd(d, true),
                min: (d: number) => formatUsd(d, true),
                max: (d: number) => formatUsd(d, true),
              },
            },
          }),
          Plot.text(labelTop, {
            x: 'receipts',
            y: 'raised',
            text: (d: CommitteeScatterPoint) => truncate(d.name, 22),
            dy: -10,
            fontSize: 10,
            fill: 'var(--ink-muted)',
          }),
        ],
      });

      host.append(chart);

      if (note) {
        const top = foreground.length;
        const tiny = data.filter((d) => d.receipts <= 1 && d.raised < 500).length;
        note.textContent = `${data.length} committees · dot size = avg gift · top ${top} by raised emphasized · ${tiny} single-receipt rows faded · mart-wide snapshot (party filter only).`;
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
