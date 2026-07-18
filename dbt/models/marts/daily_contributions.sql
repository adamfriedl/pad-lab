{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['contribution_receipt_date', 'committee_id'],
        partition_by={
            'field': 'contribution_receipt_date',
            'data_type': 'date'
        },
        cluster_by=['committee_id']
    )
}}

with new_contributions as (
    select * from {{ ref('stg_contributions') }}
    {% if is_incremental() %}
    where loaded_at > (
        select coalesce(max(last_loaded_at), timestamp('1970-01-01'))
        from {{ this }}
    )
    {% endif %}
),

affected_keys as (
    select distinct contribution_receipt_date, committee_id
    from new_contributions
),

recalculated as (
    select
        c.contribution_receipt_date,
        c.committee_id,
        count(*) as contribution_count,
        sum(c.amount) as total_amount,
        avg(c.amount) as avg_amount,
        count(distinct c.contributor_state) as unique_states,
        max(c.loaded_at) as last_loaded_at
    from {{ ref('stg_contributions') }} c
    {% if is_incremental() %}
    inner join affected_keys k
        on c.contribution_receipt_date = k.contribution_receipt_date
        and c.committee_id = k.committee_id
    {% endif %}
    group by 1, 2
)

select
    r.contribution_receipt_date,
    r.committee_id,
    coalesce(cm.committee_name, 'Unknown Committee') as committee_name,
    cm.party,
    cm.party_full,
    r.contribution_count,
    r.total_amount,
    r.avg_amount,
    r.unique_states,
    r.last_loaded_at
from recalculated r
left join {{ ref('stg_committees') }} cm using (committee_id)
