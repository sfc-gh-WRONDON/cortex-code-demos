with source as (
    select * from {{ source('raw_mainframe', 'accounts') }}
    where is_active = true
)

select
    ACCT_NUM as account_id,
    CUST_ID as customer_id,
    ACCT_OPEN_DT as account_opened_at,
    ACCT_CLOSE_DT as account_closed_at,
    ACCT_STAT_CD as account_status,
    CARD_NTWK as card_network,
    CARD_TYP as card_type,
    CRED_LMT as credit_limit,
    CURR_BAL as current_balance,
    AVAIL_CRED as available_credit,
    APR_RT as apr_rate,
    MIN_PMT_AMT as minimum_payment_amount,
    PMT_DUE_DT as payment_due_date,
    LAST_PMT_DT as last_payment_date,
    LAST_PMT_AMT as last_payment_amount,
    DAYS_PAST_DUE as days_past_due,
    CU_ID as credit_union_id,
    CU_NAME as credit_union_name,
    _LOADED_AT as loaded_at
from source
