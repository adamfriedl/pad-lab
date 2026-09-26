-- Fail if (contribution_receipt_date, committee_id) — the model's incremental
-- merge key — is not unique.
select
    contribution_receipt_date,
    committee_id,
    count(*) as contribution_count,
    'duplicate_merge_key' as failure_reason
from {{ ref('daily_contributions') }}
group by 1, 2
having count(*) > 1
