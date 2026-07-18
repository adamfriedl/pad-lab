-- Fail when >5% of contributions reference a committee missing from the dimension.
-- Matches the join-coverage alert in EXERCISES.md §6.
with stats as (
    select
        count(*) as total_contributions,
        countif(cm.committee_id is null) as orphan_contributions
    from {{ ref('stg_contributions') }} as c
    left join {{ ref('stg_committees') }} as cm
        using (committee_id)
)

select
    total_contributions,
    orphan_contributions,
    safe_divide(orphan_contributions, total_contributions) as orphan_ratio
from stats
where total_contributions > 0
  and safe_divide(orphan_contributions, total_contributions) > 0.05
