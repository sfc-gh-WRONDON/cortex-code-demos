with transactions as (
    select * from {{ ref('stg_transactions') }}
),

accounts as (
    select * from {{ ref('stg_accounts') }}
),

merchants as (
    select * from {{ ref('stg_merchants') }}
),

enriched_transactions as (
    select
        t.transaction_id,
        t.account_id,
        t.merchant_id,
        t.transaction_date,
        t.transaction_time,
        date_trunc('month', t.transaction_date) as transaction_month,
        date_trunc('quarter', t.transaction_date) as transaction_quarter,
        t.transaction_amount,
        t.transaction_type,
        t.authorization_code,
        t.merchant_category_code,
        t.is_card_present,
        t.is_international,
        t.is_high_value,
        t.interchange_fee,
        t.card_network,
        a.card_type,
        a.credit_limit,
        a.current_balance,
        a.account_status,
        a.credit_union_id,
        a.credit_union_name,
        a.days_past_due,
        m.merchant_name,
        m.merchant_category_description,
        m.risk_tier as merchant_risk_tier,
        m.merchant_discount_rate,
        m.is_online_merchant,
        case
            when t.transaction_type in ('Purchase', 'Cash Advance', 'Balance Transfer', 'Fee')
                then t.transaction_amount * -1
            when t.transaction_type in ('Payment', 'Refund')
                then t.transaction_amount
            else 0
        end as net_amount,
        case
            when m.risk_tier = 'HIGH' and t.is_high_value then 'HIGH'
            when t.is_international and t.is_high_value then 'HIGH'
            when t.is_international or (not t.is_card_present and t.transaction_amount > 2000) then 'MODERATE'
            else 'LOW'
        end as risk_level
    from transactions t
    left join accounts a on t.account_id = a.account_id
    left join merchants m on t.merchant_id = m.merchant_id
)

select
    transaction_id,
    account_id,
    merchant_id,
    transaction_date,
    transaction_time,
    transaction_month,
    transaction_quarter,
    transaction_amount,
    net_amount,
    transaction_type,
    authorization_code,
    merchant_category_code,
    merchant_name,
    merchant_category_description,
    merchant_risk_tier,
    merchant_discount_rate,
    is_online_merchant,
    is_card_present,
    is_international,
    is_high_value,
    interchange_fee,
    card_network,
    card_type,
    credit_limit,
    current_balance,
    account_status,
    credit_union_id,
    credit_union_name,
    days_past_due,
    risk_level,
    transaction_amount * merchant_discount_rate as interchange_revenue
from enriched_transactions
