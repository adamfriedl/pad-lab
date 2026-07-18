-- Fail if any staging contributions have receipt dates in the future.
select
    sub_id,
    contribution_receipt_date
from {{ ref('stg_contributions') }}
where contribution_receipt_date > current_date()
