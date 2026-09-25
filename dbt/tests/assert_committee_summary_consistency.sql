-- Fail when a committee_summary row is internally inconsistent: min/avg/max
-- contribution out of order, contribution dates reversed, more unique donors
-- than total contributions, or any compared column is NULL (which would
-- otherwise make the comparisons above evaluate to NULL and pass silently).
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
    min_contribution is null
    or avg_contribution is null
    or max_contribution is null
    or first_contribution_date is null
    or last_contribution_date is null
    or unique_donors is null
    or total_contributions is null
    or not (min_contribution <= avg_contribution and avg_contribution <= max_contribution)
    or first_contribution_date > last_contribution_date
    or unique_donors > total_contributions
