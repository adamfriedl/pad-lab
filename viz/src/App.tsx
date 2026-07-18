import { useMemo, useState } from 'react';
import { Filters } from './components/Filters';
import { KpiStrip } from './components/KpiStrip';
import { PartyChart } from './components/PartyChart';
import { TimeSeriesChart } from './components/TimeSeriesChart';
import { TopCommitteesChart } from './components/TopCommitteesChart';
import { useVizData } from './hooks/useVizData';
import {
  filterCommittees,
  filterDaily,
  rollupDaily,
  rollupParty,
  topCommittees,
  uniqueParties,
  type Filters as FilterState,
} from './lib/aggregate';
import { formatDate } from './lib/format';

export default function App() {
  const { data, error, loading } = useVizData();
  const [party, setParty] = useState('all');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');

  const parties = useMemo(() => (data ? uniqueParties(data.committees) : []), [data]);

  const dateBounds = useMemo(() => {
    if (!data) return { min: '', max: '' };
    const dates = data.daily
      .map((r) => r.contribution_receipt_date)
      .filter(Boolean)
      .sort();
    return { min: dates[0] || '', max: dates[dates.length - 1] || '' };
  }, [data]);

  const filters: FilterState = {
    party,
    dateFrom: dateFrom || dateBounds.min,
    dateTo: dateTo || dateBounds.max,
  };

  const filteredDaily = useMemo(
    () => (data ? filterDaily(data.daily, filters) : []),
    [data, party, dateFrom, dateTo, dateBounds.min, dateBounds.max],
  );
  const filteredCommittees = useMemo(
    () => (data ? filterCommittees(data.committees, filters) : []),
    [data, party],
  );

  const series = useMemo(() => rollupDaily(filteredDaily), [filteredDaily]);
  const partyPoints = useMemo(() => rollupParty(filteredCommittees), [filteredCommittees]);
  const leaders = useMemo(() => topCommittees(filteredCommittees, 12), [filteredCommittees]);

  const kpis = useMemo(() => {
    const totalRaised = filteredCommittees.reduce((s, r) => s + (Number(r.total_raised) || 0), 0);
    const totalContributions = filteredCommittees.reduce(
      (s, r) => s + (Number(r.total_contributions) || 0),
      0,
    );
    const span =
      series.length > 0
        ? `${formatDate(series[0].date)} – ${formatDate(series[series.length - 1].date)}`
        : '—';
    return {
      totalRaised,
      totalContributions,
      committees: filteredCommittees.length,
      dateRange: span,
    };
  }, [filteredCommittees, series]);

  if (loading) {
    return (
      <div className='shell state'>
        <p>Loading mart snapshots…</p>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className='shell state'>
        <p className='error'>Could not load dashboard data.</p>
        <p className='muted'>{error}</p>
        <p className='muted'>
          Run <code>python scripts/export_viz_data.py</code> then refresh.
        </p>
      </div>
    );
  }

  return (
    <div className='shell'>
      <div className='atmosphere' aria-hidden='true' />

      <header className='hero'>
        <p className='brand'>pad-lab</p>
        <h1>Contribution desk</h1>
        <p className='lede'>
          FEC individual contributions rolled up through BigQuery marts — the SketchPAD twin for
          this pipeline lab.
        </p>
        <p className='meta-line'>
          Snapshot {formatDate(data.meta.exported_at.slice(0, 10))} · {data.meta.dataset} ·{' '}
          {data.meta.daily_contributions_rows.toLocaleString()} daily rows
        </p>
      </header>

      <Filters
        parties={parties}
        party={party}
        dateFrom={dateFrom || dateBounds.min}
        dateTo={dateTo || dateBounds.max}
        dateMin={dateBounds.min}
        dateMax={dateBounds.max}
        onParty={setParty}
        onDateFrom={setDateFrom}
        onDateTo={setDateTo}
      />

      <KpiStrip {...kpis} />

      <section className='panel reveal' style={{ animationDelay: '160ms' }}>
        <div className='panel-head'>
          <h2>Raised over time</h2>
          <p>
            Daily totals from <code>daily_contributions</code>
          </p>
        </div>
        <TimeSeriesChart data={series} />
      </section>

      <div className='split'>
        <section className='panel reveal' style={{ animationDelay: '220ms' }}>
          <div className='panel-head'>
            <h2>Top committees</h2>
            <p>
              By total raised in <code>committee_summary</code>
            </p>
          </div>
          <TopCommitteesChart data={leaders} />
        </section>

        <section className='panel reveal' style={{ animationDelay: '280ms' }}>
          <div className='panel-head'>
            <h2>By party</h2>
            <p>Committee rollup · party affiliation</p>
          </div>
          <PartyChart data={partyPoints} />
        </section>
      </div>

      <footer className='foot'>
        <p>
          Reads committed JSON from marts only — never raw. Re-export after{' '}
          <code>./run_pipeline.sh</code>, then push to refresh{' '}
          <a href='https://adamfriedl.github.io/pad-lab/'>adamfriedl.github.io/pad-lab</a>.
        </p>
      </footer>
    </div>
  );
}
