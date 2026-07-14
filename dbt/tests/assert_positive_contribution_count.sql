-- Every daily aggregate should have at least one contribution.
-- Returns failing rows (should be empty).
select
    contribution_receipt_date,
    committee_id,
    contribution_count
from {{ ref('daily_contributions') }}
where contribution_count <= 0
