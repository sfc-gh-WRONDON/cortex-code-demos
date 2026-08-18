/* ============================================================
   SAS Program: Transaction Enrichment & Monthly Summary
   Source: Mainframe daily batch (TRAN_DAILY_EXTRACT)
   Purpose: Enrich raw transactions with merchant data,
            calculate running balances, and produce monthly
            summary by account and merchant category.
   Last Modified: 2019-04-15 by D. Johnson
   ============================================================ */

LIBNAME RAW '/data/mainframe/daily';
LIBNAME MART '/data/sas_marts';

/* Step 1: Read raw transaction file and apply business rules */
DATA WORK.ENRICHED_TRANS;
    SET RAW.TRAN_DAILY_EXTRACT;

    /* Retain running balance across rows within same account */
    BY ACCT_NUM TXN_DT;
    RETAIN RUNNING_BAL 0;

    /* Reset running balance at start of each account */
    IF FIRST.ACCT_NUM THEN RUNNING_BAL = 0;

    /* Calculate net amount based on transaction type */
    IF TXN_TYP_CD IN ('PUR', 'CA', 'BT', 'FEE') THEN
        NET_AMT = TXN_AMT * -1;
    ELSE IF TXN_TYP_CD IN ('PMT', 'REF') THEN
        NET_AMT = TXN_AMT;
    ELSE
        NET_AMT = 0;

    RUNNING_BAL = RUNNING_BAL + NET_AMT;

    /* Flag high-value transactions */
    IF ABS(TXN_AMT) > 5000 THEN HIGH_VALUE_FLAG = 'Y';
    ELSE HIGH_VALUE_FLAG = 'N';

    /* Flag international transactions */
    IF CNTRY_CD NE 'US' THEN INTL_FLAG = 'Y';
    ELSE INTL_FLAG = 'N';

    /* Derive transaction month and quarter */
    TXN_MONTH = INTNX('MONTH', TXN_DT, 0, 'B');
    TXN_QTR = INTNX('QTR', TXN_DT, 0, 'B');

    FORMAT TXN_MONTH TXN_QTR DATE9.;

    OUTPUT;
RUN;

/* Step 2: Join with merchant reference for category enrichment */
PROC SQL;
    CREATE TABLE WORK.TRANS_WITH_MERCHANT AS
    SELECT
        t.*,
        m.MRCH_NAME,
        m.MCC_DESC AS MERCHANT_CATEGORY,
        m.RISK_TIER AS MERCHANT_RISK_TIER,
        m.MDR_RT AS MERCHANT_DISCOUNT_RATE,
        CASE
            WHEN m.RISK_TIER = 'HIGH' AND t.HIGH_VALUE_FLAG = 'Y' THEN 'REVIEW'
            WHEN t.INTL_FLAG = 'Y' AND t.HIGH_VALUE_FLAG = 'Y' THEN 'REVIEW'
            ELSE 'CLEAR'
        END AS REVIEW_STATUS
    FROM WORK.ENRICHED_TRANS t
    LEFT JOIN RAW.MERCHANT_REF m
        ON t.MRCH_ID = m.MRCH_ID;
QUIT;

/* Step 3: Monthly summary by account and merchant category */
PROC SQL;
    CREATE TABLE MART.MONTHLY_TXN_SUMMARY AS
    SELECT
        ACCT_NUM,
        TXN_MONTH,
        TXN_QTR,
        MERCHANT_CATEGORY,
        COUNT(*) AS TXN_COUNT,
        SUM(TXN_AMT) AS TOTAL_AMOUNT,
        SUM(NET_AMT) AS NET_AMOUNT,
        SUM(CASE WHEN HIGH_VALUE_FLAG = 'Y' THEN 1 ELSE 0 END) AS HIGH_VALUE_COUNT,
        SUM(CASE WHEN INTL_FLAG = 'Y' THEN 1 ELSE 0 END) AS INTL_COUNT,
        SUM(CASE WHEN REVIEW_STATUS = 'REVIEW' THEN 1 ELSE 0 END) AS FLAGGED_COUNT,
        MAX(RUNNING_BAL) AS MAX_RUNNING_BALANCE,
        CALCULATED TOTAL_AMOUNT * MERCHANT_DISCOUNT_RATE AS INTERCHANGE_REVENUE
    FROM WORK.TRANS_WITH_MERCHANT
    GROUP BY ACCT_NUM, TXN_MONTH, TXN_QTR, MERCHANT_CATEGORY, MERCHANT_DISCOUNT_RATE
    ORDER BY ACCT_NUM, TXN_MONTH;
QUIT;

PROC PRINT DATA=MART.MONTHLY_TXN_SUMMARY (OBS=20); RUN;
