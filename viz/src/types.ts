export type DailyRow = {
  contribution_receipt_date: string;
  committee_id: string;
  committee_name: string | null;
  party: string | null;
  party_full: string | null;
  contribution_count: number;
  total_amount: number;
  avg_amount: number;
  unique_states: number;
};

export type CommitteeRow = {
  committee_id: string;
  committee_name: string;
  party: string | null;
  party_full: string | null;
  committee_type_full: string | null;
  designation_full: string | null;
  committee_state: string | null;
  total_contributions: number;
  total_raised: number;
  avg_contribution: number;
  min_contribution: number;
  max_contribution: number;
  donor_states: number;
  unique_donors: number;
  first_contribution_date: string | null;
  last_contribution_date: string | null;
};

export type Meta = {
  exported_at: string;
  project: string;
  dataset: string;
  daily_contributions_rows: number;
  committee_summary_rows: number;
  date_min: string | null;
  date_max: string | null;
  total_raised: number;
  total_contributions: number;
};
