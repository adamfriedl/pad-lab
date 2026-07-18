import { formatInt, formatUsd } from '../lib/format';

type Kpi = { label: string; value: string; hint?: string };

type Props = {
  totalRaised: number;
  totalContributions: number;
  committees: number;
  dateRange: string;
};

export function KpiStrip({ totalRaised, totalContributions, committees, dateRange }: Props) {
  const items: Kpi[] = [
    { label: 'Total raised', value: formatUsd(totalRaised), hint: 'Sum of committee totals' },
    { label: 'Contributions', value: formatInt(totalContributions), hint: 'Receipts in sample' },
    { label: 'Committees', value: formatInt(committees), hint: 'In current filter' },
    { label: 'Date span', value: dateRange, hint: 'Daily mart coverage' },
  ];

  return (
    <div className='kpi-strip' role='list'>
      {items.map((k, i) => (
        <div
          className='kpi'
          role='listitem'
          key={k.label}
          style={{ animationDelay: `${80 + i * 60}ms` }}
        >
          <span className='kpi-label'>{k.label}</span>
          <span className='kpi-value'>{k.value}</span>
          {k.hint ? <span className='kpi-hint'>{k.hint}</span> : null}
        </div>
      ))}
    </div>
  );
}
