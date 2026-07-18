-- Fail if staging is nearly empty (bad load, wrong filter, or truncated raw).
-- Lab floor: expect at least 100 contributions after a normal bootstrap run.
select count(*) as contribution_count
from {{ ref('stg_contributions') }}
having count(*) < 100
