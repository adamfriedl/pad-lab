{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['donation_date', 'campaign_id'],
        partition_by={
            'field': 'donation_date',
            'data_type': 'date'
        },
        cluster_by=['campaign_id']
    )
}}

with new_donations as (
    select * from {{ ref('stg_donations') }}
    {% if is_incremental() %}
    where loaded_at > (select coalesce(max(last_loaded_at), timestamp('1970-01-01')) from {{ this }})
    {% endif %}
),

affected_keys as (
    select distinct donation_date, campaign_id from new_donations
),

recalculated as (
    select
        s.donation_date,
        s.campaign_id,
        count(*) as donation_count,
        sum(s.amount) as total_amount,
        max(s.loaded_at) as last_loaded_at
    from {{ ref('stg_donations') }} s
    {% if is_incremental() %}
    inner join affected_keys k
        on s.donation_date = k.donation_date
        and s.campaign_id = k.campaign_id
    {% endif %}
    group by 1, 2
)

select * from recalculated
