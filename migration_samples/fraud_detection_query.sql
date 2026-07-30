-- Fraud Detection Query using Cortex AI Functions
-- This query scores transactions for potential fraud using AI_CLASSIFY
-- Run against: CARDWORKS_DEMO.MARTS.FCT_TRANSACTIONS

WITH transaction_context AS (
    SELECT
        transaction_id,
        account_id,
        merchant_name,
        merchant_category_description,
        transaction_amount,
        transaction_date,
        transaction_time,
        card_network,
        is_card_present,
        is_international,
        is_high_value,
        risk_level,
        merchant_risk_tier,
        days_past_due,
        CONCAT(
            'Transaction of $', transaction_amount,
            ' at ', merchant_name,
            ' (category: ', merchant_category_description, ')',
            ' on ', transaction_date, ' at ', transaction_time, '.',
            ' Card present: ', is_card_present, '.',
            ' International: ', is_international, '.',
            ' Merchant risk tier: ', merchant_risk_tier, '.',
            ' Account days past due: ', days_past_due, '.'
        ) AS transaction_description
    FROM CARDWORKS_DEMO.MARTS.FCT_TRANSACTIONS
    WHERE transaction_type = 'Purchase'
      AND transaction_date >= DATEADD('day', -30, CURRENT_DATE())
),

fraud_scored AS (
    SELECT
        transaction_id,
        account_id,
        merchant_name,
        merchant_category_description,
        transaction_amount,
        transaction_date,
        transaction_time,
        card_network,
        is_card_present,
        is_international,
        is_high_value,
        risk_level,
        SNOWFLAKE.CORTEX.AI_CLASSIFY(
            transaction_description,
            ['Legitimate Transaction', 'Suspicious - Unusual Amount', 'Suspicious - Unusual Location', 'Suspicious - Velocity Pattern', 'Fraudulent']
        ) AS fraud_classification
    FROM transaction_context
)

SELECT
    transaction_id,
    account_id,
    merchant_name,
    merchant_category_description,
    transaction_amount,
    transaction_date,
    card_network,
    is_card_present,
    is_international,
    risk_level,
    fraud_classification['label']::STRING AS fraud_label,
    fraud_classification['score']::FLOAT AS confidence_score
FROM fraud_scored
WHERE fraud_classification['label']::STRING != 'Legitimate Transaction'
ORDER BY confidence_score DESC
LIMIT 100;
