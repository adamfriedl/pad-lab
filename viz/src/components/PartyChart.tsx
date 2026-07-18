import { useEffect, useRef } from 'react';
import type { PartyPoint } from '../lib/aggregate';
import { chartWidth, createHorizBarChart, whenFontsReady } from '../lib/chartLayout';
import { partyColor } from '../lib/format';

type Props = { data: PartyPoint[] };

export function PartyChart({ data }: Props) {
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
        host.textContent = 'No party breakdown.';
        return;
      }

      const rows = data.map((d) => ({
        y: d.party,
        x: d.total_raised,
        fill: partyColor(d.party),
      }));

      chart = createHorizBarChart({
        rows,
        width: chartWidth(host.clientWidth, 480),
        rowHeight: 36,
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
