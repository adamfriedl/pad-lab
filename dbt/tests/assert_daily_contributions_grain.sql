-- Fail if any daily_contributions row has a non-positive contribution_count,
-- or if (contribution_receipt_date, committee_id) — the model's incremental
-- merge key — is not unique.
with bad_counts as (
    select
        contribution_receipt_date,
        committee_id,
        contribution_count,
        'non_positive_contribution_count' as failure_reason
    from {{ ref('daily_contributions') }}
    where contribution_count <= 0
),

duplicate_keys as (
    select
        contribution_receipt_date,
        committee_id,
        count(*) as contribution_count,
        'duplicate_merge_key' as failure_reason
    from {{ ref('daily_contributions') }}
    group by 1, 2
    having count(*) > 1
)

select * from bad_counts
union all
select * from duplicate_keys
