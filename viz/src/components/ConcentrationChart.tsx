import { useEffect, useRef } from 'react';
import * as Plot from '@observablehq/plot';
import type { ConcentrationSummary } from '../lib/aggregate';
import { chartWidth, whenFontsReady } from '../lib/chartLayout';
import { formatUsd } from '../lib/format';

type Props = { data: ConcentrationSummary };

function pctLabel(share: number): string {
  return `${(share * 100).toFixed(1)}%`;
}

export function ConcentrationChart({ data }: Props) {
  const barRef = useRef<HTMLDivElement>(null);
  const ladderRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const barHost = barRef.current;
    const ladderHost = ladderRef.current;
    if (!barHost || !ladderHost) return;

    let barChart: ReturnType<typeof Plot.plot> | undefined;
    let ladderChart: ReturnType<typeof Plot.plot> | undefined;
    let generation = 0;
    let cancelled = false;

    const render = async () => {
      const gen = ++generation;
      await whenFontsReady();
      if (cancelled || gen !== generation || !barHost || !ladderHost) return;

      barChart?.remove();
      ladderChart?.remove();
      barHost.replaceChildren();
      ladderHost.replaceChildren();

      if (data.committees === 0 || data.total <= 0) {
        barHost.textContent = 'No committees match this filter.';
        return;
      }

      const width = chartWidth(barHost.clientWidth);

      barChart = Plot.plot({
        width,
        height: 56,
        marginTop: 0,
        marginBottom: 0,
        marginLeft: 0,
        marginRight: 0,
        style: {
          background: 'transparent',
          fontFamily: 'var(--font-body)',
          fontSize: '12px',
        },
        x: { domain: [0, 1], axis: null },
        y: { axis: null },
        marks: [
          Plot.barX(data.bands, {
            x: 'share',
            fill: 'fill',
            tip: {
              format: {
                fill: false,
                key: false,
                share: (d: number) => pctLabel(d),
                amount: (d: number) => formatUsd(d, true),
                label: true,
                detail: true,
              },
            },
          }),
        ],
      });
      barHost.append(barChart);

      ladderChart = Plot.plot({
        width,
        height: Math.max(160, data.ladder.length * 36 + 24),
        marginLeft: 100,
        marginRight: 72,
        marginTop: 8,
        marginBottom: 8,
        style: {
          background: 'transparent',
          color: 'var(--ink-muted)',
          fontFamily: 'var(--font-body)',
          fontSize: '12px',
        },
        x: {
          domain: [0, 1],
          axis: null,
          grid: true,
        },
        y: {
          domain: data.ladder.map((d) => d.label).reverse(),
          label: null,
        },
        marks: [
          Plot.barX(data.ladder, {
            y: 'label',
            x: 'share',
            fill: 'fill',
            tip: {
              format: {
                fill: false,
                share: (d: number) => pctLabel(d),
                amount: (d: number) => formatUsd(d, true),
              },
            },
          }),
          Plot.text(data.ladder, {
            y: 'label',
            x: 'share',
            text: (d: (typeof data.ladder)[number]) =>
              `${formatUsd(d.amount)} · ${pctLabel(d.share)}`,
            dx: 6,
            textAnchor: 'start',
            fill: 'var(--ink-muted)',
            fontSize: 11,
          }),
        ],
      });
      ladderHost.append(ladderChart);
    };

    render();
    const ro = new ResizeObserver(render);
    ro.observe(barHost);
    return () => {
      cancelled = true;
      ro.disconnect();
      barChart?.remove();
      ladderChart?.remove();
    };
  }, [data]);

  return (
    <div className='concentration'>
      <div className='concentration-bar chart-host' ref={barRef} />
      <ul className='concentration-legend'>
        {data.bands.map((b) => (
          <li key={b.key}>
            <span className='swatch' style={{ background: b.fill }} aria-hidden='true' />
            <span className='legend-label'>{b.label}</span>
            <span className='legend-pct'>{pctLabel(b.share)}</span>
          </li>
        ))}
      </ul>
      <div className='chart-host' ref={ladderRef} />
      <p className='chart-note'>
        Cumulative share of total raised from <code>committee_summary</code> (party filter applies).
        Top 12 matches the ranking panel below.
      </p>
    </div>
  );
}
