import { useMemo, useState } from 'react';
import { CommitteeScatterChart } from './components/CommitteeScatterChart';
import { Filters } from './components/Filters';
import { LoadingScreen } from './components/LoadingScreen';
import { KpiStrip } from './components/KpiStrip';
import { PartyChart } from './components/PartyChart';
import { TopCommitteesChart } from './components/TopCommitteesChart';
import { useVizData } from './hooks/useVizData';
import {
  filterCommittees,
  prepareCommitteeScatter,
  rollupParty,
  topCommittees,
  uniqueParties,
} from './lib/aggregate';
import { formatDate } from './lib/format';

export default function App() {
  const { data, error, loading } = useVizData();
  const [party, setParty] = useState('all');

  const parties = useMemo(() => (data ? uniqueParties(data.committees) : []), [data]);

  const filteredCommittees = useMemo(
    () => (data ? filterCommittees(data.committees, party) : []),
    [data, party],
  );

  const scatterPoints = useMemo(
    () => prepareCommitteeScatter(filteredCommittees),
    [filteredCommittees],
  );
  const partyPoints = useMemo(() => rollupParty(filteredCommittees), [filteredCommittees]);
  const leaders = useMemo(() => topCommittees(filteredCommittees, 12), [filteredCommittees]);

  const kpis = useMemo(() => {
    const totalRaised = filteredCommittees.reduce((s, r) => s + (Number(r.total_raised) || 0), 0);
    const totalContributions = filteredCommittees.reduce(
      (s, r) => s + (Number(r.total_contributions) || 0),
      0,
    );
    const span =
      data?.meta.date_min && data?.meta.date_max
        ? `${formatDate(data.meta.date_min)} – ${formatDate(data.meta.date_max)}`
        : '—';
    return {
      totalRaised,
      totalContributions,
      committees: filteredCommittees.length,
      dateRange: span,
    };
  }, [filteredCommittees, data]);

  if (loading) {
    return <LoadingScreen />;
  }

  if (error || !data) {
    return (
      <div className='shell state'>
        <p className='error'>Could not load dashboard data.</p>
        <p className='muted'>{error}</p>
        <p className='muted'>
          Run <code>python scripts/export_viz_data.py --upload</code> or check GCS / network access.
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
          {data.meta.committee_summary_rows.toLocaleString()} committees
        </p>
      </header>

      <Filters parties={parties} party={party} onParty={setParty} />

      <KpiStrip {...kpis} />

      <section className='panel reveal' style={{ animationDelay: '160ms' }}>
        <div className='panel-head'>
          <h2>Receipts vs raised</h2>
          <p>
            Each point is a committee in <code>committee_summary</code> — volume vs dollars (log
            scales)
          </p>
        </div>
        <CommitteeScatterChart data={scatterPoints} />
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
          Curated marts only — never raw FEC tables. Snapshots refresh after each pipeline run;
          reload this page to pick up the latest export.
        </p>
      </footer>
    </div>
  );
}
