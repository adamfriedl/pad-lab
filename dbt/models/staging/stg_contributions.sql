with source as (
    select * from {{ source('raw', 'fec_contributions') }}
),

cleaned as (
    select
        sub_id,
        committee_id,
        contributor_name,
        contributor_city,
        contributor_state,
        contributor_zip,
        contributor_employer,
        contributor_occupation,
        cast(contribution_receipt_amount as numeric) as amount,
        contribution_receipt_date,
        receipt_type,
        entity_type,
        is_individual,
        two_year_transaction_period,
        timestamp(_loaded_at) as loaded_at
    from source
    where sub_id is not null
      and contribution_receipt_date is not null
      and contribution_receipt_amount is not null
),

deduped as (
    select * except (row_num)
    from (
        select
            *,
            row_number() over (
                partition by sub_id
                order by loaded_at desc
            ) as row_num
        from cleaned
    )
    where row_num = 1
)

select * from deduped
