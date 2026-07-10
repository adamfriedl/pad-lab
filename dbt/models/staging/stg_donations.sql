with source as (
    select * from {{ source('raw', 'actblue_donations') }}
),

cleaned as (
    select
        donation_id,
        cast(amount as numeric) as amount,
        timestamp(created_at) as created_at,
        date(timestamp(created_at)) as donation_date,
        campaign_id,
        donor_hash,
        timestamp(_loaded_at) as loaded_at
    from source
    where amount is not null
      and donation_id is not null
),

deduped as (
    select * except (row_num)
    from (
        select
            *,
            row_number() over (
                partition by donation_id
                order by loaded_at desc
            ) as row_num
        from cleaned
    )
    where row_num = 1
)

select * from deduped
