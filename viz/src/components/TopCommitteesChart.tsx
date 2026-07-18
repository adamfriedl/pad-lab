import { useEffect, useRef } from 'react';
import type { CommitteeRow } from '../types';
import { chartWidth, createHorizBarChart, whenFontsReady } from '../lib/chartLayout';
import { formatUsd, partyColor, partyLabel } from '../lib/format';

type Props = { data: CommitteeRow[] };

export function TopCommitteesChart({ data }: Props) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const host = ref.current;
    if (!host) return;

    let chart: ReturnType<typeof createHorizBarChart> | undefined;
    let generation = 0;
    let cancelled = false;

    const render = async () => {
      const gen = ++generation;
      await whenFontsReady();
      if (cancelled || gen !== generation || !host) return;

      chart?.remove();
      host.replaceChildren();

      if (data.length === 0) {
        host.textContent = 'No committees in this filter.';
        return;
      }

      const rows = data.map((d) => ({
        y: truncate(d.committee_name || d.committee_id, 42),
        x: Number(d.total_raised) || 0,
        fill: partyColor(partyLabel(d.party_full, d.party)),
      }));

      chart = createHorizBarChart({
        rows,
        width: chartWidth(host.clientWidth),
        tipX: (value) => formatUsd(value, true),
      });

      host.append(chart);
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

  return <div className='chart-host' ref={ref} />;
}

function truncate(s: string, n: number): string {
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}
