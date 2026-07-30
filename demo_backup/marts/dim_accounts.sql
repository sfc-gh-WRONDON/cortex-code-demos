with source as (
    select * from {{ source('raw_mainframe', 'accounts') }}
    where is_active = true
)

select
    ACCT_NUM as account_id,
    CUST_ID as customer_id,
    CU_ID as credit_union_id,
    CU_NAME as credit_union_name,
    CARD_NTWK as card_network,
    CARD_TYP as card_type,
    ACCT_OPEN_DT as account_opened_at,
    ACCT_STAT_CD as account_status,
    CRED_LMT as credit_limit,
    CURR_BAL as current_balance,
    AVAIL_CRED as available_credit,
    APR_RT as apr_rate,
    DAYS_PAST_DUE as days_past_due,
    case
        when DAYS_PAST_DUE = 0 then 'Current'
        when DAYS_PAST_DUE between 1 and 30 then '1-30 Days'
        when DAYS_PAST_DUE between 31 and 60 then '31-60 Days'
        when DAYS_PAST_DUE between 61 and 90 then '61-90 Days'
        else '90+ Days'
    end as aging_bucket,
    case when CRED_LMT > 0
        then CURR_BAL / CRED_LMT
        else 0
    end as utilization_ratio,
    datediff('day', LAST_PMT_DT, current_date()) as days_since_last_payment,
    LAST_PMT_AMT as last_payment_amount,
    _LOADED_AT as loaded_at
from source
