-- Fail when a committee_summary row is internally inconsistent: min/avg/max
-- contribution out of order, contribution dates reversed, or more unique
-- donors than total contributions.
select
    committee_id,
    min_contribution,
    avg_contribution,
    max_contribution,
    first_contribution_date,
    last_contribution_date,
    unique_donors,
    total_contributions
from {{ ref('committee_summary') }}
where
    not (min_contribution <= avg_contribution and avg_contribution <= max_contribution)
    or first_contribution_date > last_contribution_date
    or unique_donors > total_contributions
