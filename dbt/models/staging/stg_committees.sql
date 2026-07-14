with source as (
    select * from {{ source('raw', 'fec_committees') }}
),

cleaned as (
    select
        committee_id,
        name as committee_name,
        coalesce(party, '') as party,
        coalesce(party_full, '') as party_full,
        coalesce(state, '') as state,
        coalesce(designation, '') as designation,
        coalesce(designation_full, '') as designation_full,
        coalesce(committee_type, '') as committee_type,
        coalesce(committee_type_full, '') as committee_type_full,
        treasurer_name,
        first_file_date,
        timestamp(_loaded_at) as loaded_at
    from source
    where committee_id is not null
),

deduped as (
    select * except (row_num)
    from (
        select
            *,
            row_number() over (
                partition by committee_id
                order by loaded_at desc
            ) as row_num
        from cleaned
    )
    where row_num = 1
)

select * from deduped
