with transactions as (
    select * from {{ ref('stg_transactions') }}
),

merchants as (
    select * from {{ ref('stg_merchants') }}
),

enriched as (
    select
        t.transaction_id,
        t.account_id,
        t.merchant_id,
        t.transaction_date,
        t.transaction_time,
        t.transaction_amount,
        t.transaction_type,
        t.is_card_present,
        t.is_international,
        t.is_high_value,
        t.interchange_fee,
        t.card_network,
        date_trunc('month', t.transaction_date) as transaction_month,
        date_trunc('quarter', t.transaction_date) as transaction_quarter,
        m.merchant_name,
        m.merchant_category_description as merchant_category,
        m.risk_tier as merchant_risk_tier,
        m.merchant_discount_rate,
        case
            when t.transaction_type in ('Purchase', 'Cash Advance', 'Balance Transfer', 'Fee')
                then t.transaction_amount * -1
            when t.transaction_type in ('Payment', 'Refund')
                then t.transaction_amount
            else 0
        end as net_amount,
        case
            when m.risk_tier = 'HIGH' and t.is_high_value then 'REVIEW'
            when t.is_international and t.is_high_value then 'REVIEW'
            else 'CLEAR'
        end as review_status
    from transactions t
    left join merchants m on t.merchant_id = m.merchant_id
),

with_running_balance as (
    select
        *,
        sum(net_amount) over (
            partition by account_id
            order by transaction_date, transaction_time
            rows between unbounded preceding and current row
        ) as running_balance
    from enriched
)

select
    account_id,
    transaction_month,
    transaction_quarter,
    merchant_category,
    count(*) as transaction_count,
    sum(transaction_amount) as total_amount,
    sum(net_amount) as net_amount,
    sum(case when is_high_value then 1 else 0 end) as high_value_count,
    sum(case when is_international then 1 else 0 end) as international_count,
    sum(case when review_status = 'REVIEW' then 1 else 0 end) as flagged_count,
    max(running_balance) as max_running_balance,
    sum(transaction_amount) * max(merchant_discount_rate) as interchange_revenue
from with_running_balance
group by
    account_id,
    transaction_month,
    transaction_quarter,
    merchant_category
