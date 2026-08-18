with source as (
    select * from {{ source('raw_mainframe', 'credit_card_transactions') }}
    where is_active = true
)

select
    TXN_ID as transaction_id,
    ACCT_NUM as account_id,
    CARD_NUM_HASH as card_number_hash,
    MRCH_ID as merchant_id,
    TXN_DT as transaction_date,
    TXN_TM as transaction_time,
    TXN_AMT as transaction_amount,
    TXN_TYP_CD as transaction_type,
    AUTH_CD as authorization_code,
    RESP_CD as response_code,
    MCC_CD as merchant_category_code,
    CRNCY_CD as currency_code,
    CNTRY_CD as country_code,
    POS_ENTRY_MD as pos_entry_mode,
    case
        when POS_ENTRY_MD in ('01', '02') then true
        else false
    end as is_card_present,
    case
        when CNTRY_CD != 'US' then true
        else false
    end as is_international,
    case
        when TXN_AMT > 5000 then true
        else false
    end as is_high_value,
    INTCHG_FEE as interchange_fee,
    NTWK_CD as card_network,
    BATCH_ID as batch_id,
    _LOADED_AT as loaded_at
from source
