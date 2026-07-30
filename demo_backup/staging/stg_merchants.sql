with source as (
    select * from {{ source('raw_mainframe', 'merchants') }}
    where is_active = true
)

select
    MRCH_ID as merchant_id,
    MRCH_NAME as merchant_name,
    MCC_CD as merchant_category_code,
    MCC_DESC as merchant_category_description,
    MRCH_CITY as merchant_city,
    MRCH_STATE as merchant_state,
    MRCH_CNTRY as merchant_country,
    MRCH_ZIP as merchant_zip,
    MDR_RT as merchant_discount_rate,
    RISK_TIER as risk_tier,
    IS_ONLINE as is_online_merchant,
    ONBOARD_DT as onboarded_at,
    _LOADED_AT as loaded_at
from source
