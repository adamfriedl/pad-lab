{{
    config(materialized='table')
}}

with contributions as (
    select * from {{ ref('stg_contributions') }}
),

committees as (
    select * from {{ ref('stg_committees') }}
),

contribution_stats as (
    select
        committee_id,
        count(*) as total_contributions,
        sum(amount) as total_raised,
        avg(amount) as avg_contribution,
        min(amount) as min_contribution,
        max(amount) as max_contribution,
        count(distinct contributor_state) as donor_states,
        min(contribution_receipt_date) as first_contribution_date,
        max(contribution_receipt_date) as last_contribution_date,
        count(distinct contributor_name) as unique_donors
    from contributions
    group by 1
)

select
    s.committee_id,
    coalesce(c.committee_name, 'Unknown Committee') as committee_name,
    c.party,
    c.party_full,
    c.committee_type_full,
    c.designation_full,
    c.state as committee_state,
    s.total_contributions,
    s.total_raised,
    s.avg_contribution,
    s.min_contribution,
    s.max_contribution,
    s.donor_states,
    s.unique_donors,
    s.first_contribution_date,
    s.last_contribution_date
from contribution_stats s
left join committees c using (committee_id)
