type Props = {
  parties: string[];
  party: string;
  onParty: (v: string) => void;
};

export function Filters({ parties, party, onParty }: Props) {
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
    </div>
  );
}
