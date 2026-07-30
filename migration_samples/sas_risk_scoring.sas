/* ============================================================
   SAS Program: Account Risk Scoring
   Source: Mainframe account master + transaction history
   Purpose: Calculate risk scores for each account based on
            payment behavior, utilization, and transaction patterns.
   Runs: Weekly batch (Sunday 2AM)
   Last Modified: 2020-11-08 by M. Patel
   ============================================================ */

LIBNAME RAW '/data/mainframe/daily';
LIBNAME MART '/data/sas_marts';

/* Step 1: Calculate account utilization and payment metrics */
DATA WORK.ACCT_METRICS;
    SET RAW.ACCOUNT_MASTER;
    WHERE ACCT_STAT_CD = 'A'; /* Active accounts only */

    /* Utilization ratio */
    IF CRED_LMT > 0 THEN
        UTIL_RATIO = CURR_BAL / CRED_LMT;
    ELSE
        UTIL_RATIO = 0;

    /* Payment behavior scoring */
    IF DAYS_PAST_DUE = 0 THEN PMT_SCORE = 100;
    ELSE IF DAYS_PAST_DUE <= 30 THEN PMT_SCORE = 75;
    ELSE IF DAYS_PAST_DUE <= 60 THEN PMT_SCORE = 50;
    ELSE IF DAYS_PAST_DUE <= 90 THEN PMT_SCORE = 25;
    ELSE PMT_SCORE = 0;

    /* Utilization risk tier */
    IF UTIL_RATIO < 0.30 THEN UTIL_TIER = 'LOW';
    ELSE IF UTIL_RATIO < 0.70 THEN UTIL_TIER = 'MODERATE';
    ELSE IF UTIL_RATIO < 0.90 THEN UTIL_TIER = 'HIGH';
    ELSE UTIL_TIER = 'CRITICAL';
RUN;

/* Step 2: Transaction velocity and pattern analysis (last 90 days) */
PROC SQL;
    CREATE TABLE WORK.TXN_PATTERNS AS
    SELECT
        ACCT_NUM,
        COUNT(*) AS TXN_COUNT_90D,
        SUM(TXN_AMT) AS TOTAL_SPEND_90D,
        AVG(TXN_AMT) AS AVG_TXN_AMT,
        MAX(TXN_AMT) AS MAX_TXN_AMT,
        SUM(CASE WHEN CNTRY_CD NE 'US' THEN 1 ELSE 0 END) AS INTL_TXN_COUNT,
        SUM(CASE WHEN POS_ENTRY_MD IN ('01','02') THEN 0 ELSE 1 END) AS CNP_TXN_COUNT,
        SUM(CASE WHEN TXN_AMT > 5000 THEN 1 ELSE 0 END) AS HIGH_VALUE_COUNT,
        /* Velocity check: more than 3 transactions in any single hour */
        MAX(CASE WHEN HOUR_COUNT > 3 THEN 1 ELSE 0 END) AS HAS_VELOCITY_ALERT
    FROM RAW.TRAN_DAILY_EXTRACT
    LEFT JOIN (
        SELECT ACCT_NUM AS A2, TXN_DT, HOUR(TXN_TM) AS TXN_HOUR,
               COUNT(*) AS HOUR_COUNT
        FROM RAW.TRAN_DAILY_EXTRACT
        WHERE TXN_DT >= INTNX('DAY', TODAY(), -90)
        GROUP BY A2, TXN_DT, CALCULATED TXN_HOUR
    ) vel ON ACCT_NUM = vel.A2
    WHERE TXN_DT >= INTNX('DAY', TODAY(), -90)
    GROUP BY ACCT_NUM;
QUIT;

/* Step 3: Composite risk score */
DATA MART.ACCOUNT_RISK_SCORES;
    MERGE WORK.ACCT_METRICS (IN=A)
          WORK.TXN_PATTERNS (IN=B);
    BY ACCT_NUM;

    IF A; /* Keep all accounts even if no recent transactions */

    /* Weighted composite score (0-100, higher = riskier) */
    RISK_SCORE = 0;

    /* Payment behavior (weight: 30%) */
    RISK_SCORE = RISK_SCORE + (100 - PMT_SCORE) * 0.30;

    /* Utilization (weight: 25%) */
    RISK_SCORE = RISK_SCORE + (UTIL_RATIO * 100) * 0.25;

    /* International activity (weight: 15%) */
    IF TXN_COUNT_90D > 0 THEN
        INTL_RATIO = INTL_TXN_COUNT / TXN_COUNT_90D;
    ELSE
        INTL_RATIO = 0;
    RISK_SCORE = RISK_SCORE + (INTL_RATIO * 100) * 0.15;

    /* Card-not-present ratio (weight: 15%) */
    IF TXN_COUNT_90D > 0 THEN
        CNP_RATIO = CNP_TXN_COUNT / TXN_COUNT_90D;
    ELSE
        CNP_RATIO = 0;
    RISK_SCORE = RISK_SCORE + (CNP_RATIO * 100) * 0.15;

    /* Velocity alerts (weight: 15%) */
    IF HAS_VELOCITY_ALERT = 1 THEN
        RISK_SCORE = RISK_SCORE + 15;

    /* Final tier assignment */
    IF RISK_SCORE < 25 THEN RISK_TIER = 'LOW';
    ELSE IF RISK_SCORE < 50 THEN RISK_TIER = 'MODERATE';
    ELSE IF RISK_SCORE < 75 THEN RISK_TIER = 'HIGH';
    ELSE RISK_TIER = 'CRITICAL';

    RISK_RUN_DATE = TODAY();
    FORMAT RISK_RUN_DATE DATE9.;
RUN;

PROC FREQ DATA=MART.ACCOUNT_RISK_SCORES;
    TABLES RISK_TIER / NOCUM;
    TITLE 'Account Risk Tier Distribution';
RUN;
