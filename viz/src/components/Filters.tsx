type Props = {
  parties: string[];
  party: string;
  dateFrom: string;
  dateTo: string;
  dateMin: string;
  dateMax: string;
  onParty: (v: string) => void;
  onDateFrom: (v: string) => void;
  onDateTo: (v: string) => void;
};

export function Filters({
  parties,
  party,
  dateFrom,
  dateTo,
  dateMin,
  dateMax,
  onParty,
  onDateFrom,
  onDateTo,
}: Props) {
  return (
    <div className='filters'>
      <label className='filter'>
        <span>Party</span>
        <select value={party} onChange={(e) => onParty(e.target.value)}>
          <option value='all'>All parties</option>
          {parties.map((p) => (
            <option key={p} value={p}>
              {p}
            </option>
          ))}
        </select>
      </label>
      <label className='filter'>
        <span>From</span>
        <input
          type='date'
          value={dateFrom}
          min={dateMin || undefined}
          max={dateTo || dateMax || undefined}
          onChange={(e) => onDateFrom(e.target.value)}
        />
      </label>
      <label className='filter'>
        <span>To</span>
        <input
          type='date'
          value={dateTo}
          min={dateFrom || dateMin || undefined}
          max={dateMax || undefined}
          onChange={(e) => onDateTo(e.target.value)}
        />
      </label>
    </div>
  );
}
